import Foundation

extension IPAAnalyzer {
    /// Extracts the IPA/.app and runs the bad word scanner with the provided dictionary.
    func scanBadWords(
        at url: URL,
        dictionary: Set<String>,
        progress: (@Sendable (String) -> Void)? = nil,
        shouldCancel: (@Sendable () -> Bool)? = nil
    ) async throws -> BadWordScanResult? {
        switch url.pathExtension.lowercased() {
        case "ipa":
            return scanIPAForBadWords(at: url, dictionary: dictionary, progress: progress, shouldCancel: shouldCancel)
        case "app":
            return scanAppBundleForBadWords(appBundleURL: url, dictionary: dictionary, progress: progress, shouldCancel: shouldCancel)
        default:
            return nil
        }
    }

    private func scanIPAForBadWords(at url: URL, dictionary: Set<String>, progress: (@Sendable (String) -> Void)? = nil, shouldCancel: (@Sendable () -> Bool)? = nil) -> BadWordScanResult? {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
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

            return scanAppBundleForBadWords(appBundleURL: finalAppURL, dictionary: dictionary, progress: progress, shouldCancel: shouldCancel)
        } catch {
            return nil
        }
    }

    private func scanAppBundleForBadWords(appBundleURL: URL, dictionary: Set<String>, progress: (@Sendable (String) -> Void)? = nil, shouldCancel: (@Sendable () -> Bool)? = nil) -> BadWordScanResult? {
        let layout = detectLayout(for: appBundleURL)
        progress?("Scanning for bad words…")
        let scanner = BadWordScanner(words: dictionary)
        return scanner.scan(appBundleURL: layout.resourcesRoot, progress: progress, shouldCancel: shouldCancel)
    }
}
