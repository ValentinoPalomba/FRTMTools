import Foundation
import AppKit
import Cocoa

// MARK: - Analyzer Functions
protocol Analyzer {
    func analyze(at url: URL) -> IPAAnalysis?
}

final class IPAAnalyzer: Analyzer {
    func analyze(at url: URL) -> IPAAnalysis? {
        return analyzeIPA(at: url)
    }
    
    func analyzeIPA(at url: URL) -> IPAAnalysis? {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        
        defer {
            try? fm.removeItem(at: tempDir)
        }

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // 1. Unzip
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-qq", url.path, "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()
            
            // 2. Find .app bundle
            let payloadURL = tempDir.appendingPathComponent("Payload")
            guard let appBundleURL = try fm.contentsOfDirectory(at: payloadURL, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
                return nil
            }
            
            // 3. Perform recursive scan
            let rootFile = scan(url: appBundleURL, appBundleURL: appBundleURL)
            
            // 4. Extract additional info
            let (version, build) = extractVersionInfo(from: appBundleURL)
            let icon = extractAppIcon(fromIPA: url)
            let allowsArbitraryLoads = checkAllowsArbitraryLoads(from: appBundleURL)
            
            var isStripped = false
            if let binaryURL = findMainExecutableURL(in: appBundleURL) {
                isStripped = isBinaryStripped(at: binaryURL)
            }
            
            // 5. Create analysis object
            return IPAAnalysis(
                fileName: url.lastPathComponent,
                rootFile: rootFile,
                image: icon,
                version: version,
                buildNumber: build,
                isStripped: isStripped,
                allowsArbitraryLoads: allowsArbitraryLoads
            )
            
        } catch {
            print("Error analyzing IPA: \(error)")
            return nil
        }
    }

    private func scan(url: URL, appBundleURL: URL) -> FileInfo {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        
        let subItems: [FileInfo]?
        if isDir.boolValue {
            subItems = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))?
                .map { scan(url: $0, appBundleURL: appBundleURL) }
                .sorted(by: { $0.size > $1.size })
        } else {
            subItems = nil
        }
        
        let size = allocatedSize(of: url)
        let type = fileType(for: url, appBundleURL: appBundleURL)
        
        return FileInfo(name: url.lastPathComponent, type: type, size: size, subItems: subItems)
    }

    private func fileType(for url: URL, appBundleURL: URL) -> FileType {
        if url == appBundleURL {
            return .app
        }
        
        if let binaryURL = findMainExecutableURL(in: appBundleURL), url == binaryURL {
            return .binary
        }

        switch url.pathExtension.lowercased() {
        case "framework":
            return .framework
        case "bundle":
            return .bundle
        case "car":
            return .assets
        case "plist":
            return .plist
        case "lproj":
            return .lproj
        default:
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue ? .directory : .file
        }
    }

    private func findMainExecutableURL(in appBundleURL: URL) -> URL? {
        let appName = appBundleURL.deletingPathExtension().lastPathComponent
        let execURL = appBundleURL.appendingPathComponent(appName)
        if FileManager.default.fileExists(atPath: execURL.path) {
            return execURL
        }
        return nil
    }

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
        // Add the size of the directory itself
        let size = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
        total += Int64(size ?? 0)
        
        return total
    }

    func extractAppIcon(fromIPA url: URL) -> NSImage? {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // 1. Unzip
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = [url.path, "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()
            
            // 2. Trova la .app
            let payloadURL = tempDir.appendingPathComponent("Payload")
            guard let appFolder = try fm.contentsOfDirectory(at: payloadURL, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                return nil
            }
            
            // 3. Cerca i file che iniziano per "AppIcon"
            let appContents = try fm.contentsOfDirectory(at: appFolder, includingPropertiesForKeys: nil)
            let iconCandidates = appContents.filter { $0.lastPathComponent.lowercased().hasPrefix("appicon") && $0.pathExtension.lowercased() == "png" }
            
            // 4. Prendi l’icona più grande (di solito @3x)
            if let bestIcon = iconCandidates.sorted(by: { $0.lastPathComponent.count > $1.lastPathComponent.count }).first {
                return NSImage(contentsOf: bestIcon)
            }
            
        } catch {
            print("Errore estrazione icona: \(error)")
        }
        
        return nil
    }


    private func extractInfoPlist(from appBundleURL: URL) -> [String: Any]? {
        let plistURL = appBundleURL.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    private func extractVersionInfo(from appBundleURL: URL) -> (version: String?, build: String?) {
        guard let plist = extractInfoPlist(from: appBundleURL) else {
            return (nil, nil)
        }
        let version = plist["CFBundleShortVersionString"] as? String
        let build = plist["CFBundleVersion"] as? String
        return (version, build)
    }

    private func checkAllowsArbitraryLoads(from appBundleURL: URL) -> Bool {
        guard let plist = extractInfoPlist(from: appBundleURL),
              let ats = plist["NSAppTransportSecurity"] as? [String: Any],
              let allows = ats["NSAllowsArbitraryLoads"] as? Bool else {
            return false
        }
        return allows
    }

}
