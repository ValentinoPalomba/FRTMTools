import Foundation
import SwiftUI
import PeripheryKit
@preconcurrency import SourceGraph
import FRTMCore
import Observation
import UniformTypeIdentifiers

extension Accessibility: @retroactive CaseIterable {
    public static let allCases: [Accessibility] = [
        .fileprivate, .internal, .open, .private, .public
    ]
}

struct DeadCodeRemovalActivity: Equatable {
    let title: String
    var stage: DeadCodeRemovalStage
    var stageStartedAt = Date()

    var statusTitle: String {
        switch stage {
        case .applyingChanges:
            "Applying surgical changes…"
        case .rebuilding:
            "Rebuilding project…"
        case .restoringSources:
            "Build failed — restoring project changes…"
        }
    }

    var statusDetail: String {
        switch stage {
        case .applyingChanges:
            title
        case .rebuilding:
            "\(title) Changes stay applied only if the selected scheme builds."
        case .restoringSources:
            "FRTMTools is restoring every affected source and Xcode project file."
        }
    }
}

@MainActor
@Observable
final class DeadCodeViewModel {
    // MARK: - Dependencies & Persistence
    @ObservationIgnored private let persistenceManagerDependency = Dependency<PersistenceManager>()
    @ObservationIgnored private let removalService: any DeadCodeRemoving
    @ObservationIgnored private let surgicalRemovalPlanner: any DeadCodeSurgicalRemovalPlanning
    private var persistenceManager: PersistenceManager { persistenceManagerDependency.wrappedValue }
    private let persistenceKey = "dead_code_analyses"
    private static let buildValidationPreferenceKey = "dead_code_validates_build_after_removal"

    // MARK: - Published Properties
    var analyses: [DeadCodeAnalysis] = [] {
        didSet {
            updateFilteredAndGroupedResults()
        }
    }
    var selectedAnalysisID: UUID? {
        didSet {
            safeCandidatesPreparationTask?.cancel()
            safeCandidatesPreparationTask = nil
            safeCandidatesPreparationID = nil
            isPreparingSafeCandidates = false
            lastRemovalMessage = nil
            updateFilteredAndGroupedResults()
        }
    }
    
    var isLoading = false
    var isLoadingSchemes = false

    var error: Error?

    // Filter properties
    var selectedKinds: Set<String> = Set(Declaration.Kind.allCases.map { $0.displayName }) {
        didSet {
            updateFilteredAndGroupedResults()
        }
    }
    var selectedAccessibilities: Set<Accessibility> = Set(Accessibility.allCases) {
        didSet {
            updateFilteredAndGroupedResults()
        }
    }
    var minimumClusterSize = 1 {
        didSet {
            minimumClusterSize = max(1, minimumClusterSize)
            updateFilteredAndGroupedResults()
        }
    }
    var includesIsolatedClusters = true {
        didSet { updateFilteredAndGroupedResults() }
    }
    var showsOnlyFullyRemovableClusters = false {
        didSet { updateFilteredAndGroupedResults() }
    }
    var showsOnlyMultiFileClusters = false {
        didSet { updateFilteredAndGroupedResults() }
    }

    // Derived data for the view
    var filteredResults: [SerializableDeadCodeResult] = []
    var resultsByKind: [DeadCodeGroup] = []
    var dependencyClusters: [DeadCodeDependencyCluster] = []
    var removingFilePath: String?
    var removingGraphID: String?
    var removingClusterID: String?
    var isPreparingSafeCandidates = false
    var lastRemovalMessage: String?
    var removalActivity: DeadCodeRemovalActivity?
    var validatesBuildAfterRemoval: Bool {
        didSet {
            UserDefaults.standard.set(
                validatesBuildAfterRemoval,
                forKey: Self.buildValidationPreferenceKey
            )
        }
    }
    
    // Sequence token to ensure only the most recent async update applies
    @ObservationIgnored private var updateSequence: Int = 0
    @ObservationIgnored private var cachedClusterAnalysisID: UUID?
    @ObservationIgnored private var cachedClusterGraphIDs = Set<String>()
    @ObservationIgnored private var cachedDependencyClusters: [DeadCodeDependencyCluster] = []
    @ObservationIgnored private var safeCandidatesPreparationTask:
        Task<DeadCodeClusterRemovalPreview, Error>?
    @ObservationIgnored private var safeCandidatesPreparationID: UUID?
    
    // Schemes for a selected project before scanning
    var schemes: [String] = []
    var selectedScheme: String?
    var projectToScan: URL?

    // MARK: - Init
    init(
        removalService: any DeadCodeRemoving = DeadCodeRemovalService(),
        surgicalRemovalPlanner: any DeadCodeSurgicalRemovalPlanning = SwiftSyntaxDeadCodeRemovalPlanner()
    ) {
        self.removalService = removalService
        self.surgicalRemovalPlanner = surgicalRemovalPlanner
        if UserDefaults.standard.object(forKey: Self.buildValidationPreferenceKey) == nil {
            validatesBuildAfterRemoval = true
        } else {
            validatesBuildAfterRemoval = UserDefaults.standard.bool(
                forKey: Self.buildValidationPreferenceKey
            )
        }
        loadAnalyses()
    }

    // MARK: - Computed Properties
    var selectedAnalysis: DeadCodeAnalysis? {
        guard let selectedAnalysisID = selectedAnalysisID else {
            return analyses.first
        }
        return analyses.first { $0.id == selectedAnalysisID }
    }

    var safeFileRemovalCount: Int {
        guard let analysis = selectedAnalysis,
              analysis.graphSnapshotVersion >= DeadCodeAnalysis.currentGraphSnapshotVersion else {
            return 0
        }
        return independentlySafeWholeFilePaths(in: analysis.results).count
    }

    var safeRemovalCandidateCount: Int {
        guard let analysis = selectedAnalysis,
              analysis.graphSnapshotVersion >= DeadCodeAnalysis.currentGraphSnapshotVersion else {
            return 0
        }
        let clusterGraphIDs = dependencyClusters(
            for: analysis.results,
            analysisID: analysis.id
        )
            .filter(\.isPotentiallyFullyRemovable)
            .flatMap { $0.results.map(\.graphID) }
        return Set(clusterGraphIDs).count
    }

    var requiresRemovalSafetyRescan: Bool {
        guard let analysis = selectedAnalysis else { return false }
        return analysis.graphSnapshotVersion < DeadCodeAnalysis.currentGraphSnapshotVersion
    }

    func allowsSurgicalRemoval(for result: SerializableDeadCodeResult) -> Bool {
        guard let analysis = selectedAnalysis,
              analysis.graphSnapshotVersion >= DeadCodeAnalysis.currentGraphSnapshotVersion else {
            return false
        }
        let supportedKinds: Set<String> = [
            "associatedtype",
            "class",
            "enum",
            "enum case",
            "extension",
            "function",
            "imported module",
            "initializer",
            "macro",
            "precedence group",
            "property",
            "protocol",
            "struct",
            "typealias",
        ]
        return result.remediation == .deleteDeclaration &&
            result.externalReferenceLocations.isEmpty &&
            !result.requiresOwningDeclarationRemoval &&
            supportedKinds.contains(result.kind)
    }

    // MARK: - Persistence
    func loadAnalyses() {
        self.analyses = persistenceManager.load(key: persistenceKey)
        if selectedAnalysisID == nil {
            self.selectedAnalysisID = analyses.first?.id
        }
        updateFilteredAndGroupedResults()
    }

    func saveAnalyses() {
        persistenceManager.save(analyses, key: persistenceKey)
    }
    
    func deleteAnalysis(_ analysis: DeadCodeAnalysis) {
        let shouldUpdateSelection = selectedAnalysisID == analysis.id
        let newAnalyses = analyses.filter { $0.id != analysis.id }

        if shouldUpdateSelection {
            selectedAnalysisID = newAnalyses.first?.id
        }

        analyses = newAnalyses
        saveAnalyses()
    }

    func deleteAnalyses(at offsets: IndexSet) {
        var newAnalyses = analyses
        newAnalyses.remove(atOffsets: offsets)

        if let selectedID = selectedAnalysisID, !newAnalyses.contains(where: { $0.id == selectedID }) {
            selectedAnalysisID = newAnalyses.first?.id
        }

        analyses = newAnalyses
        saveAnalyses()
    }

    // MARK: - Data Processing

    // MARK: - CSV Export
    func exportToCSV() {
        guard let analysis = selectedAnalysis else { return }

        do {
            let csvString = try analysis.export()
            guard let data = csvString.data(using: .utf8) else {
                self.error = NSError(domain: "CSVError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode CSV data."])
                return
            }
            
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.nameFieldStringValue = "\(selectedAnalysis?.projectName ?? "")_DeadCodeReport.csv"
            
            savePanel.begin { result in
                if result == .OK, let url = savePanel.url {
                    do {
                        try data.write(to: url)
                    } catch {
                        Task { @MainActor in
                            self.error = error
                        }
                    }
                }
            }
        } catch {
            self.error = error
        }
    }
    private func updateFilteredAndGroupedResults() {
        // Bump sequence to invalidate any in-flight assignments
        updateSequence &+= 1
        let currentSequence = updateSequence

        // Compute new values synchronously
        let newFilteredResults: [SerializableDeadCodeResult]
        let newResultsByKind: [DeadCodeGroup]
        let newDependencyClusters: [DeadCodeDependencyCluster]

        if let results = selectedAnalysis?.results {
            let filtered = results.filter { result in
                selectedKinds.contains(result.kind) &&
                selectedAccessibilities.contains(where: { result.accessibility == $0.rawValue })
            }
            newFilteredResults = filtered

            let grouped = Dictionary(grouping: filtered, by: { $0.kind })
            newResultsByKind = grouped.map { kind, results in
                DeadCodeGroup(kind: kind, results: results)
            }.sorted { $0.results.count > $1.results.count }
            let matchingGraphIDs = Set(filtered.map(\.graphID))
            let allClusters = dependencyClusters(
                for: results,
                analysisID: selectedAnalysis?.id
            )
            newDependencyClusters = allClusters
                .filter { cluster in
                    !matchingGraphIDs.isDisjoint(with: cluster.results.map(\.graphID)) &&
                        cluster.results.count >= minimumClusterSize &&
                        (includesIsolatedClusters || cluster.isLinked) &&
                        (!showsOnlyFullyRemovableClusters || cluster.isPotentiallyFullyRemovable) &&
                        (!showsOnlyMultiFileClusters || cluster.fileCount > 1)
                }
        } else {
            newFilteredResults = []
            newResultsByKind = []
            newDependencyClusters = []
        }

        // Defer publishing to avoid changing @Published properties during view updates
        Task { @MainActor in
            guard self.updateSequence == currentSequence else { return }
            self.filteredResults = newFilteredResults
            self.resultsByKind = newResultsByKind
            self.dependencyClusters = newDependencyClusters
        }
    }

    private func dependencyClusters(
        for results: [SerializableDeadCodeResult],
        analysisID: UUID?
    ) -> [DeadCodeDependencyCluster] {
        let graphIDs = Set(results.map(\.graphID))
        if cachedClusterAnalysisID == analysisID,
           cachedClusterGraphIDs == graphIDs {
            return cachedDependencyClusters
        }

        let clusters = DeadCodeDependencyCluster.build(from: results)
        cachedClusterAnalysisID = analysisID
        cachedClusterGraphIDs = graphIDs
        cachedDependencyClusters = clusters
        return clusters
    }

    // MARK: - Safe Removal

    func removalPreview(
        for result: SerializableDeadCodeResult
    ) -> DeadCodeRemovalPreview? {
        guard result.fileRemovalSafety == .safeWholeFile,
              let analysis = selectedAnalysis,
              analysis.graphSnapshotVersion >= DeadCodeAnalysis.currentGraphSnapshotVersion,
              let scheme = analysis.scheme else {
            return nil
        }

        let fileResults = analysis.results.filter { $0.filePath == result.filePath }
        guard !fileResults.isEmpty,
              fileResults.allSatisfy({ $0.fileRemovalSafety == .safeWholeFile }),
              independentlySafeWholeFilePaths(in: analysis.results).contains(result.filePath),
              fileResults.min(by: { $0.location < $1.location })?.id == result.id else {
            return nil
        }

        return DeadCodeRemovalPreview(
            analysisID: analysis.id,
            fileURL: URL(fileURLWithPath: result.filePath),
            findingCount: fileResults.count,
            projectPath: analysis.projectPath,
            scheme: scheme
        )
    }

    func removeDeadFile(using preview: DeadCodeRemovalPreview) {
        guard removingFilePath == nil, removingGraphID == nil, removingClusterID == nil else { return }

        let validatesBuild = validatesBuildAfterRemoval
        removingFilePath = preview.fileURL.path
        lastRemovalMessage = nil
        error = nil
        removalActivity = DeadCodeRemovalActivity(
            title: "Removing \(preview.fileURL.lastPathComponent).",
            stage: .applyingChanges
        )

        Task {
            do {
                let outcome = try await removalService.remove(
                    DeadCodeRemovalRequest(
                        fileURLs: [preview.fileURL],
                        projectPath: preview.projectPath,
                        scheme: preview.scheme,
                        validatesBuild: validatesBuild
                    ),
                    progress: removalProgressHandler()
                )

                guard let analysisIndex = analyses.firstIndex(where: { $0.id == preview.analysisID }) else {
                    removingFilePath = nil
                    removalActivity = nil
                    return
                }

                let removedPaths = Set(outcome.removedFileURLs.map(\.standardizedFileURL.path))
                analyses[analysisIndex].results.removeAll {
                    removedPaths.contains(URL(fileURLWithPath: $0.filePath).standardizedFileURL.path)
                }
                saveAnalyses()
                lastRemovalMessage =
                    "\(preview.fileURL.lastPathComponent) moved to Trash. " +
                    validationSuccessMessage(validatesBuild: validatesBuild)
                removingFilePath = nil
                removalActivity = nil
            } catch {
                self.error = error
                removingFilePath = nil
                removalActivity = nil
            }
        }
    }

    func declarationRemovalPreview(
        for result: SerializableDeadCodeResult
    ) throws -> DeadCodeDeclarationRemovalPreview {
        guard let analysis = selectedAnalysis else {
            throw DeadCodeSurgicalRemovalError.declarationNotFound(result.location)
        }

        return try surgicalRemovalPlanner.makePreview(
            for: result,
            in: analysis,
            removingGraphIDs: graphIDsRemovedWithDeclaration(
                result,
                in: analysis.results
            )
        )
    }

    func removeDeclaration(using preview: DeadCodeDeclarationRemovalPreview) {
        guard removingFilePath == nil, removingGraphID == nil, removingClusterID == nil else { return }

        let validatesBuild = validatesBuildAfterRemoval
        removingGraphID = preview.resultGraphID
        lastRemovalMessage = nil
        error = nil
        removalActivity = DeadCodeRemovalActivity(
            title: "Removing \(preview.declarationName) from \(preview.fileURL.lastPathComponent).",
            stage: .applyingChanges
        )

        Task {
            do {
                _ = try await removalService.apply(
                    DeadCodeDeclarationRemovalRequest(
                        fileURL: preview.fileURL,
                        originalSource: preview.originalSource,
                        updatedSource: preview.updatedSource,
                        projectPath: preview.projectPath,
                        scheme: preview.scheme,
                        validatesBuild: validatesBuild
                    ),
                    progress: removalProgressHandler()
                )

                guard let analysisIndex = analyses.firstIndex(where: { $0.id == preview.analysisID }) else {
                    removingGraphID = nil
                    removalActivity = nil
                    return
                }

                analyses[analysisIndex].results.removeAll {
                    preview.removedGraphIDs.contains($0.graphID)
                }
                saveAnalyses()
                let count = preview.removedGraphIDs.count
                lastRemovalMessage =
                    "\(preview.declarationName) removed from \(preview.fileURL.lastPathComponent). " +
                    "\(count) finding\(count == 1 ? "" : "s") cleared. " +
                    validationSuccessMessage(validatesBuild: validatesBuild)
                removingGraphID = nil
                removalActivity = nil
            } catch {
                self.error = error
                removingGraphID = nil
                removalActivity = nil
            }
        }
    }

    func clusterRemovalPreview(
        for cluster: DeadCodeDependencyCluster
    ) throws -> DeadCodeClusterRemovalPreview {
        guard let analysis = selectedAnalysis else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "Select an analysis before removing a cluster."
            )
        }
        return try surgicalRemovalPlanner.makeClusterPreview(
            for: cluster,
            in: analysis
        )
    }

    func allSafeCandidatesRemovalPreview() async throws -> DeadCodeClusterRemovalPreview {
        guard let analysis = selectedAnalysis else {
            throw DeadCodeSurgicalRemovalError.unsupportedDeclaration(
                "Select an analysis before removing safe candidates."
            )
        }

        isPreparingSafeCandidates = true
        safeCandidatesPreparationTask?.cancel()
        let preparationID = UUID()
        safeCandidatesPreparationID = preparationID
        defer {
            if safeCandidatesPreparationID == preparationID {
                isPreparingSafeCandidates = false
                safeCandidatesPreparationTask = nil
                safeCandidatesPreparationID = nil
            }
        }

        let planner = surgicalRemovalPlanner
        let task = Task.detached(priority: .utility) {
            try await planner.makeSafeCandidatesPreview(in: analysis)
        }
        safeCandidatesPreparationTask = task
        return try await task.value
    }

    func removeCluster(using preview: DeadCodeClusterRemovalPreview) {
        guard removingFilePath == nil, removingGraphID == nil, removingClusterID == nil else { return }

        let validatesBuild = preview.kind.requiresBuildValidation || validatesBuildAfterRemoval
        removingClusterID = preview.clusterID
        lastRemovalMessage = nil
        error = nil
        removalActivity = DeadCodeRemovalActivity(
            title: removalActivityTitle(for: preview),
            stage: .applyingChanges
        )

        Task {
            do {
                _ = try await removalService.applyCluster(
                    DeadCodeClusterRemovalRequest(
                        removedFileURLs: preview.removedFileURLs,
                        sourceEdits: preview.sourceEdits,
                        projectPath: preview.projectPath,
                        scheme: preview.scheme,
                        validatesBuild: validatesBuild
                    ),
                    progress: removalProgressHandler()
                )

                guard let analysisIndex = analyses.firstIndex(where: { $0.id == preview.analysisID }) else {
                    removingClusterID = nil
                    removalActivity = nil
                    return
                }
                analyses[analysisIndex].results.removeAll {
                    preview.removedGraphIDs.contains($0.graphID)
                }
                saveAnalyses()
                lastRemovalMessage = removalSuccessMessage(
                    for: preview,
                    validatesBuild: validatesBuild
                )
                removingClusterID = nil
                removalActivity = nil
            } catch {
                self.error = error
                removingClusterID = nil
                removalActivity = nil
            }
        }
    }

    private func independentlySafeWholeFilePaths(
        in results: [SerializableDeadCodeResult]
    ) -> Set<String> {
        let resultByID = Dictionary(
            results.map { ($0.graphID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return Set(Dictionary(grouping: results, by: \.filePath).compactMap { filePath, fileResults in
            let fileGraphIDs = Set(fileResults.map(\.graphID))
            guard !fileResults.isEmpty,
                  fileResults.allSatisfy({
                      $0.fileRemovalSafety == .safeWholeFile &&
                          $0.externalReferenceLocations.isEmpty &&
                          $0.linkedGraphIDs.allSatisfy { linkedID in
                              fileGraphIDs.contains(linkedID) ||
                                  resultByID[linkedID]?.filePath == filePath
                          }
                  }) else {
                return nil
            }
            return filePath
        })
    }

    private func removalActivityTitle(
        for preview: DeadCodeClusterRemovalPreview
    ) -> String {
        switch preview.kind {
        case .dependencyCluster:
            "Removing \(preview.declarationCount) findings across \(preview.affectedFileCount) files."
        case .allSafeCandidates:
            "Removing \(preview.declarationCount) safe candidates across \(preview.affectedFileCount) files."
        }
    }

    private func removalSuccessMessage(
        for preview: DeadCodeClusterRemovalPreview,
        validatesBuild: Bool
    ) -> String {
        switch preview.kind {
        case .dependencyCluster:
            "Cluster removed: \(preview.declarationCount) findings across " +
                "\(preview.affectedFileCount) file\(preview.affectedFileCount == 1 ? "" : "s"). " +
                validationSuccessMessage(validatesBuild: validatesBuild)
        case .allSafeCandidates:
            "\(preview.declarationCount) safe candidate" +
                "\(preview.declarationCount == 1 ? "" : "s") removed across " +
                "\(preview.affectedFileCount) file\(preview.affectedFileCount == 1 ? "" : "s"). " +
                validationSuccessMessage(validatesBuild: validatesBuild)
        }
    }

    private func removalProgressHandler() -> DeadCodeRemovalProgressHandler {
        { [weak self] stage in
            Task { @MainActor in
                guard self?.removalActivity?.stage != stage else { return }
                self?.removalActivity?.stage = stage
                self?.removalActivity?.stageStartedAt = Date()
            }
        }
    }

    private func validationSuccessMessage(validatesBuild: Bool) -> String {
        if validatesBuild {
            "Build validation passed."
        } else {
            "Build validation was skipped; rebuild the project when ready."
        }
    }

    private func graphIDsRemovedWithDeclaration(
        _ result: SerializableDeadCodeResult,
        in results: [SerializableDeadCodeResult]
    ) -> Set<String> {
        var removedIDs = Set(
            results
                .filter {
                    $0.filePath == result.filePath &&
                        $0.location == result.location
                }
                .map(\.graphID)
        )
        removedIDs.insert(result.graphID)

        var didExpand = true
        while didExpand {
            didExpand = false
            for candidate in results {
                guard let parentID = candidate.parentGraphID,
                      removedIDs.contains(parentID),
                      !removedIDs.contains(candidate.graphID) else {
                    continue
                }
                removedIDs.insert(candidate.graphID)
                didExpand = true
            }
        }
        return removedIDs
    }

    // MARK: - Scanning Logic

    func selectProjectFromFile() {
        let panel = NSOpenPanel()
        
        let types: [UTType] = [
            UTType(filenameExtension: "xcodeproj", conformingTo: .package),
            UTType(filenameExtension: "xcworkspace", conformingTo: .package)
        ].compactMap { $0 }
        
        panel.allowedContentTypes = types
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.title = "Select an xcodeproj or xcworkspace file"

        if panel.runModal() == .OK, let url = panel.url {
            self.projectToScan = url
            self.schemes = []
            self.selectedScheme = nil
            loadSchemes(for: url)
        }
    }
    
    private func loadSchemes(for projectURL: URL) {
        isLoadingSchemes = true
        Task(priority: .userInitiated) {
            do {
                let schemes = try DeadCodeScanner().listSchemes(for: projectURL)
                await MainActor.run {
                    self.schemes = schemes
                    self.isLoadingSchemes = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoadingSchemes = false
                    self.projectToScan = nil
                }
            }
        }
    }

    func runScan() {
        isLoadingSchemes = false
        guard let projectURL = projectToScan, let scheme = selectedScheme else {
            error = NSError(
                domain: "Project path or scheme not selected.",
                code: 0
            )
            return
        }
        
        isLoading = true
        error = nil
        projectToScan = nil

        let projectPath = projectURL.path
        let selectedScheme = scheme

        Task(priority: .userInitiated) {
            do {
                let startTime = Date().timeIntervalSince1970
                let scanResults = try DeadCodeScanner().scan(
                    projectPath: projectPath,
                    scheme: selectedScheme
                )
                let endTime = Date().timeIntervalSince1970

                let newAnalysis = DeadCodeAnalysis(
                    id: UUID(),
                    projectName: URL(fileURLWithPath: projectPath).lastPathComponent,
                    projectPath: projectPath,
                    scheme: selectedScheme,
                    scanTimeDuration: endTime - startTime,
                    results: scanResults
                )

                await MainActor.run {
                    if let index = self.analyses.firstIndex(where: { $0.projectPath == newAnalysis.projectPath }) {
                        self.analyses[index] = newAnalysis
                    } else {
                        self.analyses.append(newAnalysis)
                    }

                    self.selectedAnalysisID = newAnalysis.id
                    self.saveAnalyses()
                    self.isLoading = false
                    self.schemes = []
                    self.selectedScheme = nil
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }

    func cancelSchemeSelection() {
        projectToScan = nil
        schemes = []
        selectedScheme = nil
        isLoadingSchemes = false
    }
}
