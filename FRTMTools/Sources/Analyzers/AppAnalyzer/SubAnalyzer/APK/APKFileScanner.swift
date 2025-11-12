import Foundation

final class APKFileScanner: @unchecked Sendable {
    private let fm = FileManager.default
    private let skippedDirectories: Set<String> = ["__MACOSX"]

    func scanRoot(at rootURL: URL) -> FileInfo {
        return scan(url: rootURL, rootURL: rootURL)
    }

    private func scan(url: URL, rootURL: URL) -> FileInfo {
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        let relativePath = url.path
            .replacingOccurrences(of: rootURL.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let subItems: [FileInfo]? = {
            guard isDir.boolValue else { return nil }
            guard !skippedDirectories.contains(url.lastPathComponent) else { return nil }
            let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            return children
                .map { scan(url: $0, rootURL: rootURL) }
                .sorted(by: { $0.size > $1.size })
        }()

        return FileInfo(
            path: relativePath.isEmpty ? nil : relativePath,
            fullPath: url.path,
            name: url.lastPathComponent,
            type: classify(url: url, isDirectory: isDir.boolValue),
            size: url.allocatedSize(),
            subItems: subItems
        )
    }

    private func classify(url: URL, isDirectory: Bool) -> FileType {
        if isDirectory { return .directory }

        switch url.pathExtension.lowercased() {
        case "dex":
            return .binary
        case "so":
            return .framework
        case "arsc":
            return .bundle
        case "xml":
            return .plist
        case "png", "jpg", "jpeg", "webp":
            return .assets
        default:
            return .file
        }
    }
}
