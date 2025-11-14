import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FRTMCore

@MainActor
final class IPAViewModel: ObservableObject {
    
    // Cache for expensive per-analysis computations
    private var cachedCategories: [UUID: [CategoryResult]] = [:]
    private var cachedArchs: [UUID: ArchsResult] = [:]
    private var cachedTips: [UUID: [Tip]] = [:]
    
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
    
    // Off-main persistence actor for file I/O
    private lazy var fileStore = IPAFileStore(
        appDirectory: appDirectory,
        analysesDirectoryURL: analysesDirectoryURL
    )
    
    private let persistenceKey = "ipa_analyses"

    func categories(for analysis: IPAAnalysis) -> [CategoryResult] {
        if let cached = cachedCategories[analysis.id] { return cached }
        let computed = CategoryGenerator.generateCategories(from: analysis.rootFile)
        cachedCategories[analysis.id] = computed
        return computed
    }

    func archs(for analysis: IPAAnalysis) -> ArchsResult {
        if let cached = cachedArchs[analysis.id] { return cached }
        let computed = ArchsAnalyzer.generateCategories(from: analysis.rootFile)
        cachedArchs[analysis.id] = computed
        return computed
    }

    func tips(for analysis: IPAAnalysis) -> [Tip] {
        if let cached = cachedTips[analysis.id] { return cached }
        let computed = TipGenerator.generateTips(for: analysis)
        cachedTips[analysis.id] = computed
        return computed
    }

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
    
        // Tips Section
        // Compute a base URL for resolving relative paths in tips
    var tipsBaseURL: URL? {
        guard let appURL = selectedAnalysis?.url else { return nil }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let contents = appURL.appendingPathComponent("Contents")
        if fm.fileExists(atPath: contents.path, isDirectory: &isDir), isDir.boolValue {
            return contents // macOS bundle layout
        }
        return appURL
    }
    
    var categories: [CategoryResult] {
        guard let selectedAnalysis else { return [] }
        return CategoryGenerator
            .generateCategories(from: selectedAnalysis.rootFile)
    }
    
    var archs: ArchsResult {
        guard let selectedAnalysis else { return .none }
        return ArchsAnalyzer.generateCategories(from: selectedAnalysis.rootFile)
    }
    
    


    struct AlertContent: Identifiable, SizeAlertProtocol {
        let id = UUID()
        let title: String
        let message: String
    }

    func loadAnalyses() {
        Task { @MainActor in
            do {
                let loaded = try await fileStore.loadAnalyses()
                self.analyses = loaded
                self.cachedCategories.removeAll()
                self.cachedArchs.removeAll()
                self.cachedTips.removeAll()
                if let first = self.analyses.first {
                    self.selectedUUID = first.id
                }
            } catch {
                print("Failed to load analyses: \(error)")
            }
        }
    }
    
    func analyzeSize(for analysisID: UUID) {
        Task { @MainActor in
            guard let analysis = analyses.firstIndex(where: { $0.id == analysisID }) else {
                return
            }
            isSizeLoading = true
            sizeAnalysisProgress = ""
            defer { isSizeLoading = false }
            do {
                let sizeAnalysis = try await IPASizeAnalyzer().analyze(
                    ipaPath: analyses[analysis].url.path()
                ) { @Sendable sizeAnalysisUpdate in
                    Task { @MainActor in
                        self.sizeAnalysisProgress = sizeAnalysisUpdate
                    }
                }

                analyses[analysis].installedSize = InstalledSizeMetrics(
                    total: sizeAnalysis.sizeInMB,
                    binaries: sizeAnalysis.appBinariesInMB,
                    frameworks: sizeAnalysis.frameworksInMB,
                    resources: sizeAnalysis.resourcesInMB
                )

                try await fileStore.saveAnalyses(self.analyses)
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
            }
        }
    }
    
    func saveAnalyses() {
        Task { @MainActor in
            do {
                try await fileStore.saveAnalyses(self.analyses)
            } catch {
                print("Failed to save analyses: \(error)")
            }
        }
    }

    func analyzeFile(_ url: URL) {
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            do {
                if let analysis = try await analyzer.analyze(at: url) {
                    withAnimation {
                        analyses.append(analysis)
                        // Precompute cached data for this analysis
                        self.cachedCategories[analysis.id] = CategoryGenerator.generateCategories(from: analysis.rootFile)
                        self.cachedArchs[analysis.id] = ArchsAnalyzer.generateCategories(from: analysis.rootFile)
                        self.cachedTips[analysis.id] = TipGenerator.generateTips(for: analysis)
                        selectedUUID = analysis.id
                    }
                    try await fileStore.saveAnalyses(self.analyses)
                }
            } catch {
                let message: String
                if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription, !description.isEmpty {
                    message = description
                } else {
                    message = error.localizedDescription
                }
                sizeAnalysisAlert = AlertContent(
                    title: "App Analysis Failed",
                    message: message
                )
            }
        }
    }
    
    
    func deleteAnalysis(withId id: UUID) {
        Task { @MainActor in
            if let analysis = analyses.first(where: { $0.id == id }) {
                try? await fileStore.deleteAnalysis(id: analysis.id)
            }
            analyses.removeAll(where: { $0.id == id })
            cachedCategories[id] = nil
            cachedArchs[id] = nil
            cachedTips[id] = nil
        }
    }

    func toggleSelection(_ id: UUID) {
        selectedUUID = id
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
    
    func exportToCSV() {
        guard let analysis = selectedAnalysis else { return }

        do {
            let csvString = try analysis.export()
            guard let data = csvString.data(using: .utf8) else {
                sizeAnalysisAlert = AlertContent(title: "Export Error", message: "Failed to encode CSV data.")
                return
            }
            
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            if let analysis = selectedAnalysis {
                savePanel.nameFieldStringValue = "\(analysis.fileName)_AppAnalysis.csv"
            }
            
            savePanel.begin { result in
                if result == .OK, let url = savePanel.url {
                    do {
                        try data.write(to: url)
                    } catch {
                        DispatchQueue.main.async {
                            self.sizeAnalysisAlert = AlertContent(title: "Export Error", message: error.localizedDescription)
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.sizeAnalysisAlert = AlertContent(title: "Export Error", message: error.localizedDescription)
            }
        }
    }
}

extension IPAViewModel: InstalledSizeAnalyzing {
    typealias Analysis = IPAAnalysis
    typealias SizeAlert = AlertContent
}
