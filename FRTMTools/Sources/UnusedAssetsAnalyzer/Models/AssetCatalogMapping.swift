//
//  AssetCatalogMapping.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation
// MARK: - Strutture di supporto
struct AssetCatalogMapping {
    let catalogName: String        // Nome della .imageset directory
    let actualFiles: [String]      // File effettivi dentro la directory
    let referenceName: String      // Nome usato nel codice (di solito = catalogName)
}
