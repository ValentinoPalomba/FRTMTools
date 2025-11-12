import Foundation

final class IPADetailViewModel: AppDetailViewModel {
    typealias Analysis = IPAAnalysis
    typealias SizeAnalyzer = IPAViewModel
    let analysis: IPAAnalysis
    private let ipaViewModel: IPAViewModel

    init(analysis: IPAAnalysis, ipaViewModel: IPAViewModel) {
        self.analysis = analysis
        self.ipaViewModel = ipaViewModel
    }

    var categories: [CategoryResult] {
        ipaViewModel.categories(for: analysis)
    }

    var archs: ArchsResult {
        ipaViewModel.archs(for: analysis)
    }

    var categoriesCount: Int { categories.count }
    var hasCategories: Bool { !categories.isEmpty }

    var archTypesDescription: String {
        archs.types.joined(separator: ", ")
    }

    var buildsForApp: [IPAAnalysis] {
        let key = analysis.executableName ?? analysis.fileName
        let builds = ipaViewModel.groupedAnalyses[key] ?? []
        return builds.sorted {
            let vA = $0.version ?? "0"
            let vB = $1.version ?? "0"
            return vA.compare(vB, options: .numeric) == .orderedAscending
        }
    }

    var tipsBaseURL: URL? {
        let appURL = analysis.url
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let contents = appURL.appendingPathComponent("Contents")
        if fm.fileExists(atPath: contents.path, isDirectory: &isDir), isDir.boolValue {
            return contents
        }
        return appURL
    }

    var sizeAnalyzer: IPAViewModel? { ipaViewModel }

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
