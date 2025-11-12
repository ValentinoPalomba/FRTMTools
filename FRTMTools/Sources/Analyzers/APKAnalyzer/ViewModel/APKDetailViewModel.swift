//
//  APKDetailViewModel.swift
//  FRTMTools
//
//

import Foundation
import SwiftUI

/// View model for APK detail view
@MainActor
class APKDetailViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedCategory: String?
    @Published var expandedSections: Set<String> = []

    let analysis: APKAnalysis

    init(analysis: APKAnalysis) {
        self.analysis = analysis
    }

    /// Filtered categories based on search and selection
    var filteredCategories: [CategoryResult] {
        let categories = APKCategoryGenerator.generateCategories(from: analysis)

        if let selected = selectedCategory {
            return categories.filter { $0.name == selected }
        }

        if !searchText.isEmpty {
            return categories.map { category in
                let filteredItems = filterFiles(category.items, searchText: searchText)
                let totalSize = filteredItems.reduce(0) { $0 + calculateSize($1) }

                return CategoryResult(
                    type: category.type,
                    totalSize: totalSize,
                    items: filteredItems
                )
            }
            .filter { !$0.items.isEmpty }
        }

        return categories
    }

    /// Filters files by search text
    private func filterFiles(_ files: [FileInfo], searchText: String) -> [FileInfo] {
        files.compactMap { file in
            let matches = file.name.localizedCaseInsensitiveContains(searchText)

            if let subItems = file.subItems {
                let filteredSubItems = filterFiles(subItems, searchText: searchText)

                if matches || !filteredSubItems.isEmpty {
                    var newFile = file
                    newFile.subItems = filteredSubItems.isEmpty ? nil : filteredSubItems
                    return newFile
                }
            } else if matches {
                return file
            }

            return nil
        }
    }

    /// Calculates total size of a file including subitems
    private func calculateSize(_ file: FileInfo) -> Int64 {
        var total = file.size

        if let subItems = file.subItems {
            for subItem in subItems {
                total += calculateSize(subItem)
            }
        }

        return total
    }

    /// ABI information
    var abiInfo: (count: Int, list: [String]) {
        ABIAnalyzer.analyzeABIs(from: analysis)
    }

    /// ABI description
    var abiDescription: String {
        ABIAnalyzer.description(for: abiInfo.list)
    }

    /// Optimization tips
    var tips: [Tip] {
        APKTipGenerator.generateTips(for: analysis)
    }

    /// File count
    var fileCount: Int {
        countFiles(in: analysis.rootFile)
    }

    private func countFiles(in file: FileInfo) -> Int {
        var count = 1

        if let subItems = file.subItems {
            for subItem in subItems {
                count += countFiles(in: subItem)
            }
        }

        return count
    }

    /// Toggles section expansion
    func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }

    /// Checks if section is expanded
    func isExpanded(_ section: String) -> Bool {
        expandedSections.contains(section)
    }
}
