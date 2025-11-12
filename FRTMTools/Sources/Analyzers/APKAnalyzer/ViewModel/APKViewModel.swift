//
//  APKViewModel.swift
//  FRTMTools
//
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Main view model for APK analysis
@MainActor
class APKViewModel: ObservableObject {
    @Published var analyses: [APKAnalysis] = []
    @Published var selectedUUID: UUID?
    @Published var compareMode = false
    @Published var isLoading = false
    @Published var isSizeLoading = false
    @Published var errorMessage: String?

    @Published var useAaptForParsing: Bool {
        didSet {
            UserDefaults.standard.set(useAaptForParsing, forKey: "APKAnalyzer.useAapt")
        }
    }

    // Cached data for performance
    private var categoriesCache: [UUID: [CategoryResult]] = [:]
    private var abiCache: [UUID: (count: Int, list: [String])] = [:]

    init() {
        // Load preference from UserDefaults (defaults to true)
        self.useAaptForParsing = UserDefaults.standard.object(forKey: "APKAnalyzer.useAapt") as? Bool ?? true

        Task {
            await loadAnalyses()
        }
    }

    /// Selected analysis
    var selectedAnalysis: APKAnalysis? {
        guard let uuid = selectedUUID else { return nil }
        return analyses.first { $0.id == uuid }
    }

    /// Grouped analyses by package name
    var groupedAnalyses: [(key: String, value: [APKAnalysis])] {
        let grouped = Dictionary(grouping: analyses) { analysis in
            analysis.packageName ?? "Unknown"
        }

        return grouped.sorted { $0.key < $1.key }
    }

    /// Loads saved analyses from disk
    func loadAnalyses() async {
        do {
            let loaded = try await APKFileStore.shared.loadAnalyses()
            analyses = loaded.sorted { $0.fileName < $1.fileName }
        } catch {
            print("Failed to load analyses: \(error)")
            errorMessage = "Failed to load saved analyses: \(error.localizedDescription)"
        }
    }

    /// Saves analyses to disk
    func saveAnalyses() async {
        do {
            try await APKFileStore.shared.saveAnalyses(analyses)
        } catch {
            print("Failed to save analyses: \(error)")
            errorMessage = "Failed to save analyses: \(error.localizedDescription)"
        }
    }

    /// Analyzes an APK file
    /// - Parameter url: URL of the APK file
    func analyzeAPK(at url: URL) async {
        isLoading = true
        errorMessage = nil

        do {
            let preferAapt = useAaptForParsing
            var analysis = try await Task.detached {
                let analyzer = APKAnalyzer()
                analyzer.preferAapt = preferAapt
                return try await analyzer.analyze(at: url)
            }.value

            // Calculate installed size
            isSizeLoading = true
            if let installedSize = await APKSizeAnalyzer.analyze(analysis) {
                analysis = APKAnalysis(
                    id: analysis.id,
                    fileName: analysis.fileName,
                    packageName: analysis.packageName,
                    appLabel: analysis.appLabel,
                    url: analysis.url,
                    rootFile: analysis.rootFile,
                    versionName: analysis.versionName,
                    versionCode: analysis.versionCode,
                    minSdkVersion: analysis.minSdkVersion,
                    targetSdkVersion: analysis.targetSdkVersion,
                    permissions: analysis.permissions,
                    installedSize: installedSize,
                    dependencyGraph: analysis.dependencyGraph,
                    imageData: nil,
                    supportedABIs: analysis.supportedABIs,
                    dexFileCount: analysis.dexFileCount,
                    totalDexSize: analysis.totalDexSize,
                    isObfuscated: analysis.isObfuscated
                )
            }
            isSizeLoading = false

            // Generate dependency graph
            if let packageName = analysis.packageName {
                let graph = await APKDependencyAnalyzer.analyzeDependencies(
                    in: analysis.rootFile,
                    packageName: packageName
                )

                analysis = APKAnalysis(
                    id: analysis.id,
                    fileName: analysis.fileName,
                    packageName: analysis.packageName,
                    appLabel: analysis.appLabel,
                    url: analysis.url,
                    rootFile: analysis.rootFile,
                    versionName: analysis.versionName,
                    versionCode: analysis.versionCode,
                    minSdkVersion: analysis.minSdkVersion,
                    targetSdkVersion: analysis.targetSdkVersion,
                    permissions: analysis.permissions,
                    installedSize: analysis.installedSize,
                    dependencyGraph: graph,
                    imageData: nil,
                    supportedABIs: analysis.supportedABIs,
                    dexFileCount: analysis.dexFileCount,
                    totalDexSize: analysis.totalDexSize,
                    isObfuscated: analysis.isObfuscated
                )
            }

            analyses.append(analysis)
            selectedUUID = analysis.id

            await saveAnalyses()
        } catch {
            print("Failed to analyze APK: \(error)")
            errorMessage = "Failed to analyze APK: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Deletes an analysis
    /// - Parameter analysis: Analysis to delete
    func deleteAnalysis(_ analysis: APKAnalysis) async {
        analyses.removeAll { $0.id == analysis.id }
        categoriesCache.removeValue(forKey: analysis.id)
        abiCache.removeValue(forKey: analysis.id)

        if selectedUUID == analysis.id {
            selectedUUID = analyses.first?.id
        }

        do {
            try await APKFileStore.shared.deleteAnalysis(id: analysis.id)
        } catch {
            print("Failed to delete analysis: \(error)")
        }
    }

    /// Gets categories for an analysis (cached)
    func categories(for analysis: APKAnalysis) -> [CategoryResult] {
        if let cached = categoriesCache[analysis.id] {
            return cached
        }

        let categories = APKCategoryGenerator.generateCategories(from: analysis)
        categoriesCache[analysis.id] = categories
        return categories
    }

    /// Gets ABI info for an analysis (cached)
    func abiInfo(for analysis: APKAnalysis) -> (count: Int, list: [String]) {
        if let cached = abiCache[analysis.id] {
            return cached
        }

        let info = ABIAnalyzer.analyzeABIs(from: analysis)
        abiCache[analysis.id] = info
        return info
    }

    /// Exports analysis to CSV
    func exportToCSV(_ analysis: APKAnalysis) throws -> URL {
        var csvContent = "Path,Name,Type,Size (bytes)\n"

        func addFileToCSV(_ file: FileInfo, prefix: String = "") {
            let path = prefix + file.name
            let type = String(describing: file.type)
            csvContent += "\"\(path)\",\"\(file.name)\",\(type),\(file.size)\n"

            if let subItems = file.subItems {
                for subItem in subItems {
                    addFileToCSV(subItem, prefix: path + "/")
                }
            }
        }

        addFileToCSV(analysis.rootFile)

        let fileName = "\(analysis.fileName)_analysis.csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

        return tempURL
    }

    /// Opens file picker to select APK
    func selectAPK() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await analyzeAPK(at: url)
            }
        }
    }
}
