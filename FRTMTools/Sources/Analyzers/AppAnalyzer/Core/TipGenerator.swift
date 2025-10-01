import Foundation

class TipGenerator {
    enum ExcludedFile: String, CaseIterable {
        case scInfo        = "SC_Info"
        case pkgInfo       = "PkgInfo"
        case assetsCar     = "Assets.car"
        case infoPlist     = "Info.plist"
        case codeSignature = "_CodeSignature"
        case codeResources = "CodeResources"
        
        static var allNames: Set<String> {
            return Set(Self.allCases.map { $0.rawValue })
        }
    }
    
    static func generateTips(for analysis: IPAAnalysis) -> [Tip] {
        var tips: [Tip] = []
        let allFiles = flatten(file: analysis.rootFile)

        // 1. Large main binary
        if let binary = allFiles.first(where: { $0.type == .binary }) {
            if binary.size > 50 * 1024 * 1024 {
                tips.append(Tip(
                    text: "The main binary is very large (\(ByteCountFormatter.string(fromByteCount: binary.size, countStyle: .file))). Consider enabling Link Time Optimization (LTO), removing unused code, or reviewing Swift optimization flags.",
                    category: .optimization
                ))
            }
        }

        // 2. Too many frameworks
        if let frameworks = analysis.rootFile.subItems?.first(where: { $0.name == "Frameworks" }) {
            if let frameworkItems = frameworks.subItems, frameworkItems.count > 20 {
                tips.append(Tip(
                    text: "The app bundles \(frameworkItems.count) frameworks. This can negatively impact startup time. Consider merging frameworks, using static linking, or removing unused dependencies.",
                    category: .optimization
                ))
            }
        }

        // 3. Large Assets.car
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

        // 4. Binary not stripped
        if !analysis.isStripped, let binary = allFiles.first(where: { $0.type == .binary }) {
            let potentialSaving = ByteCountFormatter.string(fromByteCount: Int64(Double(binary.size) * 0.25), countStyle: .file)
            tips.append(Tip(
                text: "The binary is not fully stripped. Stripping could save up to \(potentialSaving) or more, reduce binary size, and make reverse-engineering more difficult.",
                category: .warning
            ))
        }

        // 5. ATS disabled
        if analysis.allowsArbitraryLoads {
            tips.append(Tip(
                text: "App Transport Security (ATS) is disabled (NSAllowsArbitraryLoads = true). This reduces security. Instead, define exceptions only for required domains.",
                category: .warning
            ))
        }

        struct FileKey: Hashable {
            let name: String
            let size: Int64
        }
        

        let duplicates = Dictionary(
            grouping: allFiles.filter { file in
                let url = URL(fileURLWithPath: file.path ?? "-")
                let parentDirectory = url.deletingLastPathComponent().lastPathComponent
                
                return !parentDirectory.hasSuffix(".lproj")
                && file.type != .lproj
                && !ExcludedFile.allNames.contains(file.name)
            },
            by: { file -> FileKey in
                FileKey(name: file.name, size: file.size)
            })
            .filter { $0.value.count > 1 }

        if !duplicates.isEmpty {
            let totalSavings = duplicates.reduce(0) { result, duplicate in
                let key = duplicate.key
                let files = duplicate.value
                return result + Int((key.size * Int64(files.count - 1)))
            }

            var duplicateImageTip = Tip(
                text: "Found \(duplicates.count) sets of duplicate files, with a potential saving of \(ByteCountFormatter.string(fromByteCount: Int64(totalSavings), countStyle: .file))",
                category: .optimization
            )

            for (key, files) in duplicates {
                let potentialSaving = key.size * Int64(files.count - 1)
                let paths = files.map { $0.path ?? "-" }.joined(separator: "\n")
                duplicateImageTip.subTips.append(Tip(
                    text: "'\(key.name)' is duplicated \(files.count) times. Potential saving: \(ByteCountFormatter.string(fromByteCount: potentialSaving, countStyle: .file))\n\(paths)",
                    category: .optimization
                ))
            }

            tips.append(duplicateImageTip)
        }

        
        let imageFiles = allFiles.filter { $0.name.lowercased().hasSuffix(".png") || $0.name.lowercased().hasSuffix(".jpg") }
        for image in imageFiles where image.size > 5 * 1024 * 1024 {
            tips.append(Tip(
                text: "Image '\(image.name)' is very large (\(ByteCountFormatter.string(fromByteCount: image.size, countStyle: .file))). Consider compression or converting to modern formats (HEIC/WebP).",
                category: .optimization
            ))
        }

        // 8. Large videos
        let videoFiles = allFiles.filter { $0.name.lowercased().hasSuffix(".mp4") || $0.name.lowercased().hasSuffix(".mov") }
        for video in videoFiles where video.size > 10 * 1024 * 1024 {
            tips.append(Tip(
                text: "Video file '\(video.name)' is very large. Consider compressing it further or streaming from a server instead of bundling.",
                category: .optimization
            ))
        }

        // 9. Too many localizations
        let lprojDirs = allFiles.filter { $0.type == .lproj }
        if lprojDirs.count > 10 {
            tips.append(Tip(
                text: "The app contains \(lprojDirs.count) localization folders (.lproj). Verify if all of them are required.",
                category: .optimization
            ))
        }

        // 10. Debug or developer files
        let debugFiles = allFiles.filter { $0.name.hasSuffix(".dSYM") || $0.name.hasSuffix(".swiftmodule") }
        if !debugFiles.isEmpty {
            tips.append(Tip(
                text: "Debug files were found (\(debugFiles.map{$0.name}.joined(separator: ", "))). These should not be included in production builds.",
                category: .warning
            ))
        }

        // 11. Large JSON or text files
        let jsonFiles = allFiles.filter { $0.name.lowercased().hasSuffix(".json") }
        for json in jsonFiles where json.size > 5 * 1024 * 1024 {
            tips.append(Tip(
                text: "JSON file '\(json.name)' is very large (\(ByteCountFormatter.string(fromByteCount: json.size, countStyle: .file))). Consider compressing it or fetching it remotely.",
                category: .optimization
            ))
        }

        // 12. Multiple bundled fonts
        let fontFiles = allFiles.filter { $0.name.lowercased().hasSuffix(".ttf") || $0.name.lowercased().hasSuffix(".otf") }
        if fontFiles.count > 5 {
            tips.append(Tip(
                text: "The app bundles \(fontFiles.count) custom fonts. Too many fonts can increase app size and memory usage.",
                category: .optimization
            ))
        }

        // Generic success tip if nothing else triggered
        if tips.isEmpty {
            tips.append(Tip(
                text: "No major issues were detected in this analysis. Great job!",
                category: .info
            ))
        }

        return tips
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
