import Foundation

enum CategoryType: String, CaseIterable {
    case binary = "Binary"
    case frameworks = "Frameworks"
    case assets = "Assets"
    case bundles = "Bundles"
    case appClips = "AppClips"
    case resources = "Resources"
    
    var displayName: String {
        return self.rawValue
    }
}

struct CategoryResult: Identifiable {
    var id: String { type.rawValue }
    let type: CategoryType
    let totalSize: Int64
    let items: [FileInfo]
    
    var name: String {
        return type.displayName
    }
}

class CategoryGenerator {
    static func generateCategories(from rootFile: FileInfo) -> [CategoryResult] {
        guard let allFiles = rootFile.subItems else { return [] }
        
        // Dizionario per raccogliere gli items per categoria
        var categoryItems: [CategoryType: [FileInfo]] = [:]
        var remainingFiles = allFiles
        
        // MARK: - macOS App Structure
        
        // Binaries
        if let macOSFolder = allFiles.first(where: { $0.name == "MacOS" && $0.type == .directory }) {
            let binaries = macOSFolder.subItems?.filter { $0.type == .binary } ?? []
            if !binaries.isEmpty {
                categoryItems[.binary] = binaries
                remainingFiles.removeAll { $0.id == macOSFolder.id }
            }
        } else if let binary = allFiles.first(where: { $0.type == .binary }) { // iOS fallback
            categoryItems[.binary] = [binary]
            remainingFiles.removeAll { $0.id == binary.id }
        }
        
        // Frameworks
        if let frameworks = allFiles.first(where: { $0.name == "Frameworks" && $0.type == .directory }) {
            categoryItems[.frameworks] = frameworks.subItems ?? []
            remainingFiles.removeAll { $0.id == frameworks.id }
        }
        
        // Resources folder
        if let resourcesFolder = allFiles.first(where: { $0.name == "Resources" && $0.type == .directory }) {
            var folderItems = resourcesFolder.subItems ?? []
            
            // Trova TUTTI gli Assets.car al primo livello della cartella Resources
            let assetsFiles = folderItems.filter { $0.name == "Assets.car" }
            if !assetsFiles.isEmpty {
                categoryItems[.assets, default: []].append(contentsOf: assetsFiles)
                folderItems.removeAll { file in assetsFiles.contains { $0.id == file.id } }
            }
            
            // Aggiungi i rimanenti items della cartella Resources
            if !folderItems.isEmpty {
                categoryItems[.resources, default: []].append(contentsOf: folderItems)
            }
            remainingFiles.removeAll { $0.id == resourcesFolder.id }
        }
        
        // iOS fallback - cerca Assets.car al primo livello di root
        let rootAssets = allFiles.filter { $0.name == "Assets.car" }
        if !rootAssets.isEmpty {
            categoryItems[.assets, default: []].append(contentsOf: rootAssets)
            remainingFiles.removeAll { file in rootAssets.contains { $0.id == file.id } }
        }
        
        // Bundles
        let bundles = remainingFiles.filter { $0.type == .bundle }
        if !bundles.isEmpty {
            categoryItems[.bundles] = bundles
            remainingFiles.removeAll { file in bundles.contains { $0.id == file.id } }
        }
        
        // App Clips
        if let appClips = remainingFiles.first(where: { $0.name == "AppClips" && $0.type == .directory }) {
            categoryItems[.appClips] = appClips.subItems ?? []
            remainingFiles.removeAll { $0.id == appClips.id }
        }
        
        // Rimuovi cartelle conosciute
        let knownFolders = ["_CodeSignature", "SC_Info", "PlugIns", "Watch", "Info.plist"]
        remainingFiles.removeAll { file in knownFolders.contains(file.name) }
        
        // Aggiungi i file rimanenti alla categoria Resources
        if !remainingFiles.isEmpty {
            categoryItems[.resources, default: []].append(contentsOf: remainingFiles)
        }
        
        // Converti il dizionario in array di CategoryResult
        let categories = categoryItems.compactMap { (type, items) -> CategoryResult? in
            guard !items.isEmpty else { return nil }
            let totalSize = items.reduce(0) { $0 + $1.size }
            return CategoryResult(type: type, totalSize: totalSize, items: items)
        }
        
        return categories.sorted { $0.totalSize > $1.totalSize }
    }
}
