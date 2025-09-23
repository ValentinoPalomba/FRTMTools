import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FRTMCore

class IPAViewModel: ObservableObject {
    
    @Published var analyses: [IPAAnalysis] = []
    @Published var isLoading = false
    @Published var isSizeLoading = false
    @Published var compareMode = false
    @Published var selectedUUID = UUID()
    @Published var sizeAnalysisProgress = ""
    @Published var sizeAnalysisAlert: AlertContent?
    
    @Dependency var persistenceManager: PersistenceManager
    @Dependency var analyzer: any Analyzer<IPAAnalysis>
    var sizeAnalyzer: IPASizeAnalyzer = .init()
    
    private let persistenceKey = "ipa_analyses"

    struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func loadAnalyses() {
        self.analyses = persistenceManager.load(key: persistenceKey)
        if let first = self.analyses.first {
            self.selectedUUID = first.id
        }
    }
    
    
    
    func analyzeSize() {
        Task { @MainActor in
            guard let analysis = analyses.firstIndex(where: { $0.id == selectedUUID }) else {
                return
            }
            isSizeLoading = true
            sizeAnalysisProgress = ""
            do {
                let sizeAnalysis = try await sizeAnalyzer.analyze(
                    ipaPath: analyses[analysis].url.path()
                ) { sizeAnalysisUpdate in
                    DispatchQueue.main.async { [weak self] in
                        self?.sizeAnalysisProgress = sizeAnalysisUpdate
                    }
                }
                
                analyses[analysis].installedSize = IPAAnalysis.InstalledSize(
                    total: sizeAnalysis.sizeInMB,
                    binaries: sizeAnalysis.appBinariesInMB,
                    frameworks: sizeAnalysis.frameworksInMB,
                    resources: sizeAnalysis.resourcesInMB
                )
                
                saveAnalyses()
                isSizeLoading = false
            } catch {
                let message: String
                if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription, !description.isEmpty {
                    message = description
                } else {
                    message = error.localizedDescription
                }
                sizeAnalysisAlert = AlertContent(
                    title: "Size Analysis Failed",
                    message: message
                )
                isSizeLoading = false
            }
        }
    }
    
    func saveAnalyses() {
        persistenceManager.save(analyses, key: persistenceKey)
    }

    func analyzeFile(_ url: URL) {
        Task { @MainActor in
            isLoading = true
        }
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let analysis = try await self.analyzer.analyze(at: url) {
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
    
    func selectFile() {
        let panel = NSOpenPanel()
        
        var contentTypes: [UTType] = []
        if let ipaType = UTType(filenameExtension: "ipa") {
            contentTypes.append(ipaType)
        }
        if let appType = UTType(filenameExtension: "app") {
            contentTypes.append(appType)
        }
        contentTypes.append(.applicationBundle)
        panel.allowedContentTypes = contentTypes
        
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.title = "Select an IPA or App file"
        
        if panel.runModal() == .OK, let url = panel.url {
            analyzeFile(url)
        }
    }
    
    func revealAnalysesJSONInFinder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = appSupport.appendingPathComponent("FRTMTools")
        let jsonURL = appDirectory.appendingPathComponent("\(persistenceKey).json")

        if !FileManager.default.fileExists(atPath: appDirectory.path) {
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        if !FileManager.default.fileExists(atPath: jsonURL.path) {
            print("[DEBUG] ipa_analyses.json not found")
        }

        if FileManager.default.fileExists(atPath: jsonURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([jsonURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([appDirectory])
        }
    }
}
