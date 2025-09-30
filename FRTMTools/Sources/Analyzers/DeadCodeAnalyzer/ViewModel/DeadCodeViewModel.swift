import Foundation
import SwiftUI
import PeripheryKit
@preconcurrency import SourceGraph
import FRTMCore
import UniformTypeIdentifiers

extension Accessibility: @retroactive CaseIterable {
    public static let allCases: [Accessibility] = [
        .fileprivate, .internal, .open, .private, .public
    ]
}

@MainActor
class DeadCodeViewModel: ObservableObject {
    // MARK: - Dependencies & Persistence
    @Dependency var persistenceManager: PersistenceManager
    private let persistenceKey = "dead_code_analyses"

    // MARK: - Published Properties
    @Published var analyses: [DeadCodeAnalysis] = [] {
        didSet {
            updateFilteredAndGroupedResults()
        }
    }
    @Published var selectedAnalysisID: UUID? {
        didSet {
            updateFilteredAndGroupedResults()
        }
    }
    
    @Published var isLoading = false
    @Published var isLoadingSchemes = false

    @Published var error: Error?

    // Filter properties
    @Published var selectedKinds: Set<String> = Set(Declaration.Kind.allCases.map { $0.displayName }) {
        didSet {
            updateFilteredAndGroupedResults()
        }
    }
    @Published var selectedAccessibilities: Set<Accessibility> = Set(Accessibility.allCases) {
        didSet {
            updateFilteredAndGroupedResults()
        }
    }

    // Derived data for the view
    @Published var filteredResults: [SerializableDeadCodeResult] = []
    @Published var resultsByKind: [DeadCodeGroup] = []
    
    // Sequence token to ensure only the most recent async update applies
    private var updateSequence: Int = 0
    
    // Schemes for a selected project before scanning
    @Published var schemes: [String] = []
    @Published var selectedScheme: String?
    var projectToScan: URL?

    // MARK: - Init
    init() {
        loadAnalyses()
    }

    // MARK: - Computed Properties
    var selectedAnalysis: DeadCodeAnalysis? {
        guard let selectedAnalysisID = selectedAnalysisID else {
            return analyses.first
        }
        return analyses.first { $0.id == selectedAnalysisID }
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
        guard let analysis = selectedAnalysis as? Exportable else { return }

        do {
            let csvString = try analysis.export()
            guard let data = csvString.data(using: .utf8) else {
                DispatchQueue.main.async {
                    self.error = NSError(domain: "CSVError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode CSV data."])
                }
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
                        DispatchQueue.main.async {
                            self.error = error
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.error = error
            }
        }
    }
    private func updateFilteredAndGroupedResults() {
        // Bump sequence to invalidate any in-flight assignments
        updateSequence &+= 1
        let currentSequence = updateSequence

        // Compute new values synchronously
        let newFilteredResults: [SerializableDeadCodeResult]
        let newResultsByKind: [DeadCodeGroup]

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
        } else {
            newFilteredResults = []
            newResultsByKind = []
        }

        // Defer publishing to avoid changing @Published properties during view updates
        Task { @MainActor in
            guard self.updateSequence == currentSequence else { return }
            self.filteredResults = newFilteredResults
            self.resultsByKind = newResultsByKind
        }
    }
    
    // MARK: - Scanning Logic
    
    nonisolated private static func annotationDescription(for result: ScanResult) -> String {
        switch result.annotation {
        case .unused:
            return "Unused"
        case .assignOnlyProperty:
            return "Assigned but never used"
        case .redundantPublicAccessibility(let modules):
            if modules.isEmpty {
                return "Redundant public accessibility"
            } else {
                return "Redundant public accessibility (in \(modules.joined(separator: ", ")))"
            }
        case .redundantProtocol(let references, let inherited):
            let refCount = references.count
            if inherited.isEmpty {
                return "Redundant protocol conformance (\(refCount) reference(s))"
            } else {
                return "Redundant protocol conformance (\(refCount) reference(s), inherited from \(inherited.joined(separator: ", ")))"
            }
        }
    }

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
        } else {
            self.error = NSError(
                domain: "Failed to select project",
                code: 0
            )
        }
    }
    
    private func loadSchemes(for projectURL: URL) {
        isLoadingSchemes = true
        Task(priority: .userInitiated) {
            do {
                let schemes = try DeadCodeScanner().listSchemes(for: projectURL)
                await MainActor.run {
                    self.schemes = schemes
                }
            } catch {
                await MainActor.run {
                    self.error = error
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

                let serializableResults = scanResults.map { result -> SerializableDeadCodeResult in
                    return SerializableDeadCodeResult(
                        id: UUID(),
                        kind: result.declaration.kind.displayName,
                        accessibility: result.declaration.accessibility.value.rawValue,
                        name: result.declaration.name,
                        location: result.declaration.location.description,
                        filePath: result.declaration.location.file.path.string,
                        icon: result.declaration.kind.icon,
                        annotationDescription: Self.annotationDescription(for: result)
                    )
                }

                let newAnalysis = DeadCodeAnalysis(
                    id: UUID(),
                    projectName: URL(fileURLWithPath: projectPath).lastPathComponent,
                    projectPath: projectPath,
                    scanTimeDuration: endTime - startTime,
                    results: serializableResults
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
                    self.projectToScan = nil
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
}

