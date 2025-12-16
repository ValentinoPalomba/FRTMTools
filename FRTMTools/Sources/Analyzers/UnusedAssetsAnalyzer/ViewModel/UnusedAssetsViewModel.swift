import SwiftUI
import FRTMCore

@MainActor
class UnusedAssetsViewModel: ObservableObject {
    @Published var analyses: [UnusedAssetResult] = []
    @Published var selectedAnalysisID: UUID?
    @Published var isLoading = false
    @Published var error: UnusedAssetsError?
    
    @Published var selectedAssets = Set<AssetInfo.ID>()
    
    @Published var analysisToOverwrite: UnusedAssetResult?

    @Dependency var persistenceManager: PersistenceManager
    @Dependency var assetAnalyzer: any Analyzer<UnusedAssetResult>
    
    private let persistenceKey = "unused_assets_analyses"

    var selectedAnalysis: UnusedAssetResult? {
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

    func selectProjectFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                if let existing = analyses.first(where: { $0.projectPath == url.path }) {
                    analysisToOverwrite = existing
                } else {
                    analyzeProject(at: url)
                }
            }
        }
    }
    
    func forceReanalyze() {
        guard let analysis = analysisToOverwrite else { return }
        let url = URL(fileURLWithPath: analysis.projectPath)
        analyzeProject(at: url, overwriting: analysis.id)
        analysisToOverwrite = nil
    }
    
    func cancelOverwrite() {
        analysisToOverwrite = nil
    }

    func analyzeProject(at url: URL, overwriting: UUID? = nil) {
        isLoading = true
        error = nil
        Task {
            do {
                if let analysisResult = try await assetAnalyzer.analyze(
                    at: url
                ) {
                    DispatchQueue.main.async {
                        if let overwritingID = overwriting, let index = self.analyses.firstIndex(where: { $0.id == overwritingID }) {
                            self.analyses[index] = analysisResult
                        } else {
                            self.analyses.append(analysisResult)
                        }
                        self.selectedAnalysisID = analysisResult.id
                        self.saveAnalyses()
                        self.isLoading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.error = UnusedAssetsError.invalidConfiguration
                }
            }
        }
    }
    
    func deleteAnalysis(_ analysis: UnusedAssetResult) {
        if selectedAnalysisID == analysis.id {
            selectedAnalysisID = analyses.first(where: { $0.id != analysis.id })?.id
        }
        analyses.removeAll { $0.id == analysis.id }
        saveAnalyses()
    }
    
    func toggleAssetSelection(_ assetID: AssetInfo.ID) {
        if selectedAssets.contains(assetID) {
            selectedAssets.remove(assetID)
        } else {
            selectedAssets.insert(assetID)
        }
    }

    func toggleSelectAll(for group: AssetTypeGroup) {
        let groupAssetIDs = Set(group.assets.map { $0.id })
        let areAllSelected = groupAssetIDs.isSubset(of: selectedAssets)
        
        if areAllSelected {
            selectedAssets.subtract(groupAssetIDs)
        } else {
            selectedAssets.formUnion(groupAssetIDs)
        }
    }

    func deleteSelectedAssets() {
        guard let selectedAnalysisID = self.selectedAnalysisID,
              let analysisIndex = analyses.firstIndex(where: { $0.id == selectedAnalysisID }) else { return }

        var updatedAnalysis = analyses[analysisIndex]
        let assetsToDelete = updatedAnalysis.unusedAssets.filter { selectedAssets.contains($0.id) }
        
        guard !assetsToDelete.isEmpty else { return }

        do {
            _ = try UnusedAssetWrapper.deleteUnusedAssets(assetInfo: assetsToDelete)
            
            updatedAnalysis.unusedAssets.removeAll { selectedAssets.contains($0.id) }
            updatedAnalysis.totalUnusedSize = updatedAnalysis.unusedAssets.reduce(0) { $0 + $1.size }
            
            self.analyses[analysisIndex] = updatedAnalysis
            self.selectedAssets.removeAll()
            
        } catch {
            print("Failed to delete assets: \(error)")
            // self.error = .failedToDelete(error)
        }
    }
    
    func exportToCSV() {
        guard let analysis = selectedAnalysis else { return }

        do {
            let csvString = try analysis.export()
            guard let data = csvString.data(using: .utf8) else { return }
            
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            if let analysis = selectedAnalysis {
                savePanel.nameFieldStringValue = "\(analysis.projectName)_UnusedAssets.csv"
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
