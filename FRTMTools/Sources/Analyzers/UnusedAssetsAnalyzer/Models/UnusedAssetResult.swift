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
