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
    @Published var expandedExecutables: Set<String> = []
    
    @Dependency var persistenceManager: PersistenceManager
    @Dependency var analyzer: any Analyzer<IPAAnalysis>
    var sizeAnalyzer: IPASizeAnalyzer = .init()
    
    private let persistenceKey = "ipa_analyses"

    var groupedAnalyses: [String: [IPAAnalysis]] {
        let grouped = Dictionary(grouping: analyses, by: { $0.executableName ?? $0.fileName })
        return grouped.mapValues { analyses in
            analyses.sorted {
                let versionA = $0.version ?? "0"
                let versionB = $1.version ?? "0"
                return versionA.compare(versionB, options: .numeric) == .orderedDescending
            }
        }
    }

    var sortedGroupKeys: [String] {
        groupedAnalyses.keys.sorted()
    }

    var selectedAnalysis: IPAAnalysis? {
        if let selected = analyses.first(where: { $0.id == selectedUUID }) {
            return selected
        }
        return analyses.first
    }

    struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func loadAnalyses() {
        ensureAnalysesDirectoryExists()

        let fm = FileManager.default
        let dir = analysesDirectoryURL
        var loaded: [IPAAnalysis] = []

        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for file in files where file.pathExtension.lowercased() == "json" {
                if let data = try? Data(contentsOf: file), let item = try? JSONDecoder().decode(IPAAnalysis.self, from: data) {
                    loaded.append(item)
                }
            }
        }

        self.analyses = loaded

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
        for analysis in analyses {
            saveAnalysis(analysis)
        }
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
        let fm = FileManager.default
        let toDelete = offsets.map { analyses[$0] }

        // Remove files from disk
        for analysis in toDelete {
            let url = fileURL(forAnalysisID: analysis.id)
            try? fm.removeItem(at: url)
        }

        // Remove from memory
        analyses.remove(atOffsets: offsets)
    }

    func deleteAnalysis(withId id: UUID) {
        let fm = FileManager.default

        if let analysis = analyses.first(where: { $0.id == id }) {
            let url = fileURL(forAnalysisID: analysis.id)
            try? fm.removeItem(at: url)
        }

        analyses.removeAll(where: { $0.id == id })
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
        if let selected = analyses.first(where: { $0.id == selectedUUID }) {
            revealAnalysisJSONInFinder(selected.id)
            return
        }
        ensureAnalysesDirectoryExists()
        NSWorkspace.shared.activateFileViewerSelecting([analysesDirectoryURL])
    }
    
    
    // MARK: - Persistence helpers

    private var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var appDirectory: URL {
        appSupportDirectory.appendingPathComponent("FRTMTools", isDirectory: true)
    }

    private var analysesDirectoryURL: URL {
        appDirectory.appendingPathComponent(persistenceKey, isDirectory: true)
    }

    private func ensureAnalysesDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: appDirectory.path) {
            try? fm.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: analysesDirectoryURL.path) {
            try? fm.createDirectory(at: analysesDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL(forAnalysisID id: UUID) -> URL {
        analysesDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func saveAnalysis(_ analysis: IPAAnalysis) {
        ensureAnalysesDirectoryExists()
        let url = fileURL(forAnalysisID: analysis.id)
        if let data = try? JSONEncoder().encode(analysis) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func revealAnalysisJSONInFinder(_ id: UUID) {
        ensureAnalysesDirectoryExists()
        let url = fileURL(forAnalysisID: id)

        if !FileManager.default.fileExists(atPath: url.path), let analysis = analyses.first(where: { $0.id == id }) {
            // Create the file on demand if missing
            saveAnalysis(analysis)
        }

        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([analysesDirectoryURL])
        }
    }
}

