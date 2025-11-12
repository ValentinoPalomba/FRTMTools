import Foundation

struct APKManifestResult {
    let manifestURL: URL?
    let info: AndroidManifestInfo?
}

final class APKManifestAnalyzer: @unchecked Sendable {
    private let fm = FileManager.default

    func inspectManifest(atRoot rootURL: URL) -> APKManifestResult {
        let manifestURL = locateManifest(in: rootURL)
        let info = manifestURL.flatMap { AndroidManifestParser.parse(from: $0) }
        return APKManifestResult(manifestURL: manifestURL, info: info)
    }

    private func locateManifest(in rootURL: URL) -> URL? {
        let direct = rootURL.appendingPathComponent("AndroidManifest.xml")
        if fm.fileExists(atPath: direct.path) {
            return direct
        }

        let knownRelativePaths = [
            "base/manifest/AndroidManifest.xml",
            "base/AndroidManifest.xml",
            "manifest/AndroidManifest.xml"
        ]

        for relative in knownRelativePaths {
            let candidate = rootURL.appendingPathComponent(relative)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "AndroidManifest.xml" {
            return fileURL
        }

        return nil
    }
}
