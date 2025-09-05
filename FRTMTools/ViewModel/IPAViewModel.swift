import SwiftUI
import AppKit
import FRTMCore

class IPAViewModel: ObservableObject {
    @Published var analyses: [IPAAnalysis] = []
    @Published var isLoading = false
    @Published var compareMode = false
    @Published var selectedUUID = UUID()
    @Dependency var persistenceManager: PersistenceManager
    @Dependency var analyzer: Analyzer
    func loadAnalyses() {
        self.analyses = persistenceManager.loadAnalyses()
        if let first = self.analyses.first {
            self.selectedUUID = first.id
        }
    }
    
    func saveAnalyses() {
        persistenceManager.saveAnalyses(analyses)
    }

    func analyzeIPAFile(_ url: URL) {
        isLoading = true
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let analysis = self.analyzer.analyze(at: url) {
                await MainActor.run {
                    withAnimation {
                        self.analyses.append(analysis)
                        self.selectedUUID = analysis.id
                        self.isLoading = false
                        self.saveAnalyses() // Save after adding
                    }
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    func deleteAnalysis(at offsets: IndexSet) {
        analyses.remove(atOffsets: offsets)
        saveAnalyses()
    }

    func toggleSelection(_ id: UUID) {
        withAnimation { selectedUUID = id }
    }
    
    func selectIPAFile() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["ipa"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select an IPA file"
        
        if panel.runModal() == .OK, let url = panel.url {
            analyzeIPAFile(url)
        }
    }
}


struct ComparisonViewModel {
    let analysis1: IPAAnalysis
    let analysis2: IPAAnalysis

    var fileDiffs: [FileDiff] {
        var diffs: [FileDiff] = []
        
        let allFiles1 = Dictionary(uniqueKeysWithValues: flatten(file: analysis1.rootFile).map { ($0.name, $0.size) })
        let allFiles2 = Dictionary(uniqueKeysWithValues: flatten(file: analysis2.rootFile).map { ($0.name, $0.size) })
        
        let allKeys = Set(allFiles1.keys).union(allFiles2.keys)
        
        for key in allKeys.sorted() {
            let size1 = allFiles1[key] ?? 0
            let size2 = allFiles2[key] ?? 0
            if size1 != size2 {
                diffs.append(FileDiff(name: key, size1: size1, size2: size2))
            }
        }
        
        return diffs
    }
    
    private func flatten(file: FileInfo) -> [FileInfo] {
        var files: [FileInfo] = []
        if let subItems = file.subItems {
            for subItem in subItems {
                files.append(contentsOf: flatten(file: subItem))
            }
        } else {
            files.append(file)
        }
        return files
    }
}
