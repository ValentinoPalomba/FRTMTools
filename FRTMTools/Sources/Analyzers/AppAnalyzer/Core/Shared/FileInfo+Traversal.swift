import Foundation

extension FileInfo {
    /// Returns a flattened list of files (and optionally directories) contained in this node.
    func flattened(includeDirectories: Bool = false) -> [FileInfo] {
        var result: [FileInfo] = []

        if includeDirectories || type != .directory {
            result.append(self)
        }

        for child in subItems ?? [] {
            result.append(contentsOf: child.flattened(includeDirectories: includeDirectories))
        }

        return result
    }
}
