//
//  UnusedAssetWrapper.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 10/09/25.
//

import FengNiaoKit

final class UnusedAssetWrapper {
    
    let fengNiao: FengNiao
    
    init(fengNiao: FengNiao) {
        self.fengNiao = fengNiao
    }
    
    
    func findUnusedAssets() throws -> [FengNiaoKit.FileInfo] {
        try fengNiao.unusedFiles()
    }
    
    
    static func deleteUnusedAssets(assetInfo: [AssetInfo]) throws -> [AssetInfo]  {
        let results = FengNiao.delete(assetInfo.map({ FengNiaoKit.FileInfo(path: $0.path)}))
        let deletedFiles = results.deleted.map(mapToAssetInfo(_:))
        let failedFiles = results.failed.map({ (info, error) in
            (mapToAssetInfo(info))
        }
        )
        
        return deletedFiles.filter(failedFiles.contains(_:))
    }
    
    private static func mapToAssetInfo(_ fileInfo: FengNiaoKit.FileInfo) -> AssetInfo {
        let ext = fileInfo.path.extension ?? ""
        let type = AssetType(rawValue: ext.lowercased()) ?? .png
        
        return AssetInfo(
            name: fileInfo.fileName,
            path: fileInfo.path.string,
            size: Int64(fileInfo.size),
            type: type
        )
    }
    
    
}
