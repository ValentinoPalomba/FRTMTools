import Foundation

enum CacheLocations {
    static let extractedIPAsRelativePath = "FRTMTools/ExtractedIPAs"
    static let extractedAPKsRelativePath = "FRTMTools/ExtractedAPKs"

    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static var extractedIPAsDirectory: URL {
        cachesDirectory.appendingPathComponent(extractedIPAsRelativePath, isDirectory: true)
    }

    static var extractedAPKsDirectory: URL {
        cachesDirectory.appendingPathComponent(extractedAPKsRelativePath, isDirectory: true)
    }

    static func ensureExtractedIPAsDirectoryExists() {
        ensureDirectoryExists(extractedIPAsDirectory)
    }

    static func ensureExtractedAPKsDirectoryExists() {
        ensureDirectoryExists(extractedAPKsDirectory)
    }

    private static func ensureDirectoryExists(_ url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
