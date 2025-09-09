//
//  AssetInfo.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation
// MARK: - Modelli di dati
struct AssetInfo: Codable, Hashable, Identifiable {
    let name: String
    let path: String
    let size: Int64
    let type: AssetType
    public var id: String { path }
}