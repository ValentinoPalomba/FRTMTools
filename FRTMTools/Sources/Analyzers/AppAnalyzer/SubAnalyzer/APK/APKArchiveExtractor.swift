import Foundation

struct APKExtractionResult: Sendable {
    let workingDirectory: URL
    let analysisRoot: URL
    let shouldCleanupWorkingDirectory: Bool
}

final class APKArchiveExtractor: @unchecked Sendable {
    private let fm = FileManager.default
    private let persistor = APKPayloadPersistor()

    func extractPackage(at archiveURL: URL) -> APKExtractionResult? {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("APK-\(UUID().uuidString)", isDirectory: true)
        let payloadRoot = tempRoot.appendingPathComponent("Payload", isDirectory: true)

        do {
            try fm.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
            try unzip(archiveURL, into: payloadRoot)

            if let persistedURL = persistor.persistPayload(at: payloadRoot, originalFileURL: archiveURL) {
                return APKExtractionResult(workingDirectory: tempRoot, analysisRoot: persistedURL, shouldCleanupWorkingDirectory: true)
            } else {
                return APKExtractionResult(workingDirectory: tempRoot, analysisRoot: payloadRoot, shouldCleanupWorkingDirectory: false)
            }
        } catch {
            try? fm.removeItem(at: tempRoot)
            print("⚠️ Failed to extract \(archiveURL.lastPathComponent): \(error)")
            return nil
        }
    }

    func cleanup(_ result: APKExtractionResult) {
        guard result.shouldCleanupWorkingDirectory else { return }
        try? fm.removeItem(at: result.workingDirectory)
    }

    private func unzip(_ archiveURL: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // -o avoids interactive replace prompts when archives contain duplicate entries
        process.arguments = ["-qq", "-o", archiveURL.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "APKArchiveExtractor", code: Int(process.terminationStatus), userInfo: nil)
        }
    }
}

private final class APKPayloadPersistor: @unchecked Sendable {
    private let fm = FileManager.default

    func persistPayload(at sourceURL: URL, originalFileURL: URL) -> URL? {
        CacheLocations.ensureExtractedAPKsDirectoryExists()
        let folderName = originalFileURL.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString
        let destination = CacheLocations.extractedAPKsDirectory.appendingPathComponent(folderName, isDirectory: true)

        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: sourceURL, to: destination)
            return destination
        } catch {
            print("⚠️ Unable to persist extracted payload: \(error)")
            return nil
        }
    }
}
