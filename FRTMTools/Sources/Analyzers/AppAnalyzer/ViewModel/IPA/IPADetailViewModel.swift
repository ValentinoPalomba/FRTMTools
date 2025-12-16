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

    var tips: [Tip] {
        ipaViewModel.tips(for: analysis)
    }

    var sizeAnalyzer: IPAViewModel? { ipaViewModel }

    lazy var tipImagePreviewMap: [String: Data] = {
        var map: [String: Data] = [:]
        let files = analysis.rootFile.flattened(includeDirectories: false)
        for file in files {
            guard let data = file.internalImageData, !data.isEmpty else { continue }
            if let path = file.path {
                map[path] = data
            }
            if let fullPath = file.fullPath {
                map[fullPath] = data
            }
            map[file.name] = data
        }
        return map
    }()

    func categoryName(for id: String) -> String? {
        categories.first { $0.id == id }?.name
    }

    func topFiles(for categoryName: String, limit: Int) -> [FileInfo] {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return [] }
        let sorted = category.items.sorted { $0.size > $1.size }
        return Array(sorted.prefix(limit))
    }
}
