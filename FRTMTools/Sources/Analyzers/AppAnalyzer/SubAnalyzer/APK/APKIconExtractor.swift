import Foundation
import AppKit

final class APKIconExtractor: @unchecked Sendable {
    private let fm = FileManager.default
    private let allowedExtensions: Set<String> = ["png", "webp", "jpg", "jpeg"]

    func icon(in layout: AndroidPackageLayout, manifestInfo: AndroidManifestInfo?) -> NSImage? {
        if let iconPath = manifestInfo?.iconPath {
            let candidate = layout.rootURL.appendingPathComponent(iconPath)
            if let image = NSImage(contentsOf: candidate) {
                return image
            }
        }

        if let resourceIdentifier = manifestInfo?.iconResource,
           let image = loadResource(named: resourceIdentifier, layout: layout) {
            return image
        }

        return findBestGuessIcon(in: layout.rootURL)
    }

    private func loadResource(named identifier: String, layout: AndroidPackageLayout) -> NSImage? {
        let resourceName = sanitize(identifier)
        guard !resourceName.isEmpty else { return nil }

        let resDirectory = layout.rootURL.appendingPathComponent("res", isDirectory: true)
        guard fm.fileExists(atPath: resDirectory.path) else { return nil }

        guard let enumerator = fm.enumerator(at: resDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        var bestCandidate: URL?
        var largestSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard allowedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard fileURL.deletingPathExtension().lastPathComponent == resourceName else { continue }

            let size = fileURL.allocatedSize()
            if size > largestSize {
                largestSize = size
                bestCandidate = fileURL
            }
        }

        return bestCandidate.flatMap(NSImage.init(contentsOf:))
    }

    private func findBestGuessIcon(in rootURL: URL) -> NSImage? {
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }

        var bestCandidate: URL?
        var largestSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            let lowercased = fileURL.lastPathComponent.lowercased()
            guard lowercased.contains("ic_launcher") || lowercased.contains("appicon") else { continue }

            let size = fileURL.allocatedSize()
            if size > largestSize {
                largestSize = size
                bestCandidate = fileURL
            }
        }

        return bestCandidate.flatMap(NSImage.init(contentsOf:))
    }

    private func sanitize(_ identifier: String) -> String {
        var cleaned = identifier

        if cleaned.hasPrefix("@") {
            if let slashIndex = cleaned.firstIndex(of: "/") {
                cleaned = String(cleaned[cleaned.index(after: slashIndex)...])
            } else {
                cleaned.removeFirst()
            }
        }

        if let slashIndex = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[cleaned.index(after: slashIndex)...])
        }

        return cleaned
    }
}
