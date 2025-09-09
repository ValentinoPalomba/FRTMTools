//
//  AssetInfo.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//


import Foundation
import AppKit

final class UnusedAssetsAnalyzer: Analyzer {
    
    // MARK: - Proprietà
    private var configuration: DetectorConfiguration
    private let fileManager = FileManager.default
    private var isScanning = false
    
    private var fileContentsCache: [String: String] = [:]
    private var assetReferencesCache: Set<String> = []
    
    // MARK: - Inizializzazione
    init(configuration: DetectorConfiguration = DetectorConfiguration()) {
        self.configuration = configuration
    }
    
    // MARK: - Metodi pubblici
    func analyze(at url: URL) async throws -> UnusedAssetResult? {
        if !configuration.sourcePaths.contains(url.path) {
            configuration.sourcePaths.append(url.path)
        }
        
        return try await Task(priority: .background) {
            return try scanForUnusedAssetsSync(projectURL: url)
        }.value
    }
    
    
    /// Scansione sincrona (per testing o uso specifico)
    func scanForUnusedAssetsSync(projectURL: URL) throws -> UnusedAssetResult {
        let startTime = Date()
        
        // 1. Trova tutte le risorse grafiche
        let allAssets = try findAllAssets()
        
        // 2. Trova tutti i riferimenti nel codice
        let referencedAssets = try findAllAssetReferences()
        
        // 3. Identifica risorse non utilizzate
        let unusedAssets = identifyUnusedAssets(allAssets: allAssets, referencedAssets: referencedAssets)
        
        let duration = Date().timeIntervalSince(startTime)
        
        return UnusedAssetResult(
            projectPath: projectURL.path,
            projectName: projectURL.lastPathComponent,
            unusedAssets: unusedAssets,
            totalUnusedSize: unusedAssets.reduce(0) { $0 + $1.size },
            totalAssetsScanned: allAssets.count,
            scanDuration: duration
        )
    }
    
    /// Aggiorna la configurazione
    func updateConfiguration(_ newConfiguration: DetectorConfiguration) {
        configuration = newConfiguration
        clearCache()
    }
    
    /// Pulisce la cache
    func clearCache() {
        configuration.sourcePaths.removeAll()
        fileContentsCache.removeAll()
        assetReferencesCache.removeAll()
    }
        
    
    private func findAllAssets() throws -> [AssetInfo] {
        var allAssets: [AssetInfo] = []
        
        // Cerca nel bundle principale
        if let bundlePath = Bundle.main.resourcePath {
            allAssets.append(contentsOf: try findAssetsInDirectory(bundlePath))
        }
        
        // Cerca in percorsi aggiuntivi se specificati
        for sourcePath in configuration.sourcePaths {
            guard fileManager.fileExists(atPath: sourcePath) else {
                throw UnusedAssetsError.sourcePathNotFound(sourcePath)
            }
            allAssets.append(contentsOf: try findAssetsInDirectory(sourcePath))
        }
        
        return allAssets
    }
    
    private func findAssetsInDirectory(_ directoryPath: String) throws -> [AssetInfo] {
        var assets: [AssetInfo] = []
        let enumerator = fileManager.enumerator(atPath: directoryPath)
        
        while let fileName = enumerator?.nextObject() as? String {
            let fullPath = (directoryPath as NSString).appendingPathComponent(fileName)
            
            // Salta percorsi esclusi
            if shouldExcludePath(fullPath) {
                continue
            }
            
            // Verifica se è un asset supportato
            if let assetInfo = createAssetInfo(fileName: fileName, fullPath: fullPath) {
                assets.append(assetInfo)
            }
        }
        
        return assets
    }
    
    private func createAssetInfo(fileName: String, fullPath: String) -> AssetInfo? {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        
        // Verifica se l'estensione è supportata
        guard let assetType = configuration.supportedImageTypes.first(where: { 
            $0.extensions.contains(fileExtension) 
        }) else {
            return nil
        }
        
        // Ottieni dimensione file
        let fileSize: Int64
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fullPath)
            fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            fileSize = 0
        }
        
        // Rimuovi estensione e suffissi di risoluzione (@2x, @3x)
        let cleanName = cleanAssetName(fileName)
        
        return AssetInfo(name: cleanName, path: fullPath, size: fileSize, type: assetType)
    }
    
    private func cleanAssetName(_ fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        
        // Rimuovi suffissi di risoluzione
        name = name.replacingOccurrences(of: "@2x", with: "")
        name = name.replacingOccurrences(of: "@3x", with: "")
        
        return name
    }
    
    private func shouldExcludePath(_ path: String) -> Bool {
        // Controlla percorsi esclusi
        for excludedPath in configuration.excludedPaths {
            if path.contains(excludedPath) {
                return true
            }
        }
        
        // Controlla estensioni escluse
        let fileExtension = (path as NSString).pathExtension
        if configuration.excludedFileExtensions.contains(fileExtension) {
            return true
        }
        
        // Escludi icone app se richiesto
        if !configuration.includeAppIconVariants && path.contains("AppIcon") {
            return true
        }
        
        // Escludi launch images se richiesto
        if !configuration.includeLaunchImages && (path.contains("LaunchImage") || path.contains("LaunchScreen")) {
            return true
        }
        
        return false
    }
    
    private func findAllAssetReferences() throws -> Set<String> {
        var referencedAssets: Set<String> = []
        
        // Cerca nel bundle principale
        if let bundlePath = Bundle.main.resourcePath {
            referencedAssets.formUnion(try findReferencesInDirectory(bundlePath))
        }
        
        // Cerca in percorsi sorgente aggiuntivi
        for sourcePath in configuration.sourcePaths {
            guard fileManager.fileExists(atPath: sourcePath) else { continue }
            referencedAssets.formUnion(try findReferencesInDirectory(sourcePath))
        }
        
        return referencedAssets
    }
    
    private func findReferencesInDirectory(_ directoryPath: String) throws -> Set<String> {
        var references: Set<String> = []
        let enumerator = fileManager.enumerator(atPath: directoryPath)
        
        while let fileName = enumerator?.nextObject() as? String {
            let fullPath = (directoryPath as NSString).appendingPathComponent(fileName)
            
            // Cerca solo in file sorgente
            let fileExtension = (fileName as NSString).pathExtension.lowercased()
            guard ["swift", "m", "mm", "h", "storyboard", "xib", "json"].contains(fileExtension) else {
                continue
            }
            
            do {
                let content = try getFileContent(fullPath)
                references.formUnion(findAssetReferencesInContent(content))
            } catch {
                // Continua con il prossimo file se non riesce a leggere questo
                continue
            }
        }
        
        return references
    }
    
    private func getFileContent(_ filePath: String) throws -> String {
        // Usa cache se disponibile
        if let cachedContent = fileContentsCache[filePath] {
            return cachedContent
        }
        
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        fileContentsCache[filePath] = content
        return content
    }
    
    private func findAssetReferencesInContent(_ content: String) -> Set<String> {
        var references: Set<String> = []
        
        // Usa pattern di default + pattern personalizzati
        let allPatterns = DetectorConfiguration.defaultSearchPatterns + configuration.customPatterns
        
        for pattern in allPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: configuration.caseSensitive ? [] : .caseInsensitive)
                let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
                
                for match in matches {
                    if match.numberOfRanges > 1 {
                        let range = match.range(at: 1)
                        if let swiftRange = Range(range, in: content) {
                            let assetName = String(content[swiftRange])
                            references.insert(assetName)
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        return references
    }
    
    private func identifyUnusedAssets(allAssets: [AssetInfo], referencedAssets: Set<String>) -> [AssetInfo] {
        return allAssets.filter { asset in
            let isReferenced = referencedAssets.contains { referencedName in
                if configuration.caseSensitive {
                    return asset.name == referencedName
                } else {
                    return asset.name.lowercased() == referencedName.lowercased()
                }
            }
            return !isReferenced
        }
    }
}

// MARK: - Estensioni di utilità
extension UnusedAssetsAnalyzer {
    
    /// Salva la lista delle risorse non utilizzate in un file
    static func saveUnusedAssetsList(_ assets: [AssetInfo], to filePath: String) throws {
        let assetNames = assets.map { "\($0.name).\($0.type.rawValue)" }
        let content = assetNames.joined(separator: "\n")
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
}
