import Foundation

struct CategoryResult: Identifiable {
    var id: String { name }
    let name: String
    let totalSize: Int64
    let items: [FileInfo]
}

class CategoryGenerator {
    static func generateCategories(from rootFile: FileInfo) -> [CategoryResult] {
        guard let allFiles = rootFile.subItems else { return [] }

        var categories: [CategoryResult] = []
        var remainingFiles = allFiles

        // Binary
        if let binary = allFiles.first(where: { $0.type == .binary }) {
            categories.append(CategoryResult(name: "Binary", totalSize: binary.size, items: [binary]))
            remainingFiles.removeAll { $0.id == binary.id }
        }

        // Frameworks
        if let frameworks = allFiles.first(where: { $0.name == "Frameworks" && $0.type == .directory }) {
            categories.append(CategoryResult(name: "Frameworks", totalSize: frameworks.size, items: frameworks.subItems ?? []))
            remainingFiles.removeAll { $0.id == frameworks.id }
        }

        // Assets
        if let assets = allFiles.first(where: { $0.name == "Assets.car" }) {
            categories.append(CategoryResult(name: "Assets", totalSize: assets.size, items: [assets]))
            remainingFiles.removeAll { $0.id == assets.id }
        }
        
        // Bundles
        let bundles = allFiles.filter { $0.type == .bundle }
        if !bundles.isEmpty {
            let totalSize = bundles.reduce(0) { $0 + $1.size }
            categories.append(CategoryResult(name: "Bundles", totalSize: totalSize, items: bundles))
            remainingFiles.removeAll { file in bundles.contains { $0.id == file.id } }
        }
        
        // App Clips
        if let appClips = allFiles.first(where: { $0.name == "AppClips" && $0.type == .directory }) {
            categories.append(CategoryResult(name: "AppClips", totalSize: appClips.size, items: appClips.subItems ?? []))
            remainingFiles.removeAll { $0.id == appClips.id }
        }

        // Other known folders to exclude from resources
        let knownFolders = ["_CodeSignature", "SC_Info", "PlugIns", "Watch"]
        remainingFiles.removeAll { file in knownFolders.contains(file.name) }

        // The rest is resources
        if !remainingFiles.isEmpty {
            let totalSize = remainingFiles.reduce(0) { $0 + $1.size }
            categories.append(CategoryResult(name: "Resources", totalSize: totalSize, items: remainingFiles))
        }

        return categories.sorted { $0.totalSize > $1.totalSize }
    }
}