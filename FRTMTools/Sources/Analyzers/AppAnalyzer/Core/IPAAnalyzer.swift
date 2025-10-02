import Foundation
import AppKit
import Cocoa
import CartoolKit

// MARK: - Layout

private enum AppBundleLayout {
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
    let carAnalyzer = CarAnalyzer()
    
    func analyze(at url: URL) async throws -> IPAAnalysis? {
        switch url.pathExtension.lowercased() {
        case "ipa":
                return analyzeIPA(at: url)
        case "app":
            return performAnalysisOnAppBundle(appBundleURL: url, originalFileName: url.lastPathComponent)
        default:
            return nil
        }
    }
    
    private func analyzeIPA(at url: URL) -> IPAAnalysis? {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        
        // Clean up temporary extraction when done
        defer { try? fm.removeItem(at: tempDir) }
        
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
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
            
            return performAnalysisOnAppBundle(appBundleURL: finalAppURL, originalFileName: url.lastPathComponent, originalURL: finalAppURL)
        } catch {
            print("Error analyzing IPA: \(error)")
            return nil
        }
    }
    
    // MARK: - Core analysis
    
    private func performAnalysisOnAppBundle(appBundleURL: URL, originalFileName: String, originalURL: URL? = nil) -> IPAAnalysis? {
        let layout = detectLayout(for: appBundleURL)
        
        // Scan resources
        let rootFile = scan(url: layout.resourcesRoot, rootURL: layout.resourcesRoot, appBundleURL: layout.appURL, layout: layout)
        
        // Metadata
        let plist = extractInfoPlist(from: layout)
        let execName = plist?["CFBundleExecutable"] as? String ?? layout.appURL.deletingPathExtension().lastPathComponent
        let version = plist?["CFBundleShortVersionString"] as? String
        let build = plist?["CFBundleVersion"] as? String
        let allowsArbitraryLoads = (plist?["NSAppTransportSecurity"] as? [String: Any])?["NSAllowsArbitraryLoads"] as? Bool ?? false
        
        let icon = extractAppIcon(from: layout, plist: plist)
        
        var isStripped = false
        if let binaryURL = findMainExecutableURL(in: layout, plist: plist) {
            isStripped = isBinaryStripped(at: binaryURL)
        }
        
        return IPAAnalysis(
            url: originalURL ?? layout.appURL,
            fileName: originalFileName,
            executableName: execName,
            rootFile: rootFile,
            image: icon,
            version: version,
            buildNumber: build,
            isStripped: isStripped,
            allowsArbitraryLoads: allowsArbitraryLoads
        )
    }
    
    private func detectLayout(for appBundleURL: URL) -> AppBundleLayout {
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
    
    private func scan(url: URL, rootURL: URL, appBundleURL: URL, layout: AppBundleLayout) -> FileInfo {
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
            subItems = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))?
                .map { scan(url: $0, rootURL: rootURL, appBundleURL: appBundleURL, layout: layout) }
                .sorted(by: { $0.size > $1.size })
        } else {
            subItems = nil
        }
        
        if url.pathExtension.lowercased() == "car" {
            return analyzeCarFile(at: url, relativePath: relativePath)
        }

        
        let size = url.allocatedSize()
        let type = fileType(for: url, layout: layout)
        return FileInfo(
            path: relativePath, name: url.lastPathComponent ,
            type: type,
            size: size,
            subItems: subItems
        )
    }

    private func analyzeCarFile(at url: URL, relativePath: String) -> FileInfo {
        return carAnalyzer.analyzeCarFile(at: url, relativePath: relativePath)
    }
    
    private func fileType(for url: URL, layout: AppBundleLayout) -> FileType {
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
        
        if let binaryURL = findMainExecutableURL(in: layout, plist: extractInfoPlist(from: layout)), url == binaryURL {
            return .binary
        }
        
        switch url.pathExtension.lowercased() {
        case "framework": return .framework
        case "bundle": return .bundle
        case "car": return .assets
        case "plist": return .plist
        case "lproj": return .lproj
        default:
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
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
        let binaryAnalyzer = BinaryAnalyzer()
        return binaryAnalyzer.isBinaryStripped(at: binaryURL)
    }
}

