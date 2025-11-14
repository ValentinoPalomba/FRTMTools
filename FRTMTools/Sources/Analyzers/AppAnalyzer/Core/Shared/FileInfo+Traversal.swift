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

    /// Returns a pruned copy of the file tree containing only nodes matching the query.
    func pruned(matchingLowercased query: String) -> (file: FileInfo, size: Int64)? {
        let matchesSelf = matches(lowercasedQuery: query)

        var matchedChildren: [FileInfo] = []
        var matchedChildrenSize: Int64 = 0

        if let children = subItems {
            matchedChildren.reserveCapacity(children.count)
            for child in children {
                if let (file, size) = child.pruned(matchingLowercased: query) {
                    matchedChildren.append(file)
                    matchedChildrenSize += size
                }
            }
        }

        if matchesSelf {
            return (self, size.matchedSize(defaultingTo: matchedChildrenSize))
        }

        guard !matchedChildren.isEmpty else { return nil }

        var copy = self
        copy.subItems = matchedChildren
        if matchedChildrenSize > 0 {
            copy.size = matchedChildrenSize
        }
        return (copy, matchedChildrenSize.matchedSize(defaultingTo: size))
    }

    private func matches(lowercasedQuery query: String) -> Bool {
        if name.range(of: query, options: .caseInsensitive) != nil { return true }
        if let path, path.range(of: query, options: .caseInsensitive) != nil { return true }
        if let fullPath, fullPath.range(of: query, options: .caseInsensitive) != nil { return true }
        if let internalName, internalName.range(of: query, options: .caseInsensitive) != nil { return true }
        return false
    }
}

private extension Int64 {
    func matchedSize(defaultingTo fallback: Int64) -> Int64 {
        return self > 0 ? self : fallback
    }
}
