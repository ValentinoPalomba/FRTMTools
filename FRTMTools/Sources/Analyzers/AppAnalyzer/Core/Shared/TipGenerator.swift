import Foundation
import CryptoKit

class TipGenerator {
    enum ExcludedFile: String, CaseIterable {
        case scInfo        = "SC_Info"
        case pkgInfo       = "PkgInfo"
        case assetsCar     = "Assets.car"
        case infoPlist     = "Info.plist"
        case codeSignature = "_CodeSignature"
        case codeResources = "CodeResources"
        case xcPrivacy = "PrivacyInfo.xcprivacy"
        case runtimeNib = "runtime.nib"
        
        static var allNames: Set<String> {
            return Set(Self.allCases.map { $0.rawValue })
        }
    }
    
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "gif", "bmp", "svg",
        "heic", "heif", "tif", "tiff", "pdf"
    ]
    
    private struct DuplicateFileKey: Hashable {
        let name: String
        let size: Int64
        let internalName: String?
        let contentHash: String
    }
    
    static func generateTips(for analysis: any AppAnalysis) -> [Tip] {
        if let ipa = analysis as? IPAAnalysis {
            return generateIPATips(for: ipa)
        } else if let apk = analysis as? APKAnalysis {
            return generateAPKTips(for: apk)
        } else {
            return []
        }
    }

    private static func generateIPATips(for analysis: IPAAnalysis) -> [Tip] {
        var tips: [Tip] = []
        let allFiles = flatten(file: analysis.rootFile)
        let binaryFiles = allFiles.filter { $0.type == .binary }
        let mainBinary: FileInfo? = {
            if let execName = analysis.executableName {
                return binaryFiles.first(where: { $0.name == execName })
            }
            return binaryFiles.first
        }()

        if let binary = mainBinary {
            if binary.size > 50 * 1024 * 1024 {
                tips.append(Tip(
                    text: "The main binary is very large (\(ByteCountFormatter.string(fromByteCount: binary.size, countStyle: .file))). Consider enabling Link Time Optimization (LTO), removing unused code, or reviewing Swift optimization flags.",
                    category: .optimization
                ))
            }
        }

        if let frameworks = analysis.rootFile.subItems?.first(where: { $0.name == "Frameworks" }) {
            if let frameworkItems = frameworks.subItems, frameworkItems.count > 20 {
                tips.append(Tip(
                    text: "The app bundles \(frameworkItems.count) frameworks. This can negatively impact startup time. Consider merging frameworks, using static linking, or removing unused dependencies.",
                    category: .optimization
                ))
            }
        }

        if let assets = allFiles.first(where: { $0.name == "Assets.car" }) {
            if assets.size > 100 * 1024 * 1024 {
                tips.append(Tip(
                    text: "The Assets.car file is extremely large (\(ByteCountFormatter.string(fromByteCount: assets.size, countStyle: .file))). Ensure images are optimized and use efficient formats such as HEIC or WebP.",
                    category: .optimization
                ))
            } else if assets.size > 50 * 1024 * 1024 {
                tips.append(Tip(
                    text: "The Assets.car file is quite large. Review if there are uncompressed or unused images.",
                    category: .warning
                ))
            }
        }

        let nonStrippedBinaries = analysis.nonStrippedBinaries
        if !nonStrippedBinaries.isEmpty {
            let totalSaving = nonStrippedBinaries.reduce(Int64(0)) { $0 + $1.potentialSaving }
            var strippingTip = Tip(
                text: "\(nonStrippedBinaries.count) binaries are not fully stripped. Removing debug symbols could save approximately \(ByteCountFormatter.string(fromByteCount: totalSaving, countStyle: .file)) and makes reverse-engineering harder.",
                category: .warning
            )
            strippingTip.kind = .unstrippedBinaries
            let sortedFindings = nonStrippedBinaries.sorted { $0.potentialSaving > $1.potentialSaving }
            for finding in sortedFindings {
                let identifier = (finding.path?.isEmpty == false ? finding.path! : nil)
                    ?? (finding.fullPath ?? finding.name)
                let savingText = ByteCountFormatter.string(fromByteCount: finding.potentialSaving, countStyle: .file)
                let sizeText = ByteCountFormatter.string(fromByteCount: finding.size, countStyle: .file)
                var subTip = Tip(
                    text: "\(identifier): file size \(sizeText), estimated saving \(savingText) when stripped.",
                    category: .warning
                )
                subTip.kind = .unstrippedBinaries
                strippingTip.subTips.append(subTip)
            }
            tips.append(strippingTip)
        }

        if analysis.allowsArbitraryLoads {
            tips.append(Tip(
                text: "App Transport Security (ATS) is disabled (NSAllowsArbitraryLoads = true). This reduces security. Instead, define exceptions only for required domains.",
                category: .warning
            ))
        }

        let duplicates = duplicateGroups(
            from: allFiles,
            filter: { file in
                let url = URL(fileURLWithPath: file.path ?? "-")
                let parentDirectory = url.deletingLastPathComponent().lastPathComponent

                return !parentDirectory.hasSuffix(".lproj")
                    && file.type != .lproj
                    && !ExcludedFile.allNames.contains(file.name)
            }
        )


        if !duplicates.isEmpty {
            let totalSavings = totalDuplicateSavings(from: duplicates)

            var duplicateImageTip = Tip(
                text: "Found \(duplicates.count) sets of duplicate files, with a potential saving of \(ByteCountFormatter.string(fromByteCount: totalSavings, countStyle: .file))",
                category: .optimization
            )
            duplicateImageTip.kind = .duplicateFiles

            for (key, files) in duplicates {
                let potentialSaving = key.size * Int64(files.count - 1)
                let paths = files.map { $0.path ?? "-" }.joined(separator: "\n")
                var subTip = Tip(
                    text: "'\(key.name)' is duplicated \(files.count) times. Potential saving: \(ByteCountFormatter.string(fromByteCount: potentialSaving, countStyle: .file))\n\(paths)",
                    category: .optimization
                )
                subTip.kind = .duplicateFiles
                duplicateImageTip.subTips.append(subTip)
            }

            tips.append(duplicateImageTip)
        }

        let duplicateImages = duplicateImageGroups(from: allFiles)
        if !duplicateImages.isEmpty {
            let totalImageSavings = totalDuplicateSavings(from: duplicateImages)
            var duplicateImagesTip = Tip(
                text: "Found \(duplicateImages.count) sets of identical images in the IPA bundle. Removing redundant copies could save \(ByteCountFormatter.string(fromByteCount: totalImageSavings, countStyle: .file)).",
                category: .optimization
            )
            duplicateImagesTip.kind = .duplicateImages

            let sortedImages = duplicateImages.values.sorted {
                duplicateSavings(for: $0) > duplicateSavings(for: $1)
            }

            for group in sortedImages {
                guard let sample = group.first else { continue }
                let saving = duplicateSavings(for: group)
                let paths = group.map(displayPath(for:)).joined(separator: "\n")
                var subTip = Tip(
                    text: "Image '\(sample.name)' has identical copies (\(group.count) total). Potential saving: \(ByteCountFormatter.string(fromByteCount: saving, countStyle: .file))\n\(paths)",
                    category: .optimization
                )
                subTip.kind = .duplicateImages
                duplicateImagesTip.subTips.append(subTip)
            }

            tips.append(duplicateImagesTip)
        }

        let imageFiles = allFiles.filter { $0.name.lowercased().hasSuffix(".png") || $0.name.lowercased().hasSuffix(".jpg") }
        for image in imageFiles where image.size > 5 * 1024 * 1024 {
            tips.append(Tip(
                text: "Image '\(image.name)' is very large (\(ByteCountFormatter.string(fromByteCount: image.size, countStyle: .file))). Consider compression or converting to modern formats (HEIC/WebP).",
                category: .optimization
            ))
        }

        let videoFiles = allFiles.filter { $0.name.lowercased().hasSuffix(".mp4") || $0.name.lowercased().hasSuffix(".mov") }
        for video in videoFiles where video.size > 10 * 1024 * 1024 {
            tips.append(Tip(
                text: "Video file '\(video.name)' is very large. Consider compressing it further or streaming from a server instead of bundling.",
                category: .optimization
            ))
        }

        let lprojDirs = allFiles.filter { $0.type == .lproj }
        if lprojDirs.count > 10 {
            tips.append(Tip(
                text: "The app contains \(lprojDirs.count) localization folders (.lproj). Verify if all of them are required.",
                category: .optimization
            ))
        }

        let debugFiles = allFiles.filter { $0.name.hasSuffix(".dSYM") || $0.name.hasSuffix(".swiftmodule") }
        if !debugFiles.isEmpty {
            tips.append(Tip(
                text: "Debug files were found (\(debugFiles.map{$0.name}.joined(separator: ", "))). These should not be included in production builds.",
                category: .warning
            ))
        }

        let jsonFiles = allFiles.filter { $0.name.lowercased().hasSuffix(".json") }
        for json in jsonFiles where json.size > 5 * 1024 * 1024 {
            tips.append(Tip(
                text: "JSON file '\(json.name)' is very large (\(ByteCountFormatter.string(fromByteCount: json.size, countStyle: .file))). Consider compressing it or fetching it remotely.",
                category: .optimization
            ))
        }

        let fontFiles = allFiles.filter { $0.name.lowercased().hasSuffix(".ttf") || $0.name.lowercased().hasSuffix(".otf") }
        if fontFiles.count > 5 {
            tips.append(Tip(
                text: "The app bundles \(fontFiles.count) custom fonts. Too many fonts can increase app size and memory usage.",
                category: .optimization
            ))
        }

        if tips.isEmpty {
            tips.append(Tip(
                text: "No major issues were detected in this analysis. Great job!",
                category: .info
            ))
        }

        return tips
    }

    private static func generateAPKTips(for analysis: APKAnalysis) -> [Tip] {
        var tips: [Tip] = []
        let files = analysis.rootFile.flattened(includeDirectories: false)

        let abiFolders = ["armeabi", "armeabi-v7a", "arm64-v8a", "x86", "x86_64", "riscv64"]
        let duplicateFiles = duplicateGroups(
            from: files,
            filter: { file in
                guard file.size > 0 else { return false }
                let loweredName = file.name.lowercased()
                if loweredName == "androidmanifest.xml" || loweredName == "resources.arsc" {
                    return false
                }

                let loweredPath = (file.path ?? "").lowercased()
                if loweredPath.contains("/meta-inf/") {
                    return false
                }
                // Ignore density/ABI folders where repeated filenames are intentional.
                if loweredPath.contains("/res/drawable") || loweredPath.contains("/res/mipmap") {
                    return false
                }
                if abiFolders.contains(where: { loweredPath.contains("/lib/\($0)/") }) {
                    return false
                }

                return true
            }
        )

        if !duplicateFiles.isEmpty {
            let totalSavings = totalDuplicateSavings(from: duplicateFiles)
            var duplicateTip = Tip(
                text: "Found \(duplicateFiles.count) sets of duplicate files in the APK/AAB bundle. Cleaning them up could save \(ByteCountFormatter.string(fromByteCount: totalSavings, countStyle: .file)).",
                category: .optimization
            )
            duplicateTip.kind = .duplicateFiles

            for (key, occurrences) in duplicateFiles {
                let potentialSaving = key.size * Int64(occurrences.count - 1)
                let paths = occurrences.map { $0.path ?? "-" }.joined(separator: "\n")
                var subTip = Tip(
                    text: "'\(key.name)' appears \(occurrences.count) times outside density/ABI splits. Potential saving: \(ByteCountFormatter.string(fromByteCount: potentialSaving, countStyle: .file))\n\(paths)",
                    category: .optimization
                )
                subTip.kind = .duplicateFiles
                duplicateTip.subTips.append(subTip)
            }

            tips.append(duplicateTip)
        }

        let duplicateImages = duplicateImageGroups(from: files)
        if !duplicateImages.isEmpty {
            let totalImageSavings = totalDuplicateSavings(from: duplicateImages)
            var duplicateImagesTip = Tip(
                text: "Found \(duplicateImages.count) sets of identical images. Removing redundant copies (even when names differ) could save \(ByteCountFormatter.string(fromByteCount: totalImageSavings, countStyle: .file)).",
                category: .optimization
            )
            duplicateImagesTip.kind = .duplicateImages

            let sortedImages = duplicateImages.values.sorted {
                duplicateSavings(for: $0) > duplicateSavings(for: $1)
            }

            for group in sortedImages {
                guard let sample = group.first else { continue }
                let saving = duplicateSavings(for: group)
                let paths = group.map(displayPath(for:)).joined(separator: "\n")
                var subTip = Tip(
                    text: "Image data reused \(group.count) times (example: '\(sample.name)'). Potential saving: \(ByteCountFormatter.string(fromByteCount: saving, countStyle: .file))\n\(paths)",
                    category: .optimization
                )
                subTip.kind = .duplicateImages
                duplicateImagesTip.subTips.append(subTip)
            }

            tips.append(duplicateImagesTip)
        }
        
        let dexFiles = files.filter { $0.name.lowercased().hasSuffix(".dex") }
        if let largestDex = dexFiles.max(by: { $0.size < $1.size }), largestDex.size > 25 * 1_048_576 {
            tips.append(Tip(
                text: "Dex file '\(largestDex.name)' is large (\(ByteCountFormatter.string(fromByteCount: largestDex.size, countStyle: .file))). Enable R8/ProGuard and shrink unused bytecode.",
                category: .optimization
            ))
        }

        if !dexFiles.isEmpty {
            let obfuscation = APKObfuscationDetector.analyze(dexFiles: dexFiles)
            if obfuscation.totalIdentifiers > 0 {
                let percent = Int((Double(obfuscation.obfuscatedIdentifiers) / Double(obfuscation.totalIdentifiers)) * 100)
                let severity: TipCategory = percent > 70 ? .security : .info
                let message: String
                if percent < 20 {
                    message = "Little to no ProGuard/R8 obfuscation detected (\(percent)%). Consider enabling code shrinking to protect intellectual property."
                } else if percent > 70 {
                    message = "Code looks obfuscated (\(percent)% of identifiers match ProGuard/R8 patterns)."
                } else {
                    message = "Partial obfuscation detected (\(percent)%). Ensure sensitive modules are protected."
                }
                var obfuscationTip = Tip(
                    text: message,
                    category: severity
                )
                obfuscationTip.subTips.append(
                    Tip(
                        text: "\(obfuscation.obfuscatedIdentifiers) of \(obfuscation.totalIdentifiers) package/class names match the obfuscated pattern (e.g. a.b.c).",
                        category: .info
                    )
                )
                tips.append(obfuscationTip)
            }
        }
        
        let nativeLibs = files.filter { $0.name.lowercased().hasSuffix(".so") }
        if nativeLibs.count > 25 {
            tips.append(Tip(
                text: "App bundles \(nativeLibs.count) native libraries (.so). Consider splitting by ABI or stripping unused architectures.",
                category: .optimization
            ))
        }
        
        if let minSDK = analysis.minSDK, let value = Int(minSDK), value < 24 {
            tips.append(Tip(
                text: "Min SDK is \(value). Raising it can simplify compatibility paths and reduce APK size.",
                category: .info
            ))
        }
        
        if let targetSDK = analysis.targetSDK, let value = Int(targetSDK), value < 33 {
            tips.append(Tip(
                text: "Target SDK \(value) is behind current Play requirements. Target API 33+ to avoid publishing issues.",
                category: .warning
            ))
        }
        
        let permissions = analysis.permissions
        let dangerous = permissions.filter { AndroidPermissionCatalog.dangerousPermissions.contains($0) }
        if !dangerous.isEmpty {
            let joined = dangerous.joined(separator: ", ")
            tips.append(Tip(
                text: "App requests \(dangerous.count) high-risk permissions (\(joined)). Double-check user messaging and actual need.",
                category: .warning
            ))
        } else if permissions.count > 20 {
            tips.append(Tip(
                text: "App declares \(permissions.count) permissions. Removing unused ones can improve install conversion.",
                category: .info
            ))
        }
        
        let resArsc = files.first(where: { $0.name.lowercased() == "resources.arsc" })
        if let resArsc, resArsc.size > 40 * 1_048_576 {
            tips.append(Tip(
                text: "resources.arsc is \(ByteCountFormatter.string(fromByteCount: resArsc.size, countStyle: .file)). Check for redundant resources or enable resource shrinking.",
                category: .optimization
            ))
        }
        
        if tips.isEmpty {
            tips.append(Tip(
                text: "No major Android-specific issues detected in this analysis. Great job!",
                category: .info
            ))
        }
        
        return tips
    }

    private static func duplicateGroups(
        from files: [FileInfo],
        filter: (FileInfo) -> Bool
    ) -> [DuplicateFileKey: [FileInfo]] {
        let candidates: [(DuplicateFileKey, FileInfo)] = files
            .filter(filter)
            .compactMap { file in
                guard file.type != .directory else { return nil }
                guard let contentHash = duplicateContentHash(for: file) else { return nil }
                return (
                    DuplicateFileKey(
                        name: file.name,
                        size: file.size,
                        internalName: file.internalName,
                        contentHash: contentHash
                    ),
                    file
                )
            }

        return Dictionary(grouping: candidates, by: { $0.0 })
            .mapValues { $0.map(\.1) }
            .filter { $0.value.count > 1 }
    }
    
    private static func totalDuplicateSavings(
        from duplicates: [DuplicateFileKey: [FileInfo]]
    ) -> Int64 {
        duplicates.reduce(0) { result, duplicate in
            let occurrences = duplicate.value.count
            guard occurrences > 1 else { return result }
            return result + duplicate.key.size * Int64(occurrences - 1)
        }
    }
    
    private static func duplicateImageGroups(from files: [FileInfo]) -> [String: [FileInfo]] {
        var groups: [String: [FileInfo]] = [:]
        for file in files {
            let ext = (file.name as NSString).pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            guard let hash = imageHash(for: file) else { continue }
            groups[hash, default: []].append(file)
        }
        return groups.filter { $0.value.count > 1 }
    }
    
    private static func hashFile(at path: String) -> String? {
        guard let stream = InputStream(fileAtPath: path) else { return nil }
        stream.open()
        defer { stream.close() }
        
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount < 0 {
                return nil
            }
            if readCount == 0 {
                break
            }
            hasher.update(data: Data(bytes: buffer, count: readCount))
        }
        
        let digest = hasher.finalize()
        return digest.map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }
    
    private static func hashData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }

    private static func duplicateContentHash(for file: FileInfo) -> String? {
        if let internalData = file.internalImageData, !internalData.isEmpty {
            return hashData(internalData)
        }
        guard let fullPath = file.fullPath else { return nil }
        return hashFile(at: fullPath)
    }

    private static func imageHash(for file: FileInfo) -> String? {
        if let internalData = file.internalImageData, !internalData.isEmpty {
            return hashData(internalData)
        }
        guard let fullPath = file.fullPath else { return nil }
        return hashFile(at: fullPath)
    }

    
    private static func duplicateSavings(for files: [FileInfo]) -> Int64 {
        guard let representative = files.first, files.count > 1 else { return 0 }
        return representative.size * Int64(files.count - 1)
    }
    
    private static func displayPath(for file: FileInfo) -> String {
        if let path = file.path, !path.isEmpty {
            return path
        }
        if let fullPath = file.fullPath {
            return fullPath
        }
        return file.name
    }
    
    private static func totalDuplicateSavings(
        from duplicates: [String: [FileInfo]]
    ) -> Int64 {
        duplicates.reduce(0) { result, entry in
            result + duplicateSavings(for: entry.value)
        }
    }

    private static func flatten(file: FileInfo) -> [FileInfo] {
        var files: [FileInfo] = []
        if let subItems = file.subItems {
            files.append(file) // include directories too
            for subItem in subItems {
                files.append(contentsOf: flatten(file: subItem))
            }
        } else {
            files.append(file)
        }
        return files
    }
}
