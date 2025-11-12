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

    func filteredCategories(searchText: String) -> [CategoryResult]
    func categoryName(for id: String) -> String?
    func topFiles(for categoryName: String, limit: Int) -> [FileInfo]
}
