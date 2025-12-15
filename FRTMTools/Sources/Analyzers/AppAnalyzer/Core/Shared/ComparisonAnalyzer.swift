import Foundation

struct ComparisonResult: Sendable {
    let categories: [ComparisonCategory]
    let modifiedFiles: [FileDiff]
    let addedFiles: [FileDiff]
    let removedFiles: [FileDiff]
}

struct ComparisonCategory: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let size1: Int64
    let size2: Int64
}

enum ComparisonAnalyzer {
    static func compare(first: any AppAnalysis, second: any AppAnalysis) -> ComparisonResult {
        let firstFiles = first.rootFile.flattened(includeDirectories: false)
        let secondFiles = second.rootFile.flattened(includeDirectories: false)

        let firstFilesMap = Dictionary(firstFiles.map { ($0.name, $0.size) }, uniquingKeysWith: { current, _ in current })
        let secondFilesMap = Dictionary(secondFiles.map { ($0.name, $0.size) }, uniquingKeysWith: { current, _ in current })
        let allFileNames = Set(firstFilesMap.keys).union(secondFilesMap.keys)

        var modifiedFiles: [FileDiff] = []
        var addedFiles: [FileDiff] = []
        var removedFiles: [FileDiff] = []

        for name in allFileNames {
            let size1 = firstFilesMap[name]
            let size2 = secondFilesMap[name]

            if let s1 = size1, let s2 = size2 {
                if s1 != s2 {
                    modifiedFiles.append(FileDiff(name: name, size1: s1, size2: s2))
                }
            } else if let s2 = size2 {
                addedFiles.append(FileDiff(name: name, size1: 0, size2: s2))
            } else if let s1 = size1 {
                removedFiles.append(FileDiff(name: name, size1: s1, size2: 0))
            }
        }

        let firstCategories = CategoryGenerator.generateCategories(from: first.rootFile)
        let secondCategories = CategoryGenerator.generateCategories(from: second.rootFile)
        let allCategoryNames = Set(firstCategories.map(\.name) + secondCategories.map(\.name))

        let categories = allCategoryNames.map { name -> ComparisonCategory in
            let size1 = firstCategories.first { $0.name == name }?.totalSize ?? 0
            let size2 = secondCategories.first { $0.name == name }?.totalSize ?? 0
            return ComparisonCategory(name: name, size1: size1, size2: size2)
        }
        .sorted { $0.name < $1.name }

        return ComparisonResult(
            categories: categories,
            modifiedFiles: modifiedFiles.sorted { $0.name < $1.name },
            addedFiles: addedFiles.sorted { $0.name < $1.name },
            removedFiles: removedFiles.sorted { $0.name < $1.name }
        )
    }
}
