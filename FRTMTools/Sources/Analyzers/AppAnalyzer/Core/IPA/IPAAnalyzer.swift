import Foundation
import AppKit
import Cocoa


// MARK: - Layout

enum AppBundleLayout {
    case iOS(appURL: URL)
    case macOS(appURL: URL, contents: URL, resources: URL)

    var appURL: URL {
        switch self {
        case .iOS(let url): return url
        case .macOS(let url, _, _): return url
        }
    }

    var resourcesRoot: URL {
        switch self {
        case .iOS(let url): return url
        case .macOS(_, _, let res): return res
        }
    }

    var infoPlist: URL? {
        switch self {
        case .iOS(let url):
            let candidate = url.appendingPathComponent("Info.plist")
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        case .macOS(_, let contents, _):
            let candidate = contents.appendingPathComponent("Info.plist")
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
    }

    var executableCandidatePaths: [URL] {
        switch self {
        case .iOS(let appURL):
            let name = appURL.deletingPathExtension().lastPathComponent
            return [appURL.appendingPathComponent(name)]
        case .macOS(let appURL, let contents, _):
            let name = appURL.deletingPathExtension().lastPathComponent
            return [contents.appendingPathComponent("MacOS/\(name)")]
        }
    }
}

// MARK: - Analyzer

final class IPAAnalyzer: Analyzer {
    
    private static let excludedScanDirectories: Set<String> = ["_CodeSignature", "CodeResources"]
    private static let excludedScanExtensions: Set<String> = ["storyboardc", "lproj", "nib"]
    private static let machOMagicNumbers: Set<UInt32> = [
        0xfeedface, // MH_MAGIC
        0xcefaedfe, // MH_CIGAM
        0xfeedfacf, // MH_MAGIC_64
        0xcffaedfe, // MH_CIGAM_64
        0xcafebabe, // FAT_MAGIC
        0xbebafeca, // FAT_CIGAM
        0xcafed00d, // FAT_MAGIC_64
        0xd00dfeca  // FAT_CIGAM_64
    ]
    let carAnalyzer = CarAnalyzer()
    let dependencyAnalyzer = DependencyAnalyzer()
    let binaryAnalyzer = BinaryAnalyzer()
    
    func analyze(at url: URL) async throws -> IPAAnalysis? {
        try await analyze(at: url, progress: nil)
    }

    func analyze(at url: URL, progress: (@Sendable (String) -> Void)? = nil) async throws -> IPAAnalysis? {
        switch url.pathExtension.lowercased() {
        case "ipa":
                return analyzeIPA(at: url, progress: progress)
        case "app":
            return performAnalysisOnAppBundle(appBundleURL: url, originalFileName: url.lastPathComponent, progress: progress)
        default:
            return nil
        }
    }
    
    private func analyzeIPA(at url: URL, progress: (@Sendable (String) -> Void)? = nil) -> IPAAnalysis? {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        
        // Clean up temporary extraction when done
        defer { try? fm.removeItem(at: tempDir) }
        
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

            progress?("Unzipping \(url.lastPathComponent)…")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-qq", url.path, "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()
            
            let payloadURL = tempDir.appendingPathComponent("Payload")
            guard let appBundleURL = try fm.contentsOfDirectory(at: payloadURL, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
                return nil
            }
            
            // Persist a copy of the extracted .app into Caches so Finder reveal keeps working
            let extractedBase = CacheLocations.extractedIPAsDirectory
            CacheLocations.ensureExtractedIPAsDirectoryExists()
            let folderName = url.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString
            let targetDir = extractedBase.appendingPathComponent(folderName, isDirectory: true)
            try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let persistentAppURL = targetDir.appendingPathComponent(appBundleURL.lastPathComponent, isDirectory: true)
            if fm.fileExists(atPath: persistentAppURL.path) {
                try? fm.removeItem(at: persistentAppURL)
            }
            try? fm.copyItem(at: appBundleURL, to: persistentAppURL)
            let finalAppURL = fm.fileExists(atPath: persistentAppURL.path) ? persistentAppURL : appBundleURL
            
            progress?("Scanning extracted app bundle…")
            return performAnalysisOnAppBundle(appBundleURL: finalAppURL, originalFileName: url.lastPathComponent, originalURL: finalAppURL, progress: progress)
        } catch {
            print("Error analyzing IPA: \(error)")
            return nil
        }
    }
    
    // MARK: - Core analysis
    
    private func performAnalysisOnAppBundle(appBundleURL: URL, originalFileName: String, originalURL: URL? = nil, progress: (@Sendable (String) -> Void)? = nil) -> IPAAnalysis? {
        let layout = detectLayout(for: appBundleURL)
        
        let plist = extractInfoPlist(from: layout)
        let mainExecutableURL = findMainExecutableURL(in: layout, plist: plist)

        // Scan resources collecting binary nodes along the way
        var binaryEntries: [FileInfo] = []
        let rootFile = scan(
            url: layout.resourcesRoot,
            rootURL: layout.resourcesRoot,
            layout: layout,
            plist: plist,
            mainExecutableURL: mainExecutableURL,
            binaryCollector: &binaryEntries,
            progress: progress
        )
        
        // Metadata
        let execName = plist?["CFBundleExecutable"] as? String ?? layout.appURL.deletingPathExtension().lastPathComponent
        let version = plist?["CFBundleShortVersionString"] as? String
        let build = plist?["CFBundleVersion"] as? String
        let allowsArbitraryLoads = (plist?["NSAppTransportSecurity"] as? [String: Any])?["NSAllowsArbitraryLoads"] as? Bool ?? false
        
        let icon = extractAppIcon(from: layout, plist: plist)
        
        let binaryFiles = binaryEntries.filter { $0.fullPath != nil }
        var seenBinaryPaths = Set<String>()
        var nonStrippedBinaries: [IPAAnalysis.BinaryStrippingInfo] = []
        for binary in binaryFiles {
            guard let fullPath = binary.fullPath else { continue }
            let resolvedPath = URL(fileURLWithPath: fullPath).resolvingSymlinksInPath().path
            guard !resolvedPath.isEmpty, seenBinaryPaths.insert(resolvedPath).inserted else { continue }
            let binaryURL = URL(fileURLWithPath: resolvedPath)
            if !isBinaryStripped(at: binaryURL) {
                let saving = estimatedStrippingSaving(forBinarySize: binary.size)
                let info = IPAAnalysis.BinaryStrippingInfo(
                    name: binary.name,
                    path: binary.path,
                    fullPath: binary.fullPath,
                    size: binary.size,
                    potentialSaving: saving
                )
                nonStrippedBinaries.append(info)
            }
        }
        let isStripped = nonStrippedBinaries.isEmpty

        // Analyze dependencies
        let dependencyGraph = dependencyAnalyzer.analyzeDependencies(rootFile: rootFile, layout: layout, plist: plist)
        return IPAAnalysis(
            url: originalURL ?? layout.appURL,
            fileName: originalFileName,
            executableName: execName,
            rootFile: rootFile,
            image: icon,
            version: version,
            buildNumber: build,
            isStripped: isStripped,
            nonStrippedBinaries: nonStrippedBinaries,
            allowsArbitraryLoads: allowsArbitraryLoads,
            dependencyGraph: dependencyGraph
        )
    }
    
    func detectLayout(for appBundleURL: URL) -> AppBundleLayout {
        let contents = appBundleURL.appendingPathComponent("Contents")
        if FileManager.default.fileExists(atPath: contents.path) {
            return .macOS(
                appURL: appBundleURL,
                contents: contents,
                resources: contents
            )
        } else {
            return .iOS(appURL: appBundleURL)
        }
    }
    
    // MARK: - File scan
    
    private func scan(
        url: URL,
        rootURL: URL,
        layout: AppBundleLayout,
        plist: [String: Any]?,
        mainExecutableURL: URL?,
        binaryCollector: inout [FileInfo],
        progress: (@Sendable (String) -> Void)? = nil
    ) -> FileInfo {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if Self.excludedScanDirectories.contains(name) || Self.excludedScanExtensions.contains(ext) {
            let type: FileType = ext == "lproj" ? .lproj : (isDir.boolValue ? .directory : .file)
            
            return FileInfo(
                path: url.path.replacingOccurrences(of: rootURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                name: name,
                type: type,
                size: url.allocatedSize(),
                subItems: nil
            )
        }
        
        let relativePath = url.path.replacingOccurrences(of: rootURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let subItems: [FileInfo]?
        if isDir.boolValue {
            if let childURLs = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                var childInfos: [FileInfo] = []
                childInfos.reserveCapacity(childURLs.count)
                for childURL in childURLs {
                    let info = scan(
                        url: childURL,
                        rootURL: rootURL,
                        layout: layout,
                        plist: plist,
                        mainExecutableURL: mainExecutableURL,
                        binaryCollector: &binaryCollector,
                        progress: progress
                    )
                    childInfos.append(info)
                }
                subItems = childInfos.sorted(by: { $0.size > $1.size })
            } else {
                subItems = nil
            }
        } else {
            subItems = nil
        }
        
        if url.pathExtension.lowercased() == "car" {
            return analyzeCarFile(at: url, relativePath: relativePath)
        }

        
        let size = url.allocatedSize()
        let type = fileType(for: url, layout: layout, plist: plist, mainExecutableURL: mainExecutableURL)
        let fileInfo = FileInfo(
            path: relativePath,
            fullPath: url.path,
            name: url.lastPathComponent,
            type: type,
            size: size,
            subItems: subItems
        )
        if type == .binary {
            binaryCollector.append(fileInfo)
        }
        return fileInfo
    }

    private func analyzeCarFile(at url: URL, relativePath: String) -> FileInfo {
        return carAnalyzer.analyzeCarFile(at: url, relativePath: relativePath)
    }
    
    private func fileType(for url: URL, layout: AppBundleLayout, plist: [String: Any]?, mainExecutableURL: URL?) -> FileType {
        if url == layout.appURL {
            return .app
        }

        // macOS binaries are inside Contents/MacOS and might not have a file extension
        if case .macOS(_, let contents, _) = layout, url.path.contains(contents.appendingPathComponent("MacOS").path) {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if !isDir.boolValue {
                return .binary
            }
        }
        
        if let binaryURL = mainExecutableURL, url == binaryURL {
            return .binary
        }
        
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        case "framework": return .framework
        case "bundle": return .bundle
        case "car": return .assets
        case "plist": return .plist
        case "lproj": return .lproj
        default:
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if !isDir.boolValue, isPotentialBinaryExtension(pathExtension), isMachOBinary(at: url) {
                return .binary
            }
            return isDir.boolValue ? .directory : .file
        }
    }
    
    // MARK: - Metadata
    
    private func extractInfoPlist(from layout: AppBundleLayout) -> [String: Any]? {
        guard let plistURL = layout.infoPlist, let data = try? Data(contentsOf: plistURL) else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }
    
    private func findMainExecutableURL(in layout: AppBundleLayout, plist: [String: Any]?) -> URL? {
        let execName = plist?["CFBundleExecutable"] as? String ?? layout.appURL.deletingPathExtension().lastPathComponent
        switch layout {
        case .iOS(let appURL):
            let candidate = appURL.appendingPathComponent(execName)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        case .macOS(_, let contents, _):
            let candidate = contents.appendingPathComponent("MacOS/\(execName)")
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
    }
    
    private func extractAppIcon(from layout: AppBundleLayout, plist: [String: Any]?) -> NSImage? {
        let fm = FileManager.default
        
        switch layout {
        case .macOS(_, _, let resources):
            if let iconName = plist?["CFBundleIconFile"] as? String {
                let iconPath = resources.appendingPathComponent("Resources").appendingPathComponent(
                    iconName
                )
                if let image = NSImage(contentsOf: iconPath.pathExtension == "icns" ? iconPath : iconPath.appendingPathExtension("icns")) {
                    return image
                }
            }
        case .iOS(let appURL):
            do {
                let contents = try fm.contentsOfDirectory(at: appURL, includingPropertiesForKeys: nil)
                let candidates = contents.filter {
                    $0.lastPathComponent.lowercased().hasPrefix("appicon") && $0.pathExtension.lowercased() == "png"
                }
                if let best = candidates.sorted(by: { $0.lastPathComponent.count > $1.lastPathComponent.count }).first {
                    return NSImage(contentsOf: best)
                }
            } catch {
                print("Errore estrazione icona: \(error)")
            }
        }
        return nil
    }
    

    func isBinaryStripped(at binaryURL: URL) -> Bool {
        return binaryAnalyzer.isBinaryStripped(at: binaryURL)
    }

    private func isMachOBinary(at url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let magicData = try? handle.read(upToCount: 4), magicData.count == 4 else {
            return false
        }
        let rawValue = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }
        let bigEndianValue = UInt32(bigEndian: rawValue)
        return Self.machOMagicNumbers.contains(bigEndianValue)
    }

    private func estimatedStrippingSaving(forBinarySize size: Int64) -> Int64 {
        guard size > 0 else { return 0 }
        let estimated = Int64(Double(size) * 0.25)
        return max(estimated, 1)
    }

    private func isPotentialBinaryExtension(_ ext: String) -> Bool {
        return ext.isEmpty || ext == "dylib" || ext == "so"
    }
}
