import Foundation

final class APKDetailViewModel: AppDetailViewModel {
    typealias Analysis = APKAnalysis
    typealias SizeAnalyzer = APKViewModel

    let analysis: APKAnalysis
    private let apkViewModel: APKViewModel

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

    func filteredCategories(searchText: String) -> [CategoryResult] {
        guard !searchText.isEmpty else { return categories }
        return categories.compactMap { category in
            let filteredItems = category.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            guard !filteredItems.isEmpty else { return nil }
            let totalSize = filteredItems.reduce(0) { $0 + $1.size }
            return CategoryResult(
                type: category.type,
                totalSize: totalSize,
                items: filteredItems
            )
        }
    }

    func categoryName(for id: String) -> String? {
        categories.first { $0.id == id }?.name
    }

    func topFiles(for categoryName: String, limit: Int) -> [FileInfo] {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return [] }
        let sorted = category.items.sorted { $0.size > $1.size }
        return Array(sorted.prefix(limit))
    }
}
