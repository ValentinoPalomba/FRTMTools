//
//  AssetInfo.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//


import Foundation
import AppKit
import FengNiaoKit

final class UnusedAssetsAnalyzer: Analyzer {
    
    // MARK: - Proprietà
    private var configuration: DetectorConfiguration
    
    // MARK: - Inizializzazione
    init(configuration: DetectorConfiguration = DetectorConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - Metodi pubblici
    func analyze(at url: URL) async throws -> UnusedAssetResult? {
        let startTime = Date()
        
        configuration.sourcePaths.removeAll()
        if !configuration.sourcePaths.contains(url.path) {
            configuration.sourcePaths.append(url.path)
        }
        
        let fengNiao = FengNiao(
            projectPath: configuration.sourcePaths.first!,
            excludedPaths: [],
            resourceExtensions: AssetType.allCases.map({ $0.rawValue }),
            searchInFileExtensions: ["h", "m", "mm", "swift", "xib", "storyboard", "plist"]
        )
        
        let unusedAssets = try fengNiao.unusedFiles()
        let duration = Date().timeIntervalSince(startTime)
        
        
        let assetInfos = unusedAssets.map(mapToAssetInfo)

        let totalUnusedSize = assetInfos.reduce(0) { $0 + $1.size }
        let totalAssetsScanned = assetInfos.count

        let unusedAssetResult = UnusedAssetResult(
            projectPath: url.path,
            projectName: url.lastPathComponent,
            unusedAssets: assetInfos,
            totalUnusedSize: totalUnusedSize,
            totalAssetsScanned: totalAssetsScanned,
            scanDuration: duration
        )
        
        
        return unusedAssetResult
    }
    
   

    private func mapToAssetInfo(_ fileInfo: FengNiaoKit.FileInfo) -> AssetInfo {
        let ext = fileInfo.path.extension ?? "" // FengNiaoKit ti dà già l’estensione
        let type = AssetType(rawValue: ext.lowercased()) ?? .png
        
        return AssetInfo(
            name: fileInfo.fileName,
            path: fileInfo.path.string,
            size: Int64(fileInfo.size),
            type: type
        )
    }

    


    func fileExtension(from path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        return ext.isEmpty ? nil : ext
    }

    
}


