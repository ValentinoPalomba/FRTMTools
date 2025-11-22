import Foundation
@MainActor
protocol AppDetailViewModel: ObservableObject {
    associatedtype Analysis: AppAnalysis
    associatedtype SizeAnalyzer: InstalledSizeAnalyzing where SizeAnalyzer.Analysis == Analysis

    var analysis: Analysis { get }
    var sizeAnalyzer: SizeAnalyzer? { get }
    var categories: [CategoryResult] { get }
    var archs: ArchsResult { get }
    var categoriesCount: Int { get }
    var hasCategories: Bool { get }
    var archTypesDescription: String { get }
    var buildsForApp: [Analysis] { get }
    var tipsBaseURL: URL? { get }
    var tips: [Tip] { get }
    var tipImagePreviewMap: [String: Data] { get }

    func filteredCategories(searchText: String) -> [CategoryResult]
    func categoryName(for id: String) -> String?
    func topFiles(for categoryName: String, limit: Int) -> [FileInfo]
}

extension AppDetailViewModel {
    var tips: [Tip] { [] }
    var tipImagePreviewMap: [String: Data] { [:] }

    func filteredCategories(searchText: String) -> [CategoryResult] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return categories }
        let lowered = trimmed.lowercased()

        return categories.compactMap { category in
            let filteredItems = category.items.compactMap { item -> (file: FileInfo, size: Int64)? in
                item.pruned(matchingLowercased: lowered)
            }
            guard !filteredItems.isEmpty else { return nil }
            let totalSize = filteredItems.reduce(0) { $0 + $1.size }
            let items = filteredItems.map(\.file)
            return CategoryResult(
                type: category.type,
                totalSize: totalSize,
                items: items
            )
        }
    }
}
