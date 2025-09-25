
import SwiftUI
import FRTMCore

@MainActor
class SecurityScannerViewModel: ObservableObject {
    @Published var analyses: [SecurityScanResult] = []
    @Published var selectedAnalysisID: UUID?
    @Published var isLoading = false
    
    @Published var analysisToOverwrite: SecurityScanResult?

    @Dependency var persistenceManager: PersistenceManager
    @Dependency var scanner: any Analyzer<SecurityScanResult>
    
    private let persistenceKey = "security_scan_analyses"

    var selectedAnalysis: SecurityScanResult? {
        guard let selectedAnalysisID = selectedAnalysisID else {
            return analyses.first
        }
        return analyses.first { $0.id == selectedAnalysisID }
    }

    func loadAnalyses() {
        self.analyses = persistenceManager.load(key: persistenceKey)
        if selectedAnalysisID == nil {
            selectedAnalysisID = analyses.first?.id
        }
    }

    func saveAnalyses() {
        persistenceManager.save(analyses, key: persistenceKey)
    }

    func selectFolderAndScan() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                if let existing = analyses.first(where: { $0.projectPath == url.path }) {
                    analysisToOverwrite = existing
                } else {
                    Task { await analyzeProject(at: url) }
                }
            }
        }
    }
    
    func forceReanalyze() {
        guard let analysis = analysisToOverwrite else { return }
        let url = URL(fileURLWithPath: analysis.projectPath)
        Task { await analyzeProject(at: url, overwriting: analysis.id) }
        analysisToOverwrite = nil
    }
    
    func cancelOverwrite() {
        analysisToOverwrite = nil
    }

    func analyzeProject(at url: URL, overwriting: UUID? = nil) async {
        isLoading = true
        
        guard let analysisResult = try? await scanner.analyze(at: url) else {
            self.isLoading = false
            return
        }
        
        if let overwritingID = overwriting, let index = self.analyses.firstIndex(where: { $0.id == overwritingID }) {
            self.analyses[index] = analysisResult
        } else {
            self.analyses.append(analysisResult)
        }
        self.selectedAnalysisID = analysisResult.id
        self.saveAnalyses()
        self.isLoading = false
    }
    
    func deleteAnalysis(_ analysis: SecurityScanResult) {
        if selectedAnalysisID == analysis.id {
            selectedAnalysisID = analyses.first(where: { $0.id != analysis.id })?.id
        }
        analyses.removeAll { $0.id == analysis.id }
        saveAnalyses()
    }
}
