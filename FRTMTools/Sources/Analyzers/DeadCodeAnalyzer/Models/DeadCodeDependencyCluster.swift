import Foundation

struct DeadCodeDependencyCluster: Identifiable {
    let id: String
    let roots: [DeadCodeTreeNode]
    let results: [SerializableDeadCodeResult]

    var linkedDeclarationCount: Int {
        results.reduce(0) { $0 + $1.linkedGraphIDs.count }
    }

    var fileCount: Int {
        Set(results.map(\.filePath)).count
    }

    var isLinked: Bool {
        results.count > 1
    }

    var retainedReferenceCount: Int {
        results.reduce(0) { $0 + $1.externalReferenceLocations.count }
    }

    var isPotentiallyFullyRemovable: Bool {
        let graphIDs = Set(results.map(\.graphID))
        let supportedKinds: Set<String> = [
            "associatedtype", "class", "enum", "enum case", "extension",
            "function", "imported module", "initializer", "macro",
            "precedence group", "property", "protocol", "struct", "typealias",
        ]
        return results.allSatisfy {
            $0.remediation == .deleteDeclaration &&
                $0.externalReferenceLocations.isEmpty &&
                supportedKinds.contains($0.kind) &&
                $0.isStructurallyRemovable(within: graphIDs)
        }
    }

    static func build(from results: [SerializableDeadCodeResult]) -> [DeadCodeDependencyCluster] {
        let resultByID = Dictionary(results.map { ($0.graphID, $0) }, uniquingKeysWith: { first, _ in first })
        let validIDs = Set(resultByID.keys)
        var components = DeadCodeUnionFind(ids: validIDs)

        for result in results {
            for neighbor in result.linkedGraphIDs where validIDs.contains(neighbor) {
                components.union(result.graphID, neighbor)
            }
            if let parentID = result.parentGraphID, validIDs.contains(parentID) {
                components.union(result.graphID, parentID)
            }
        }

        let resultsByComponent = Dictionary(grouping: resultByID.values) {
            components.root(of: $0.graphID)
        }
        let clusters = resultsByComponent.map { componentID, componentValues in
            let componentResults = componentValues.sorted(by: resultSort)
            let componentIDs = Set(componentResults.map(\.graphID))
            let roots = makeTreeRoots(
                componentIDs: componentIDs,
                resultByID: resultByID
            )

            return DeadCodeDependencyCluster(
                id: componentIDs.min() ?? componentID,
                roots: roots,
                results: componentResults
            )
        }

        return clusters.sorted {
            if $0.results.count == $1.results.count {
                return $0.id < $1.id
            }
            return $0.results.count > $1.results.count
        }
    }

    private static func makeTreeRoots(
        componentIDs: Set<String>,
        resultByID: [String: SerializableDeadCodeResult]
    ) -> [DeadCodeTreeNode] {
        let componentResults = componentIDs.compactMap { resultByID[$0] }
        let childrenByParent = Dictionary(
            grouping: componentResults.filter {
                $0.parentGraphID.map(componentIDs.contains) == true
            },
            by: { $0.parentGraphID! }
        )
        let orderedStarts = componentResults
            .filter { result in
                guard let parentID = result.parentGraphID else { return true }
                return !componentIDs.contains(parentID)
            }
            .sorted(by: resultSort)
            .map(\.graphID)
        var visited = Set<String>()
        var roots: [DeadCodeTreeNode] = []

        func buildNode(_ id: String) -> DeadCodeTreeNode? {
            guard visited.insert(id).inserted, let result = resultByID[id] else {
                return nil
            }

            let children = childrenByParent[id, default: []]
                .sorted(by: resultSort)
                .compactMap { buildNode($0.graphID) }

            return DeadCodeTreeNode(
                result: result,
                children: children.isEmpty ? nil : children
            )
        }

        for startID in orderedStarts {
            if let root = buildNode(startID) {
                roots.append(root)
            }
        }
        for remainingID in componentIDs.subtracting(visited).sorted() {
            if let root = buildNode(remainingID) {
                roots.append(root)
            }
        }

        return roots
    }

    private static func resultSort(
        _ lhs: SerializableDeadCodeResult,
        _ rhs: SerializableDeadCodeResult
    ) -> Bool {
        if lhs.filePath == rhs.filePath {
            return lhs.location.localizedStandardCompare(rhs.location) == .orderedAscending
        }
        return lhs.filePath.localizedStandardCompare(rhs.filePath) == .orderedAscending
    }
}

private struct DeadCodeUnionFind {
    private var parent: [String: String]
    private var rank: [String: Int]

    init(ids: Set<String>) {
        parent = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        rank = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
    }

    mutating func root(of id: String) -> String {
        guard let currentParent = parent[id] else { return id }
        if currentParent == id {
            return id
        }
        let rootID = root(of: currentParent)
        parent[id] = rootID
        return rootID
    }

    mutating func union(_ lhs: String, _ rhs: String) {
        let lhsRoot = root(of: lhs)
        let rhsRoot = root(of: rhs)
        guard lhsRoot != rhsRoot else { return }

        let lhsRank = rank[lhsRoot, default: 0]
        let rhsRank = rank[rhsRoot, default: 0]
        if lhsRank < rhsRank {
            parent[lhsRoot] = rhsRoot
        } else if lhsRank > rhsRank {
            parent[rhsRoot] = lhsRoot
        } else {
            parent[rhsRoot] = lhsRoot
            rank[lhsRoot] = lhsRank + 1
        }
    }
}

struct DeadCodeTreeNode: Identifiable {
    let result: SerializableDeadCodeResult
    let children: [DeadCodeTreeNode]?

    var id: String { result.graphID }
}

struct DeadCodeRemovalPreview: Identifiable {
    let analysisID: UUID
    let fileURL: URL
    let findingCount: Int
    let projectPath: String
    let scheme: String

    var id: String { fileURL.path }
}

struct DeadCodeDeclarationRemovalPreview: Identifiable, Sendable {
    let analysisID: UUID
    let resultGraphID: String
    let declarationName: String
    let declarationKind: String
    let fileURL: URL
    let location: String
    let diff: String
    let originalSource: String
    let updatedSource: String
    let removalRange: Range<Int>
    let removedGraphIDs: Set<String>
    let projectPath: String
    let scheme: String

    var id: String { "\(analysisID.uuidString):\(resultGraphID)" }
}

struct DeadCodeSourceEdit: Sendable {
    let fileURL: URL
    let originalSource: String
    let updatedSource: String
}

enum DeadCodeClusterRemovalKind: Equatable, Sendable {
    case dependencyCluster
    case allSafeCandidates

    var requiresBuildValidation: Bool {
        self == .allSafeCandidates
    }
}

struct DeadCodeClusterRemovalPreview: Identifiable, Sendable {
    let analysisID: UUID
    let clusterID: String
    let kind: DeadCodeClusterRemovalKind
    let declarationCount: Int
    let removedGraphIDs: Set<String>
    let removedFileURLs: [URL]
    let sourceEdits: [DeadCodeSourceEdit]
    let diffSections: [String]
    let skippedCandidateCount: Int
    let projectPath: String
    let scheme: String

    var id: String { "\(analysisID.uuidString):\(clusterID)" }

    var affectedFileCount: Int {
        Set(removedFileURLs.map(\.standardizedFileURL.path) + sourceEdits.map { $0.fileURL.standardizedFileURL.path }).count
    }
}
