//
//  APKCategoryGenerator.swift
//  FRTMTools
//
//

import Foundation
import SwiftUI

/// Generates file categories for APK analysis
class APKCategoryGenerator {

    /// Generates categorized file groups from APK analysis
    /// - Parameter analysis: The APK analysis to categorize
    /// - Returns: Array of category results with files grouped by type
    static func generateCategories(from analysis: APKAnalysis) -> [CategoryResult] {
        var categoryItems: [CategoryType: [FileInfo]] = [:]

        // Categorize files
        categorizeFile(analysis.rootFile, into: &categoryItems)

        // Convert to CategoryResult array
        let results = categoryItems.compactMap { (type, items) -> CategoryResult? in
            guard !items.isEmpty else { return nil }

            let totalSize = items.reduce(0) { $0 + calculateTotalSize($1) }

            return CategoryResult(
                type: type,
                totalSize: totalSize,
                items: items
            )
        }
        .sorted { $0.totalSize > $1.totalSize }

        return results
    }

    /// Recursively categorizes files
    private static func categorizeFile(_ file: FileInfo, into categories: inout [CategoryType: [FileInfo]]) {
        let path = file.fullPath ?? ""
        let name = file.name.lowercased()

        // Always recurse into directories first
        if file.type == .directory {
            if let subItems = file.subItems {
                for subItem in subItems {
                    categorizeFile(subItem, into: &categories)
                }
            }
            return // Don't add directories to categories, only their contents
        }

        // Check file type and location for non-directory files
        if file.type == .dex || name.hasSuffix(".dex") {
            categories[.dex, default: []].append(file)
        } else if file.type == .so || name.hasSuffix(".so") {
            categories[.nativeLibraries, default: []].append(file)
        } else if file.type == .xml || file.type == .arsc || path.contains("/res/") {
            categories[.resources, default: []].append(file)
        } else if path.contains("/assets/") {
            categories[.assets, default: []].append(file)
        } else if name == "androidmanifest.xml" || path.contains("META-INF") || name.hasSuffix(".sf") || name.hasSuffix(".rsa") || name.hasSuffix(".mf") {
            categories[.manifestMetadata, default: []].append(file)
        } else {
            categories[.other, default: []].append(file)
        }
    }

    /// Calculates total size including subitems
    private static func calculateTotalSize(_ file: FileInfo) -> Int64 {
        var total = file.size

        if let subItems = file.subItems {
            for subItem in subItems {
                total += calculateTotalSize(subItem)
            }
        }

        return total
    }
}
