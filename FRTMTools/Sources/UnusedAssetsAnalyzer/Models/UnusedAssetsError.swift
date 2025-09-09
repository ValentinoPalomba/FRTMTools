//
//  UnusedAssetsError.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//


// MARK: - Errori personalizzati
enum UnusedAssetsError: Error {
    case bundlePathNotFound
    case sourcePathNotFound(String)
    case fileReadError(String)
    case invalidConfiguration
    case invalidAssetCatalog(String)
    
    var errorDescription: String? {
        switch self {
        case .bundlePathNotFound:
            return "Percorso del bundle non trovato"
        case .sourcePathNotFound(let path):
            return "Percorso sorgente non trovato: \(path)"
        case .fileReadError(let file):
            return "Errore lettura file: \(file)"
        case .invalidConfiguration:
            return "Configurazione non valida"
        case .invalidAssetCatalog(let file):
            return "File AssetCatalog non valido: \(file)"
        }
    }
}
