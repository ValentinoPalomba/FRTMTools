import Foundation
import SwiftUI
import PeripheryKit
import SourceGraph
import FRTMCore

extension Accessibility: @retroactive CaseIterable {
    public static var allCases: [Accessibility] = [
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

    @Published var errorMessage: String?

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
    
    // Schemes for a selected project before scanning
    @Published var schemes: [String] = []
    @Published var selectedScheme: String?
    var projectToScan: URL?

    private let scanner = DeadCodeScanner()

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
        if selectedAnalysisID == analysis.id {
            selectedAnalysisID = analyses.first(where: { $0.id != analysis.id })?.id
        }
        analyses.removeAll { $0.id == analysis.id }
        saveAnalyses()
    }

    // MARK: - Data Processing
    private func updateFilteredAndGroupedResults() {
        guard let results = selectedAnalysis?.results else {
            self.filteredResults = []
            self.resultsByKind = []
            return
        }

        let filtered = results.filter { result in
            selectedKinds.contains(result.kind) &&
            selectedAccessibilities
                .contains(where: {
                    result.accessibility == $0.rawValue })
        }
        self.filteredResults = filtered

        let grouped = Dictionary(grouping: filtered, by: { $0.kind })
        self.resultsByKind = grouped.map { kind, results in
            DeadCodeGroup(kind: kind, results: results)
        }.sorted { $0.results.count > $1.results.count }.sorted { $0.id > $1.id }
    }
    
    // MARK: - Scanning Logic
    
    private func annotationDescription(for result: ScanResult) -> String {
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
        panel.allowedFileTypes = ["xcodeproj", "xcworkspace"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false // Should be false to select a file
        panel.title = "Select an xcodeproj or xcworkspace file"

        if panel.runModal() == .OK, let url = panel.url {
            self.projectToScan = url
            self.schemes = []
            self.selectedScheme = nil
            loadSchemes(for: url)
        } else {
            self.errorMessage = "Failed to select file"
        }
    }

    private func loadSchemes(for projectURL: URL) {
        isLoadingSchemes = true
        Task {
            do {
                self.schemes = try await Task { try scanner.listSchemes(for: projectURL) }.value
            } catch {
                self.errorMessage = "Failed to load schemes: \(error.localizedDescription)"
            }
        }
    }

    func runScan() {
        isLoadingSchemes = false
        guard let projectURL = projectToScan, let scheme = selectedScheme else {
            errorMessage = "Project path or scheme not selected."
            return
        }
        
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let startTime = Date().timeIntervalSince1970
                let scanResults = try self.scanner.scan(
                    projectPath: projectURL.path,
                    scheme: scheme
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
                        annotationDescription: self.annotationDescription(for: result)
                    )
                }

                let newAnalysis = DeadCodeAnalysis(
                    id: UUID(),
                    projectName: projectURL.lastPathComponent,
                    projectPath: projectURL.path,
                    scanTimeDuration: endTime - startTime,
                    results: serializableResults
                )

                DispatchQueue.main.async {
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
                DispatchQueue.main.async {
                    self.errorMessage = "Scan failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
