import Foundation
import SwiftParser
import SwiftSyntax

protocol DeadCodeSurgicalRemovalPlanning: Sendable {
    func makePreview(
        for result: SerializableDeadCodeResult,
        in analysis: DeadCodeAnalysis,
        removingGraphIDs: Set<String>
    ) throws -> DeadCodeDeclarationRemovalPreview

    func makeClusterPreview(
        for cluster: DeadCodeDependencyCluster,
        in analysis: DeadCodeAnalysis
    ) throws -> DeadCodeClusterRemovalPreview

    func makeSafeCandidatesPreview(
        in analysis: DeadCodeAnalysis
    ) async throws -> DeadCodeClusterRemovalPreview
}

struct SwiftSyntaxDeadCodeRemovalPlanner: DeadCodeSurgicalRemovalPlanning {
    func makeClusterPreview(
        for cluster: DeadCodeDependencyCluster,
        in analysis: DeadCodeAnalysis
    ) throws -> DeadCodeClusterRemovalPreview {
        try validateGraphSnapshot(in: analysis)
        let graphIDs = Set(cluster.results.map(\.graphID))
        guard cluster.results.allSatisfy({ $0.remediation == .deleteDeclaration }) else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "This cluster contains findings that require different remediations and cannot be deleted as one unit."
            )
        }
        guard cluster.results.allSatisfy({
            $0.isStructurallyRemovable(within: graphIDs)
        }) else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "An initializer or deinitializer cannot be removed while its owning type is retained."
            )
        }

        return try makeClusterPreview(
            results: cluster.results,
            clusterID: cluster.id,
            kind: .dependencyCluster,
            skippedCandidateCount: 0,
            in: analysis
        )
    }

    func makeSafeCandidatesPreview(
        in analysis: DeadCodeAnalysis
    ) async throws -> DeadCodeClusterRemovalPreview {
        try validateGraphSnapshot(in: analysis)
        guard analysis.scheme != nil else {
            throw DeadCodeSurgicalRemovalError.missingScheme
        }
        let cache = SurgicalPlanningCache(
            safeWholeFilePaths: safeWholeFilePaths(in: analysis.results),
            resultsByFile: Dictionary(grouping: analysis.results, by: \.filePath)
        )
        let candidateClusters = DeadCodeDependencyCluster.build(from: analysis.results)
            .filter(\.isPotentiallyFullyRemovable)
        let candidateGraphIDs = Set(candidateClusters.flatMap { $0.results.map(\.graphID) })
        let preparedCandidates = candidateClusters.map { cluster in
            PreparedCandidateCluster(
                cluster: cluster,
                selection: removalSelection(
                    for: cluster.results,
                    in: analysis,
                    cache: cache
                )
            )
        }
        let surgicalResults = Dictionary(
            preparedCandidates
                .flatMap(\.selection.surgicalRoots)
                .map { ($0.graphID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        cache.plannedDeclarations = try await prepareSurgicalPlans(
            for: Array(surgicalResults.values)
        )
        var selectedByID: [String: SerializableDeadCodeResult] = [:]

        for candidate in preparedCandidates {
            try Task.checkCancellation()
            guard (try? validatePreparedClusterPlan(
                candidate.selection,
                cache: cache
            )) != nil else {
                continue
            }
            for result in candidate.cluster.results {
                selectedByID[result.graphID] = result
            }
        }

        guard !selectedByID.isEmpty else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "No candidate passed the final surgical safety checks. Refresh the scan or review candidates individually."
            )
        }

        let selectedResults = Array(selectedByID.values)
        return try makeClusterPreview(
            results: selectedResults,
            clusterID: "all-safe-candidates-\(analysis.id.uuidString)",
            kind: .allSafeCandidates,
            skippedCandidateCount: candidateGraphIDs.subtracting(selectedByID.keys).count,
            in: analysis,
            cache: cache
        )
    }

    private func prepareSurgicalPlans(
        for results: [SerializableDeadCodeResult]
    ) async throws -> [String: PlannedSurgicalDeclaration] {
        let inputs = Dictionary(grouping: results, by: \.filePath)
            .map { filePath, results in
                FilePlanningInput(
                    fileURL: URL(fileURLWithPath: filePath).standardizedFileURL,
                    results: results
                )
            }
            .sorted { $0.fileURL.path < $1.fileURL.path }
        guard !inputs.isEmpty else { return [:] }

        return try await withThrowingTaskGroup(
            of: FilePlanningOutcome.self,
            returning: [String: PlannedSurgicalDeclaration].self
        ) { group in
            // Two parser jobs keep preparation responsive without monopolizing
            // the machine. Each job releases its SwiftSyntax tree per file.
            let concurrencyLimit = min(2, inputs.count)
            var nextIndex = 0
            var plans: [String: PlannedSurgicalDeclaration] = [:]

            func enqueue(_ input: FilePlanningInput) {
                group.addTask {
                    try Task.checkCancellation()
                    let fileCache = SurgicalPlanningCache(
                        safeWholeFilePaths: [],
                        resultsByFile: [:]
                    )
                    var filePlans: [String: PlannedSurgicalDeclaration] = [:]
                    for result in input.results {
                        try Task.checkCancellation()
                        if let plan = try? makePlannedDeclaration(
                            for: result,
                            cache: fileCache
                        ) {
                            filePlans[result.graphID] = plan
                        }
                    }
                    return FilePlanningOutcome(plans: filePlans)
                }
            }

            for _ in 0..<concurrencyLimit {
                enqueue(inputs[nextIndex])
                nextIndex += 1
            }

            while let outcome = try await group.next() {
                try Task.checkCancellation()
                for (graphID, plan) in outcome.plans {
                    plans[graphID] = plan
                }
                if nextIndex < inputs.count {
                    enqueue(inputs[nextIndex])
                    nextIndex += 1
                }
            }
            return plans
        }
    }

    private func makeClusterPreview(
        results: [SerializableDeadCodeResult],
        clusterID: String,
        kind: DeadCodeClusterRemovalKind,
        skippedCandidateCount: Int,
        in analysis: DeadCodeAnalysis,
        cache: SurgicalPlanningCache? = nil
    ) throws -> DeadCodeClusterRemovalPreview {
        guard let scheme = analysis.scheme else {
            throw DeadCodeSurgicalRemovalError.missingScheme
        }
        guard results.allSatisfy(\.externalReferenceLocations.isEmpty) else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "This dependency closure still has references from retained declarations. No source was changed."
            )
        }

        let selection = removalSelection(
            for: results,
            in: analysis,
            cache: cache
        )
        let removedFileURLs = selection.wholeFilePaths
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .sorted { $0.path < $1.path }

        let declarationPreviews = try selection.surgicalRoots.map { result in
            try Task.checkCancellation()
            return try makePlannedDeclaration(
                for: result,
                cache: cache
            )
        }
        let previewsByFile = Dictionary(grouping: declarationPreviews, by: \.fileURL)
        let sourceEdits = try previewsByFile.map { fileURL, previews in
            guard let originalSource = previews.first?.originalSource,
                  previews.allSatisfy({ $0.originalSource == originalSource }) else {
                throw DeadCodeSurgicalRemovalError.invalidSyntaxRange
            }

            let ranges = try normalizedRemovalRanges(
                previews.map { ($0.removalRange, $0.declarationName) },
                fileURL: fileURL
            )

            var updatedBytes = Array(originalSource.utf8)
            for range in ranges {
                updatedBytes.removeSubrange(range)
            }
            guard let updatedSource = String(bytes: updatedBytes, encoding: .utf8) else {
                throw DeadCodeSurgicalRemovalError.invalidSyntaxRange
            }

            return DeadCodeSourceEdit(
                fileURL: fileURL,
                originalSource: originalSource,
                updatedSource: updatedSource
            )
        }.sorted { $0.fileURL.path < $1.fileURL.path }

        guard !removedFileURLs.isEmpty || !sourceEdits.isEmpty else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "This cluster does not contain an atomic declaration that can be removed safely."
            )
        }

        let diffSections: [String]
        if kind == .allSafeCandidates {
            // The bulk sheet renders a virtualized file summary. Building
            // thousands of textual diffs here would stall SwiftUI text layout.
            diffSections = []
        } else {
            diffSections = declarationPreviews.map {
                "\($0.fileURL.lastPathComponent) — \($0.declarationName)\n" +
                    makeDiff(
                        source: $0.originalSource,
                        startLine: $0.startLine,
                        endLine: $0.endLine
                    )
            } + removedFileURLs.map {
                "\($0.lastPathComponent)\n" +
                    "- Entire dead source file will be moved to Trash.\n" +
                    "- Matching Xcode project references will be removed."
            }
        }

        return DeadCodeClusterRemovalPreview(
            analysisID: analysis.id,
            clusterID: clusterID,
            kind: kind,
            declarationCount: selection.removedGraphIDs.count,
            removedGraphIDs: selection.removedGraphIDs,
            removedFileURLs: removedFileURLs,
            sourceEdits: sourceEdits,
            diffSections: diffSections,
            skippedCandidateCount: skippedCandidateCount,
            projectPath: analysis.projectPath,
            scheme: scheme
        )
    }

    private func validateClusterPlan(
        results: [SerializableDeadCodeResult],
        in analysis: DeadCodeAnalysis,
        cache: SurgicalPlanningCache
    ) throws {
        let selection = removalSelection(for: results, in: analysis, cache: cache)
        let plans = try selection.surgicalRoots.map {
            try makePlannedDeclaration(for: $0, cache: cache)
        }
        let plansByFile = Dictionary(grouping: plans, by: \.fileURL)
        for (fileURL, filePlans) in plansByFile {
            _ = try normalizedRemovalRanges(
                filePlans.map { ($0.removalRange, $0.declarationName) },
                fileURL: fileURL
            )
        }
        guard !selection.wholeFilePaths.isEmpty || !plans.isEmpty else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "This cluster does not contain an atomic declaration that can be removed safely."
            )
        }
    }

    private func validatePreparedClusterPlan(
        _ selection: RemovalSelection,
        cache: SurgicalPlanningCache
    ) throws {
        let plans = try selection.surgicalRoots.map { result in
            guard let plan = cache.plannedDeclarations[result.graphID] else {
                throw DeadCodeSurgicalRemovalError.declarationNotFound(result.location)
            }
            return plan
        }
        let plansByFile = Dictionary(grouping: plans, by: \.fileURL)
        for (fileURL, filePlans) in plansByFile {
            _ = try normalizedRemovalRanges(
                filePlans.map { ($0.removalRange, $0.declarationName) },
                fileURL: fileURL
            )
        }
        guard !selection.wholeFilePaths.isEmpty || !plans.isEmpty else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "This cluster does not contain an atomic declaration that can be removed safely."
            )
        }
    }

    private func removalSelection(
        for results: [SerializableDeadCodeResult],
        in analysis: DeadCodeAnalysis,
        cache: SurgicalPlanningCache?
    ) -> RemovalSelection {
        let globallySafeFilePaths = cache?.safeWholeFilePaths ??
            safeWholeFilePaths(in: analysis.results)
        let requestedGraphIDs = Set(results.map(\.graphID))
        let resultsByFile = cache?.resultsByFile ??
            Dictionary(grouping: analysis.results, by: \.filePath)
        let wholeFilePaths = Set(results.map(\.filePath).filter { filePath in
            globallySafeFilePaths.contains(filePath) &&
                resultsByFile[filePath, default: []]
                    .allSatisfy { requestedGraphIDs.contains($0.graphID) }
        })
        // A file is selected only when every finding it contains is already part
        // of this closed request, so the requested IDs are the complete removal set.
        let removedGraphIDs = requestedGraphIDs
        let resultByID = Dictionary(
            results.map { ($0.graphID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seenLocations = Set<String>()
        let surgicalRoots = results.filter { result in
            guard !wholeFilePaths.contains(result.filePath) else { return false }
            let locationKey = "\(result.filePath):\(result.location)"
            guard seenLocations.insert(locationKey).inserted else { return false }

            var parentID = result.parentGraphID
            while let currentParentID = parentID {
                if removedGraphIDs.contains(currentParentID) {
                    return false
                }
                parentID = resultByID[currentParentID]?.parentGraphID
            }
            return true
        }
        return RemovalSelection(
            wholeFilePaths: wholeFilePaths,
            removedGraphIDs: removedGraphIDs,
            surgicalRoots: surgicalRoots
        )
    }

    private func safeWholeFilePaths(
        in results: [SerializableDeadCodeResult]
    ) -> Set<String> {
        Set(
            Dictionary(grouping: results, by: \.filePath)
                .filter {
                    !$0.value.isEmpty &&
                        $0.value.allSatisfy { $0.fileRemovalSafety == .safeWholeFile }
                }
                .map(\.key)
        )
    }

    func makePreview(
        for result: SerializableDeadCodeResult,
        in analysis: DeadCodeAnalysis,
        removingGraphIDs: Set<String>
    ) throws -> DeadCodeDeclarationRemovalPreview {
        try validateGraphSnapshot(in: analysis)
        guard let scheme = analysis.scheme else {
            throw DeadCodeSurgicalRemovalError.missingScheme
        }
        guard result.externalReferenceLocations.isEmpty else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "This declaration still has references from retained code. Remove its complete dependency closure instead."
            )
        }
        guard !result.requiresOwningDeclarationRemoval else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "Initializers and deinitializers can only be removed together with their owning type."
            )
        }
        let planned = try makePlannedDeclaration(
            for: result,
            cache: nil
        )
        var updatedBytes = Array(planned.originalSource.utf8)
        updatedBytes.removeSubrange(planned.removalRange)
        guard let updatedSource = String(bytes: updatedBytes, encoding: .utf8) else {
            throw DeadCodeSurgicalRemovalError.invalidSyntaxRange
        }

        return DeadCodeDeclarationRemovalPreview(
            analysisID: analysis.id,
            resultGraphID: result.graphID,
            declarationName: planned.declarationName,
            declarationKind: result.kind,
            fileURL: planned.fileURL,
            location: result.location,
            diff: makeDiff(
                source: planned.originalSource,
                startLine: planned.startLine,
                endLine: planned.endLine
            ),
            originalSource: planned.originalSource,
            updatedSource: updatedSource,
            removalRange: planned.removalRange,
            removedGraphIDs: removingGraphIDs,
            projectPath: analysis.projectPath,
            scheme: scheme
        )
    }

    private func makePlannedDeclaration(
        for result: SerializableDeadCodeResult,
        cache: SurgicalPlanningCache?
    ) throws -> PlannedSurgicalDeclaration {
        if let cached = cache?.plannedDeclarations[result.graphID] {
            return cached
        }

        guard result.remediation == .deleteDeclaration else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "This finding requires a different remediation."
            )
        }

        let fileURL = URL(fileURLWithPath: result.filePath).standardizedFileURL
        guard fileURL.pathExtension.lowercased() == "swift" else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "Surgical removal is only available for Swift source files."
            )
        }

        let context = try sourceContext(for: fileURL, cache: cache)
        let source = context.source

        guard let target = SourceTarget(location: result.location) else {
            throw DeadCodeSurgicalRemovalError.invalidLocation(result.location)
        }

        let visitor = SurgicalDeclarationVisitor(
            converter: context.converter,
            target: target,
            expectedKind: result.kind,
            expectedName: result.name
        )
        guard let declaration = declarationSyntax(
            containing: target,
            in: context
        ) else {
            throw DeadCodeSurgicalRemovalError.declarationNotFound(result.location)
        }
        visitor.walk(declaration)

        guard let candidate = visitor.candidate else {
            throw visitor.rejection ??
                DeadCodeSurgicalRemovalError.declarationNotFound(result.location)
        }

        let sourceBytes = Array(source.utf8)
        guard candidate.range.lowerBound >= 0,
              candidate.range.upperBound <= sourceBytes.count,
              candidate.range.lowerBound < candidate.range.upperBound else {
            throw DeadCodeSurgicalRemovalError.invalidSyntaxRange
        }

        let preview = PlannedSurgicalDeclaration(
            declarationName: result.name ?? "Unknown declaration",
            fileURL: fileURL,
            originalSource: source,
            removalRange: candidate.range,
            startLine: candidate.startLine,
            endLine: candidate.endLine
        )
        cache?.plannedDeclarations[result.graphID] = preview
        return preview
    }

    private func sourceContext(
        for fileURL: URL,
        cache: SurgicalPlanningCache?
    ) throws -> SurgicalSourceContext {
        if let cached = cache?.sourceContexts[fileURL.path] {
            return cached
        }

        let source: String
        do {
            source = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw DeadCodeSurgicalRemovalError.unreadableSource(fileURL)
        }
        let context = SurgicalSourceContext(
            source: source,
            filePath: fileURL.path
        )
        cache?.sourceContexts[fileURL.path] = context
        return context
    }

    private func declarationSyntax(
        containing target: SourceTarget,
        in context: SurgicalSourceContext
    ) -> Syntax? {
        let position = context.converter.position(
            ofLine: target.line,
            column: target.column
        )
        let token = context.tokensByAnchorOffset[position.utf8Offset] ??
            context.tree.token(at: position)
        var node = token.map(Syntax.init)

        while let current = node {
            if current.isProtocol(DeclSyntaxProtocol.self) {
                return current
            }
            node = current.parent
        }
        return nil
    }

    private func validateGraphSnapshot(in analysis: DeadCodeAnalysis) throws {
        guard analysis.graphSnapshotVersion >= DeadCodeAnalysis.currentGraphSnapshotVersion else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "This analysis predates dependency-closure safety checks. Run a new scan before removing clusters or safe candidates."
            )
        }
    }

    private func makeDiff(source: String, startLine: Int, endLine: Int) -> String {
        let lines = source.components(separatedBy: "\n")
        let firstLine = max(1, startLine - 2)
        let lastLine = min(lines.count, endLine + 2)
        let width = String(lastLine).count

        var diff = ["@@ -\(startLine),\(max(1, endLine - startLine + 1)) +\(startLine),0 @@"]
        for lineNumber in firstLine...lastLine {
            let prefix = (startLine...endLine).contains(lineNumber) ? "-" : " "
            let paddedNumber = String(repeating: " ", count: width - String(lineNumber).count) + String(lineNumber)
            diff.append("\(prefix)\(paddedNumber) │ \(lines[lineNumber - 1])")
        }
        return diff.joined(separator: "\n")
    }

    private func normalizedRemovalRanges(
        _ candidates: [(range: Range<Int>, name: String)],
        fileURL: URL
    ) throws -> [Range<Int>] {
        let ordered = candidates.sorted {
            if $0.range.lowerBound == $1.range.lowerBound {
                return $0.range.upperBound > $1.range.upperBound
            }
            return $0.range.lowerBound < $1.range.lowerBound
        }
        var normalized: [(range: Range<Int>, name: String)] = []

        for candidate in ordered {
            guard candidate.range.lowerBound < candidate.range.upperBound else {
                throw DeadCodeSurgicalRemovalError.invalidSyntaxRange
            }
            if let containing = normalized.last,
               containing.range.lowerBound <= candidate.range.lowerBound,
               containing.range.upperBound >= candidate.range.upperBound {
                continue
            }
            if let previous = normalized.last,
               previous.range.upperBound > candidate.range.lowerBound {
                throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                    "\(previous.name) and \(candidate.name) partially overlap in " +
                    "\(fileURL.lastPathComponent). No source was changed. " +
                    "Refresh the scan or remove them individually."
                )
            }
            normalized.append(candidate)
        }

        return normalized.map(\.range).sorted { $0.lowerBound > $1.lowerBound }
    }
}

private struct RemovalSelection {
    let wholeFilePaths: Set<String>
    let removedGraphIDs: Set<String>
    let surgicalRoots: [SerializableDeadCodeResult]
}

private struct PreparedCandidateCluster {
    let cluster: DeadCodeDependencyCluster
    let selection: RemovalSelection
}

private struct FilePlanningInput: Sendable {
    let fileURL: URL
    let results: [SerializableDeadCodeResult]
}

private struct FilePlanningOutcome: Sendable {
    let plans: [String: PlannedSurgicalDeclaration]
}

private final class SurgicalPlanningCache {
    let safeWholeFilePaths: Set<String>
    let resultsByFile: [String: [SerializableDeadCodeResult]]
    var sourceContexts: [String: SurgicalSourceContext] = [:]
    var plannedDeclarations: [String: PlannedSurgicalDeclaration] = [:]

    init(
        safeWholeFilePaths: Set<String>,
        resultsByFile: [String: [SerializableDeadCodeResult]]
    ) {
        self.safeWholeFilePaths = safeWholeFilePaths
        self.resultsByFile = resultsByFile
    }
}

private struct SurgicalSourceContext {
    let source: String
    let tree: SourceFileSyntax
    let converter: SourceLocationConverter
    let tokensByAnchorOffset: [Int: TokenSyntax]

    init(source: String, filePath: String) {
        self.source = source
        tree = Parser.parse(source: source)
        converter = SourceLocationConverter(fileName: filePath, tree: tree)
        var indexedTokens: [Int: TokenSyntax] = [:]
        for token in tree.tokens(viewMode: .sourceAccurate) {
            indexedTokens[token.position.utf8Offset] = token
            indexedTokens[token.positionAfterSkippingLeadingTrivia.utf8Offset] = token
        }
        tokensByAnchorOffset = indexedTokens
    }
}

private struct PlannedSurgicalDeclaration: Sendable {
    let declarationName: String
    let fileURL: URL
    let originalSource: String
    let removalRange: Range<Int>
    let startLine: Int
    let endLine: Int
}

private struct SourceTarget {
    let line: Int
    let column: Int

    init?(location: String) {
        let components = location.split(separator: ":")
        guard components.count >= 3,
              let line = Int(components[components.count - 2]),
              let column = Int(components[components.count - 1]) else {
            return nil
        }
        self.line = line
        self.column = column
    }
}

private struct SurgicalCandidate {
    let range: Range<Int>
    let startLine: Int
    let endLine: Int
}

private final class SurgicalDeclarationVisitor: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private let target: SourceTarget
    private let expectedKind: String
    private let expectedName: String?

    private(set) var candidate: SurgicalCandidate?
    private(set) var rejection: DeadCodeSurgicalRemovalError?

    init(
        converter: SourceLocationConverter,
        target: SourceTarget,
        expectedKind: String,
        expectedName: String?
    ) {
        self.converter = converter
        self.target = target
        self.expectedKind = expectedKind
        self.expectedName = expectedName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "class", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "class", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "struct", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "enum", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "protocol", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        var anchors = [node.extendedType.positionAfterSkippingLeadingTrivia]
        if let memberType = node.extendedType.as(MemberTypeSyntax.self) {
            anchors.append(memberType.name.positionAfterSkippingLeadingTrivia)
        }
        if let genericClause = node.extendedType.as(IdentifierTypeSyntax.self)?.genericArgumentClause {
            anchors.append(genericClause.rightAngle.positionAfterSkippingLeadingTrivia)
        }
        consider(node, kind: "extension", name: node.extendedType.trimmedDescription, anchors: anchors)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "function", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "initializer", name: "init", anchors: [node.initKeyword.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "function", name: "deinit", anchors: [node.deinitKeyword.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "function", name: "subscript", anchors: [node.subscriptKeyword.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "typealias", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "associatedtype", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: PrecedenceGroupDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "precedence group", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        consider(node, kind: "macro", name: node.name.text, anchors: [node.name.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.path.first?.name.text
        consider(node, kind: "imported module", name: name, anchors: [node.positionAfterSkippingLeadingTrivia])
        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard expectedKind == "enum case",
              node.elements.contains(where: { matches($0.name.positionAfterSkippingLeadingTrivia) }) else {
            return .visitChildren
        }

        guard node.elements.count == 1, let element = node.elements.first else {
            rejection = .unsupportedDeclaration(
                "This enum case shares one declaration with other cases and cannot be removed atomically."
            )
            return .skipChildren
        }

        consider(
            node,
            kind: "enum case",
            name: element.name.text,
            anchors: [element.name.positionAfterSkippingLeadingTrivia]
        )
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard expectedKind == "property",
              node.bindings.contains(where: { matches($0.positionAfterSkippingLeadingTrivia) }) else {
            return .visitChildren
        }

        guard node.bindings.count == 1,
              let binding = node.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            rejection = .unsupportedDeclaration(
                "This property shares a declaration with other bindings and cannot be removed atomically."
            )
            return .skipChildren
        }

        guard binding.initializer == nil else {
            rejection = .unsupportedDeclaration(
                "Properties with an initializer require manual review because removing them may discard side effects."
            )
            return .skipChildren
        }

        consider(
            node,
            kind: "property",
            name: identifier.identifier.text,
            anchors: [binding.positionAfterSkippingLeadingTrivia]
        )
        return .visitChildren
    }

    private func consider<Node: SyntaxProtocol>(
        _ node: Node,
        kind: String,
        name: String?,
        anchors: [AbsolutePosition]
    ) {
        guard candidate == nil,
              expectedKind == kind,
              anchors.contains(where: matches),
              nameMatches(name) else {
            return
        }

        let start = node.position.utf8Offset
        let end = node.endPosition.utf8Offset
        let startLocation = converter.location(for: node.position)
        let endLocation = converter.location(for: node.endPositionBeforeTrailingTrivia)

        candidate = SurgicalCandidate(
            range: start..<end,
            startLine: startLocation.line,
            endLine: max(startLocation.line, endLocation.line)
        )
    }

    private func matches(_ position: AbsolutePosition) -> Bool {
        let location = converter.location(for: position)
        return location.line == target.line && location.column == target.column
    }

    private func nameMatches(_ candidateName: String?) -> Bool {
        guard let expectedName, !expectedName.isEmpty,
              let candidateName, !candidateName.isEmpty else {
            return true
        }

        return expectedName == candidateName ||
            expectedName.hasPrefix(candidateName + "(") ||
            expectedName.hasPrefix(candidateName + "<") ||
            expectedName.hasSuffix("." + candidateName) ||
            candidateName.hasPrefix(expectedName + "<") ||
            candidateName.hasSuffix("." + expectedName)
    }
}

enum DeadCodeSurgicalRemovalError: LocalizedError {
    case missingScheme
    case unreadableSource(URL)
    case invalidLocation(String)
    case declarationNotFound(String)
    case unsupportedDeclaration(String)
    case invalidSyntaxRange

    var errorDescription: String? {
        switch self {
        case .missingScheme:
            "The saved analysis has no scheme. Run a new scan before removing declarations."
        case .unreadableSource(let fileURL):
            "\(fileURL.lastPathComponent) could not be read as UTF-8 Swift source."
        case .invalidLocation(let location):
            "The saved source location is invalid: \(location)."
        case .declarationNotFound(let location):
            "The declaration no longer matches the scan at \(location). Run the scanner again."
        case .unsupportedDeclaration(let reason):
            reason
        case .invalidSyntaxRange:
            "SwiftSyntax returned an invalid declaration range. No source was changed."
        }
    }
}
