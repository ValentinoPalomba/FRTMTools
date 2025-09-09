//
//  UnusedAssetResult.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation

struct UnusedAssetResult {
    let unusedAssets: [AssetInfo]
    let totalUnusedSize: Int64
    let totalAssetsScanned: Int
    let scanDuration: TimeInterval
}
