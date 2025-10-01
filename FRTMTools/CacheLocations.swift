import Foundation

enum CacheLocations {
    static let extractedIPAsRelativePath = "FRTMTools/ExtractedIPAs"

    static var extractedIPAsDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(extractedIPAsRelativePath, isDirectory: true)
    }

    static func ensureExtractedIPAsDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: extractedIPAsDirectory.path) {
            try? fm.createDirectory(at: extractedIPAsDirectory, withIntermediateDirectories: true)
        }
    }
}
