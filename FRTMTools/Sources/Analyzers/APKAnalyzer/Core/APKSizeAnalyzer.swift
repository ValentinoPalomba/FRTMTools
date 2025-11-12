//
//  APKSizeAnalyzer.swift
//  FRTMTools
//
//

import Foundation

/// Analyzes installed size of APK files
class APKSizeAnalyzer {

    /// Analyzes the installed size breakdown of an APK
    /// - Parameter analysis: The APK analysis with file hierarchy
    /// - Returns: InstalledSize breakdown or nil if analysis fails
    static func analyze(_ analysis: APKAnalysis) async -> APKAnalysis.InstalledSize? {
        var dexSize: Int64 = 0
        var nativeLibsSize: Int64 = 0
        var resourcesSize: Int64 = 0
        var assetsSize: Int64 = 0

        // Walk the file hierarchy and categorize sizes
        calculateSizes(for: analysis.rootFile, dex: &dexSize, nativeLibs: &nativeLibsSize, resources: &resourcesSize, assets: &assetsSize)

        let totalBytes = dexSize + nativeLibsSize + resourcesSize + assetsSize

        // Convert to MB
        let totalMB = Int(totalBytes / (1024 * 1024))
        let dexMB = Int(dexSize / (1024 * 1024))
        let nativeLibsMB = Int(nativeLibsSize / (1024 * 1024))
        let resourcesMB = Int(resourcesSize / (1024 * 1024))
        let assetsMB = Int(assetsSize / (1024 * 1024))

        return APKAnalysis.InstalledSize(
            total: totalMB,
            dex: dexMB,
            nativeLibs: nativeLibsMB,
            resources: resourcesMB,
            assets: assetsMB
        )
    }

    /// Recursively calculates sizes by category
    private static func calculateSizes(for file: FileInfo, dex: inout Int64, nativeLibs: inout Int64, resources: inout Int64, assets: inout Int64) {
        let path = file.fullPath ?? ""
        let name = file.name.lowercased()

        // Categorize by file type and path
        if file.type == .dex || name.hasSuffix(".dex") {
            dex += file.size
        } else if file.type == .so || name.hasSuffix(".so") || path.contains("/lib/") {
            nativeLibs += file.size
        } else if path.contains("/res/") || file.type == .xml || file.type == .arsc {
            resources += file.size
        } else if path.contains("/assets/") {
            assets += file.size
        }

        // Recursively process subdirectories
        if let subItems = file.subItems {
            for subItem in subItems {
                calculateSizes(for: subItem, dex: &dex, nativeLibs: &nativeLibs, resources: &resources, assets: &assets)
            }
        }
    }
}
