//
//  AssetTypeGroup.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation
struct AssetTypeGroup: Identifiable {
    var id: String { type.rawValue }
    let type: AssetType
    let assets: [AssetInfo]
    let totalSize: Int64
}
