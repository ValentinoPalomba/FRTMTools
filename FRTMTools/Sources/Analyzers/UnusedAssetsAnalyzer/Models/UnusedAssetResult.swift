import Foundation

// NOTE: Ensure AssetInfo and AssetType are Codable.

struct UnusedAssetResult: Codable, Identifiable {
    let id: UUID
    let projectPath: String
    let projectName: String
    
    var unusedAssets: [AssetInfo]
    var totalUnusedSize: Int64
    let totalAssetsScanned: Int
    let scanDuration: TimeInterval
    
    init(
        id: UUID = UUID(),
        projectPath: String,
        projectName: String,
        unusedAssets: [AssetInfo],
        totalUnusedSize: Int64,
        totalAssetsScanned: Int,
        scanDuration: TimeInterval
    ) {
        self.id = id
        self.projectPath = projectPath
        self.projectName = projectName
        self.unusedAssets = unusedAssets
        self.totalUnusedSize = totalUnusedSize
        self.totalAssetsScanned = totalAssetsScanned
        self.scanDuration = scanDuration
    }
}

extension UnusedAssetResult: Exportable {
    func export() throws -> String {
        let header = "Name,Path,Size (Bytes)\n"
        let rows = unusedAssets.map { asset in
            let name = escapeCSVField(asset.name)
            let path = escapeCSVField(asset.path)
            let size = "\(asset.size)"
            return "\(name),\(path),\(size)"
        }
        return header + rows.joined(separator: "\n")
    }
    
    private func escapeCSVField(_ field: String) -> String {
        var escaped = field
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            escaped = escaped.replacingOccurrences(of: "\"", with: "")
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
}
