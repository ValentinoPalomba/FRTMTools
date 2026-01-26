
import SwiftUI
import FRTMCore
import Observation

@MainActor
@Observable
final class SecurityScannerViewModel {
    var analyses: [SecurityScanResult] = []
    var selectedAnalysisID: UUID?
    var isLoading = false
    
    var analysisToOverwrite: SecurityScanResult?

    @ObservationIgnored private let persistenceManagerDependency = Dependency<PersistenceManager>()
    @ObservationIgnored private let scannerDependency = Dependency<any Analyzer<SecurityScanResult>>()

    private var persistenceManager: PersistenceManager { persistenceManagerDependency.wrappedValue }
    private var scanner: any Analyzer<SecurityScanResult> { scannerDependency.wrappedValue }
    
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
    
    func exportToCSV() {
        guard let analysis = selectedAnalysis else { return }

        do {
            let csvString = try analysis.export()
            guard let data = csvString.data(using: .utf8) else { return }
            
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            if let analysis = selectedAnalysis {
                savePanel.nameFieldStringValue = "\(analysis.projectName)_SecurityReport.csv"
            }
            
            savePanel.begin { result in
                if result == .OK, let url = savePanel.url {
                    try? data.write(to: url)
                }
            }
        } catch {
            // Handle error if needed
        }
    }
}
