import Foundation
import AppKit

final class APKDetailViewModel: AppDetailViewModel {
    typealias Analysis = APKAnalysis
    typealias SizeAnalyzer = APKViewModel

    let analysis: APKAnalysis
    private let apkViewModel: APKViewModel
    private let imageExtractor = APKImageExtractor()

    init(analysis: APKAnalysis, apkViewModel: APKViewModel) {
        self.analysis = analysis
        self.apkViewModel = apkViewModel
    }

    var sizeAnalyzer: APKViewModel? { apkViewModel }

    var categories: [CategoryResult] {
        apkViewModel.categories(for: analysis)
    }

    var archs: ArchsResult {
        apkViewModel.archs(for: analysis)
    }

    var categoriesCount: Int { categories.count }
    var hasCategories: Bool { !categories.isEmpty }

    var archTypesDescription: String {
        archs.types.joined(separator: ", ")
    }

    var buildsForApp: [APKAnalysis] {
        let key = analysis.packageName ?? analysis.executableName ?? analysis.fileName
        let builds = apkViewModel.groupedAnalyses[key] ?? []
        return builds.sorted {
            let vA = $0.version ?? "0"
            let vB = $1.version ?? "0"
            return vA.compare(vB, options: .numeric) == .orderedAscending
        }
    }

    var tipsBaseURL: URL? {
        analysis.url
    }

    var tips: [Tip] {
        apkViewModel.tips(for: analysis)
    }

    func categoryName(for id: String) -> String? {
        categories.first { $0.id == id }?.name
    }

    func topFiles(for categoryName: String, limit: Int) -> [FileInfo] {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return [] }
        let sorted = category.items.sorted { $0.size > $1.size }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Image Extraction

    /// Gets the count of images in the APK
    var imageCount: Int {
        let layout = AndroidPackageLayout(rootURL: analysis.url, manifestURL: nil)
        return imageExtractor.imageCount(in: layout)
    }

    /// Extracts all images from the APK to a user-selected folder
    /// - Parameter preserveStructure: Whether to preserve directory structure
    /// - Returns: Extraction result with statistics
    @MainActor
    func extractImages(preserveStructure: Bool = true) -> APKImageExtractor.ExtractionResult? {
        // Show save panel for destination selection
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.title = "Choose Destination for Extracted Images"
        savePanel.message = "Select a folder where images will be extracted"
        savePanel.nameFieldStringValue = "\(analysis.fileName)-images"
        savePanel.prompt = "Extract Here"

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return nil
        }

        let layout = AndroidPackageLayout(rootURL: analysis.url, manifestURL: nil)
        return imageExtractor.extractImages(from: layout, to: destinationURL, preserveStructure: preserveStructure)
    }

    /// Reveals the extracted images in Finder
    /// - Parameter result: The extraction result containing the destination URL
    func revealExtractedImages(_ result: APKImageExtractor.ExtractionResult) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: result.destinationURL.path)
    }
}
