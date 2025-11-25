import Foundation

enum CategoryType: String, CaseIterable {
    case binary = "Binary"
    case frameworks = "Frameworks"
    case assets = "Assets"
    case bundles = "Bundles"
    case appClips = "AppClips"
    case resources = "Resources"
    case nativeLibs = "Native Libraries"
    case dexFiles = "Dex Files"
    
    var displayName: String {
        switch self {
        case .binary:
            return "Main app binary"
        default:
            return self.rawValue
        }
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

    var sizeText: String {
        SizeTextFormatter.formatSize(totalSize, categoryName: name, itemCount: items.count)
    }
}

class CategoryGenerator {
    static func generateCategories(from rootFile: FileInfo) -> [CategoryResult] {
        if isAndroidBundle(rootFile) {
            return generateAndroidCategories(from: rootFile)
        } else {
            return generateAppleCategories(from: rootFile)
        }
    }

    // MARK: - Apple bundle strategy

    private static func generateAppleCategories(from rootFile: FileInfo) -> [CategoryResult] {
        guard let allFiles = rootFile.subItems else { return [] }
        
        var categoryItems: [CategoryType: [FileInfo]] = [:]
        var remainingFiles = allFiles
        
        if let macOSFolder = allFiles.first(where: { $0.name == "MacOS" && $0.type == .directory }) {
            let binaries = macOSFolder.subItems?.filter { $0.type == .binary } ?? []
            if !binaries.isEmpty {
                categoryItems[.binary] = binaries
                remainingFiles.removeAll { $0.id == macOSFolder.id }
            }
        } else if let binary = allFiles.first(where: { $0.type == .binary }) {
            categoryItems[.binary] = [binary]
            remainingFiles.removeAll { $0.id == binary.id }
        }
        
        if let frameworks = allFiles.first(where: { $0.name == "Frameworks" && $0.type == .directory }) {
            categoryItems[.frameworks] = frameworks.subItems ?? []
            remainingFiles.removeAll { $0.id == frameworks.id }
        }
        
        if let resourcesFolder = allFiles.first(where: { $0.name == "Resources" && $0.type == .directory }) {
            var folderItems = resourcesFolder.subItems ?? []
            let assetsFiles = folderItems.filter { $0.name == "Assets.car" }
            if !assetsFiles.isEmpty {
                categoryItems[.assets, default: []].append(contentsOf: assetsFiles)
                folderItems.removeAll { file in assetsFiles.contains { $0.id == file.id } }
            }
            
            if !folderItems.isEmpty {
                categoryItems[.resources, default: []].append(contentsOf: folderItems)
            }
            remainingFiles.removeAll { $0.id == resourcesFolder.id }
        }
        
        let rootAssets = allFiles.filter { $0.name == "Assets.car" }
        if !rootAssets.isEmpty {
            categoryItems[.assets, default: []].append(contentsOf: rootAssets)
            remainingFiles.removeAll { file in rootAssets.contains { $0.id == file.id } }
        }
        
        let bundles = remainingFiles.filter { $0.type == .bundle }
        if !bundles.isEmpty {
            categoryItems[.bundles] = bundles
            remainingFiles.removeAll { file in bundles.contains { $0.id == file.id } }
        }
        
        if let appClips = remainingFiles.first(where: { $0.name == "AppClips" && $0.type == .directory }) {
            categoryItems[.appClips] = appClips.subItems ?? []
            remainingFiles.removeAll { $0.id == appClips.id }
        }
        
        let knownFolders = ["_CodeSignature", "SC_Info", "PlugIns", "Watch", "Info.plist"]
        remainingFiles.removeAll { file in knownFolders.contains(file.name) }
        
        if !remainingFiles.isEmpty {
            categoryItems[.resources, default: []].append(contentsOf: remainingFiles)
        }
        
        return categoryItems.compactMap { (type, items) -> CategoryResult? in
            guard !items.isEmpty else { return nil }
            // Ensure Android-only categories are never included in iOS analysis
            guard type != .dexFiles && type != .nativeLibs else { return nil }
            let totalSize = items.reduce(0) { $0 + $1.size }
            return CategoryResult(type: type, totalSize: totalSize, items: items)
        }
        .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Android bundle strategy

    private static func generateAndroidCategories(from rootFile: FileInfo) -> [CategoryResult] {
        var categories: [CategoryResult] = []
        let flattenedFiles = rootFile.flattened(includeDirectories: true)
        let fileLeaves = rootFile.flattened(includeDirectories: false)
        var usedIds = Set<UUID>()
        
        let dexFiles = fileLeaves.filter { $0.name.lowercased().hasSuffix(".dex") }
        appendCategory(.dexFiles, items: dexFiles, to: &categories, usedIds: &usedIds)
        
        if let libDir = rootFile.subItems?.first(where: { $0.name.lowercased() == "lib" }) {
            appendCategory(.nativeLibs, items: [libDir], to: &categories, usedIds: &usedIds)
        } else {
            let nativeLibs = fileLeaves.filter { $0.name.lowercased().hasSuffix(".so") }
            appendCategory(.nativeLibs, items: nativeLibs, to: &categories, usedIds: &usedIds)
        }
        
        if let assetsDir = rootFile.subItems?.first(where: { $0.name.lowercased() == "assets" }) {
            appendCategory(.assets, items: [assetsDir], to: &categories, usedIds: &usedIds)
        }
        
        var resourceItems: [FileInfo] = []
        if let resDir = rootFile.subItems?.first(where: { $0.name.lowercased() == "res" }) {
            resourceItems.append(resDir)
        }
        let arscFiles = fileLeaves.filter { $0.name.lowercased() == "resources.arsc" }
        resourceItems.append(contentsOf: arscFiles)
        appendCategory(.resources, items: resourceItems, to: &categories, usedIds: &usedIds)
        
        let remaining = flattenedFiles.filter { $0.id != rootFile.id && !usedIds.contains($0.id) }
        appendCategory(.resources, items: remaining, to: &categories, usedIds: &usedIds)
        
        return categories.sorted { $0.totalSize > $1.totalSize }
    }

    private static func appendCategory(_ type: CategoryType, items: [FileInfo], to categories: inout [CategoryResult], usedIds: inout Set<UUID>) {
        guard !items.isEmpty else { return }
        // Ensure iOS-only categories are never included in Android analysis
        guard type != .frameworks && type != .bundles && type != .appClips else { return }
        let ids = items.flatMap { $0.flattened(includeDirectories: true).map(\.id) }
        usedIds.formUnion(ids)
        let total = items.reduce(0) { $0 + $1.size }
        if let index = categories.firstIndex(where: { $0.type == type }) {
            let mergedItems = categories[index].items + items
            let mergedTotal = mergedItems.reduce(0) { $0 + $1.size }
            categories[index] = CategoryResult(type: type, totalSize: mergedTotal, items: mergedItems)
        } else {
            categories.append(CategoryResult(type: type, totalSize: total, items: items))
        }
    }

    private static func isAndroidBundle(_ rootFile: FileInfo) -> Bool {
        let files = rootFile.flattened(includeDirectories: true)
        return files.contains(where: { $0.name.lowercased() == "androidmanifest.xml" })
            || files.contains(where: { $0.name.lowercased().hasSuffix(".dex") })
    }
}
