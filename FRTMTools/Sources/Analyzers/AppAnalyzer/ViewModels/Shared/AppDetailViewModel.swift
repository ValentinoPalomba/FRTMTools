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
    var categoriesCount: Int { categories.count }
    var hasCategories: Bool { !categories.isEmpty }
    var archTypesDescription: String {
        archs.types.isEmpty ? "—" : archs.types.joined(separator: ", ")
    }

    func categoryName(for id: String) -> String? {
        categories.first(where: { $0.id == id })?.name
    }

    func topFiles(for categoryName: String, limit: Int) -> [FileInfo] {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return [] }
        return Array(category.items.sorted { $0.size > $1.size }.prefix(limit))
    }

    func filteredCategories(searchText: String) -> [CategoryResult] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setCachedFilteredCategories(nil)
            return categories
        }
        let lowered = trimmed.lowercased()
        let signature = categoriesSignature(for: categories)

        if let cached = cachedFilteredCategories(), cached.query == lowered, cached.signature == signature {
            return cached.results
        }

        let results = categories.compactMap { category -> CategoryResult? in
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
        setCachedFilteredCategories(CategorySearchCacheEntry(query: lowered, signature: signature, results: results))
        return results
    }

    private func categoriesSignature(for categories: [CategoryResult]) -> Int {
        var hasher = Hasher()
        hasher.combine(categories.count)
        for category in categories {
            hasher.combine(category.id)
            hasher.combine(category.totalSize)
        }
        return hasher.finalize()
    }

    private func cacheIdentifier() -> ObjectIdentifier {
        ObjectIdentifier(self)
    }

    private func cachedFilteredCategories() -> CategorySearchCacheEntry? {
        CategoryFilteredResultsCache.storage[cacheIdentifier()]
    }

    private func setCachedFilteredCategories(_ entry: CategorySearchCacheEntry?) {
        CategoryFilteredResultsCache.storage[cacheIdentifier()] = entry
    }
}

private struct CategorySearchCacheEntry {
    let query: String
    let signature: Int
    let results: [CategoryResult]
}

@MainActor
private enum CategoryFilteredResultsCache {
    static var storage: [ObjectIdentifier: CategorySearchCacheEntry] = [:]
}
