//
//  DexAnalyzer.swift
//  FRTMTools
//
//

import Foundation

/// Analyzes DEX (Dalvik Executable) files
class DexAnalyzer {

    /// Information about a DEX file
    struct DexInfo {
        let fileName: String
        let size: Int64
        let classCount: Int?
        let methodCount: Int?
    }

    /// Analyzes all DEX files in an APK
    /// - Parameter rootFile: Root file hierarchy from APK analysis
    /// - Returns: Array of DexInfo objects
    static func analyzeDexFiles(in rootFile: FileInfo) -> [DexInfo] {
        var dexFiles: [DexInfo] = []

        findDexFiles(in: rootFile, dexFiles: &dexFiles)

        return dexFiles.sorted { $0.fileName < $1.fileName }
    }

    /// Recursively finds DEX files
    private static func findDexFiles(in file: FileInfo, dexFiles: inout [DexInfo]) {
        if file.type == .dex || file.name.hasSuffix(".dex") {
            let dexInfo = DexInfo(
                fileName: file.name,
                size: file.size,
                classCount: nil,  // Would require parsing DEX format
                methodCount: nil  // Would require parsing DEX format
            )
            dexFiles.append(dexInfo)
        }

        if let subItems = file.subItems {
            for subItem in subItems {
                findDexFiles(in: subItem, dexFiles: &dexFiles)
            }
        }
    }

    /// Checks if DEX files appear to be obfuscated
    /// - Parameter dexFiles: Array of DexInfo objects
    /// - Returns: True if obfuscation is detected
    static func isObfuscated(_ dexFiles: [DexInfo]) -> Bool {
        // This is a simple heuristic - actual obfuscation detection would require
        // parsing the DEX file format and analyzing class/method names
        // For now, we check if there are multiple DEX files (common with obfuscation/minification)
        return dexFiles.count > 1
    }
}
