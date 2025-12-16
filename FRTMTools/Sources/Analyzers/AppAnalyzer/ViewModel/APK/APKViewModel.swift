import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FRTMCore

final class APKViewModel: ObservableObject, InstalledSizeAnalyzing {

    typealias Analysis = APKAnalysis
    typealias SizeAlert = AlertContent

    private var cachedCategories: [UUID: [CategoryResult]] = [:]
    private var cachedArchs: [UUID: ArchsResult] = [:]
    private var cachedTips: [UUID: [Tip]] = [:]

    @Published var analyses: [APKAnalysis] = []
    @Published var isLoading = false
    @Published var isSizeLoading = false
    @Published var compareMode = false
    @Published var selectedUUID = UUID()
    @Published var sizeAnalysisProgress = ""
    @Published var sizeAnalysisAlert: AlertContent?
    @Published var expandedExecutables: Set<String> = []

    @Dependency var persistenceManager: PersistenceManager
    @Dependency var analyzer: any Analyzer<APKAnalysis>

    private lazy var fileStore = APKFileStore(
        appDirectory: appDirectory,
        analysesDirectoryURL: analysesDirectoryURL
    )

    private let persistenceKey = "apk_analyses"

    struct AlertContent: Identifiable, SizeAlertProtocol {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - Derived data

    func categories(for analysis: APKAnalysis) -> [CategoryResult] {
        if let cached = cachedCategories[analysis.id] { return cached }
        let computed = CategoryGenerator.generateCategories(from: analysis.rootFile)
        cachedCategories[analysis.id] = computed
        return computed
    }

    func archs(for analysis: APKAnalysis) -> ArchsResult {
        if let cached = cachedArchs[analysis.id] { return cached }
        let abis = analysis.supportedABIs 
        let computed: ArchsResult
        if abis.isEmpty {
            computed = .none
        } else {
            computed = ArchsResult(number: abis.count, types: abis)
        }
        cachedArchs[analysis.id] = computed
        return computed
    }

    func tips(for analysis: APKAnalysis) -> [Tip] {
        if let cached = cachedTips[analysis.id] { return cached }
        let computed = TipGenerator.generateTips(for: analysis)
        cachedTips[analysis.id] = computed
        return computed
    }

    var groupedAnalyses: [String: [APKAnalysis]] {
        let grouped = Dictionary(grouping: analyses, by: { analysis in
            analysis.packageName ?? analysis.executableName ?? analysis.fileName
        })
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

    var selectedAnalysis: APKAnalysis? {
        if let selected = analyses.first(where: { $0.id == selectedUUID }) {
            return selected
        }
        return analyses.first
    }

    var tipsBaseURL: URL? {
        selectedAnalysis?.url
    }

    var categories: [CategoryResult] {
        guard let selectedAnalysis else { return [] }
        return CategoryGenerator.generateCategories(from: selectedAnalysis.rootFile)
    }

    var archs: ArchsResult {
        guard let selectedAnalysis else { return .none }
        return ArchsResult(
            number: selectedAnalysis.supportedABIs.count,
            types: selectedAnalysis.supportedABIs
        )
    }

    // MARK: - Persistence

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
                print("Failed to load APK analyses: \(error)")
            }
        }
    }

    func saveAnalyses() {
        Task { @MainActor in
            do {
                try await fileStore.saveAnalyses(self.analyses)
            } catch {
                print("Failed to save APK analyses: \(error)")
            }
        }
    }

    // MARK: - Size analysis

    func analyzeSize(for analysisID: UUID) {
        Task { @MainActor in
            guard let index = analyses.firstIndex(where: { $0.id == analysisID }) else {
                return
            }
            isSizeLoading = true
            sizeAnalysisProgress = ""
            defer { isSizeLoading = false }

            let breakdown = APKSizeBreakdownCalculator.calculate(from: analyses[index].rootFile)
            analyses[index].installedSize = breakdown
            do {
                try await fileStore.saveAnalyses(self.analyses)
            } catch {
                sizeAnalysisAlert = AlertContent(title: "Size Analysis Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Analysis

    func analyzeFile(_ url: URL) {
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            do {
                if let analysis = try await analyzer.analyze(at: url) {
                    withAnimation {
                        analyses.append(analysis)
                        cachedCategories[analysis.id] = CategoryGenerator.generateCategories(from: analysis.rootFile)
                        cachedArchs[analysis.id] = archs
                        cachedTips[analysis.id] = TipGenerator.generateTips(for: analysis)
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

    // MARK: - UI helpers

    func toggleSelection(_ id: UUID) {
        selectedUUID = id
    }

    func selectFile() {
        let panel = NSOpenPanel()
        var contentTypes: [UTType] = []
        ["apk", "aab", "abb"].forEach { ext in
            if let type = UTType(filenameExtension: ext) {
                contentTypes.append(type)
            }
        }
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select an APK or App Bundle"
        if panel.runModal() == .OK, let url = panel.url {
            analyzeFile(url)
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

    func revealAnalysesJSONInFinder() {
        if let selected = analyses.first(where: { $0.id == selectedUUID }) {
            revealAnalysisJSONInFinder(selected.id)
            return
        }
        ensureAnalysesDirectoryExists()
        NSWorkspace.shared.activateFileViewerSelecting([analysesDirectoryURL])
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
            savePanel.nameFieldStringValue = "\(analysis.fileName)_AppAnalysis.csv"

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

    private func saveAnalysis(_ analysis: APKAnalysis) {
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
            saveAnalysis(analysis)
        }

        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([analysesDirectoryURL])
        }
    }

}
