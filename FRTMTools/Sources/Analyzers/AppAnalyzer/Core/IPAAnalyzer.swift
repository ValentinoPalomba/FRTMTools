import Foundation
import AppKit
import Cocoa

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
    func analyze(at url: URL) async throws -> IPAAnalysis? {
        switch url.pathExtension.lowercased() {
        case "ipa":
                var analysis = analyzeIPA(at: url)
                analysis?.url = url
                return analysis
        case "app":
            return performAnalysisOnAppBundle(appBundleURL: url, originalFileName: url.lastPathComponent)
        default:
            return nil
        }
    }
    
    private func analyzeIPA(at url: URL) -> IPAAnalysis? {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        
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
            
            return performAnalysisOnAppBundle(appBundleURL: appBundleURL, originalFileName: url.lastPathComponent)
        } catch {
            print("Error analyzing IPA: \(error)")
            return nil
        }
    }
    
    // MARK: - Core analysis
    
    private func performAnalysisOnAppBundle(appBundleURL: URL, originalFileName: String) -> IPAAnalysis? {
        let layout = detectLayout(for: appBundleURL)
        
        // Scan resources
        let rootFile = scan(url: layout.resourcesRoot, appBundleURL: layout.appURL, layout: layout)
        
        // Metadata
        let plist = extractInfoPlist(from: layout)
        let version = plist?["CFBundleShortVersionString"] as? String
        let build = plist?["CFBundleVersion"] as? String
        let allowsArbitraryLoads = (plist?["NSAppTransportSecurity"] as? [String: Any])?["NSAllowsArbitraryLoads"] as? Bool ?? false
        
        let icon = extractAppIcon(from: layout, plist: plist)
        
        var isStripped = false
        if let binaryURL = findMainExecutableURL(in: layout, plist: plist) {
            isStripped = isBinaryStripped(at: binaryURL)
        }
        
        return IPAAnalysis(
            url: layout.appURL,
            fileName: originalFileName,
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
    
    private func scan(url: URL, appBundleURL: URL, layout: AppBundleLayout) -> FileInfo {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        
        let subItems: [FileInfo]?
        if isDir.boolValue {
            subItems = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))?
                .map { scan(url: $0, appBundleURL: appBundleURL, layout: layout) }
                .sorted(by: { $0.size > $1.size })
        } else {
            subItems = nil
        }
        
        let size = allocatedSize(of: url)
        let type = fileType(for: url, layout: layout)
        
        return FileInfo(name: url.lastPathComponent, type: type, size: size, subItems: subItems)
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
    
    // MARK: - Utils
    
    func isBinaryStripped(at binaryURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        process.arguments = ["-gU", binaryURL.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return false }
            return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }
    
    func allocatedSize(of url: URL) -> Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let size = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
                total += Int64(size ?? 0)
            }
        }
        let size = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
        total += Int64(size ?? 0)
        return total
    }
}
