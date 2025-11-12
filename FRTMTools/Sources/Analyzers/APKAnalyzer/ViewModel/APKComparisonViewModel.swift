//
//  ComparisonViewModel.swift
//  FRTMTools
//
//

import Foundation

/// View model for comparing two APK analyses
@MainActor
class APKComparisonViewModel: ObservableObject {
    let oldAnalysis: APKAnalysis
    let newAnalysis: APKAnalysis

    init(oldAnalysis: APKAnalysis, newAnalysis: APKAnalysis) {
        self.oldAnalysis = oldAnalysis
        self.newAnalysis = newAnalysis
    }

    /// File differences between analyses
    var fileDiffs: [FileDiff] {
        var diffs: [FileDiff] = []
        var oldFiles: [String: FileInfo] = [:]
        var newFiles: [String: FileInfo] = [:]

        // Build lookup dictionaries
        buildFileMap(oldAnalysis.rootFile, prefix: "", into: &oldFiles)
        buildFileMap(newAnalysis.rootFile, prefix: "", into: &newFiles)

        // Find all unique paths
        let allPaths = Set(oldFiles.keys).union(Set(newFiles.keys))

        for path in allPaths {
            let oldFile = oldFiles[path]
            let newFile = newFiles[path]
            let oldSize = oldFile?.size ?? 0
            let newSize = newFile?.size ?? 0

            // Only add if sizes are different
            if oldSize != newSize {
                diffs.append(FileDiff(
                    name: path,
                    size1: oldSize,
                    size2: newSize
                ))
            }
        }

        return diffs.sorted { abs($0.size2 - $0.size1) > abs($1.size2 - $1.size1) }
    }

    /// Builds a flat map of file paths to FileInfo objects
    private func buildFileMap(_ file: FileInfo, prefix: String, into map: inout [String: FileInfo]) {
        let path = prefix.isEmpty ? file.name : "\(prefix)/\(file.name)"
        map[path] = file

        if let subItems = file.subItems {
            for subItem in subItems {
                buildFileMap(subItem, prefix: path, into: &map)
            }
        }
    }

    /// Total size change
    var totalSizeChange: Int64 {
        newAnalysis.totalSize - oldAnalysis.totalSize
    }

    /// Percentage change in total size
    var totalSizePercentageChange: Double {
        guard oldAnalysis.totalSize > 0 else { return 0 }
        return (Double(totalSizeChange) / Double(oldAnalysis.totalSize)) * 100
    }

    /// Installed size change
    var installedSizeChange: Int? {
        guard let oldInstalled = oldAnalysis.installedSize?.total,
              let newInstalled = newAnalysis.installedSize?.total else {
            return nil
        }

        return newInstalled - oldInstalled
    }

    /// DEX size change
    var dexSizeChange: Int64? {
        guard let oldDex = oldAnalysis.totalDexSize,
              let newDex = newAnalysis.totalDexSize else {
            return nil
        }

        return newDex - oldDex
    }

    /// ABI changes
    var abiChanges: (added: [String], removed: [String]) {
        let oldABIs = Set(oldAnalysis.supportedABIs ?? [])
        let newABIs = Set(newAnalysis.supportedABIs ?? [])

        let added = Array(newABIs.subtracting(oldABIs)).sorted()
        let removed = Array(oldABIs.subtracting(newABIs)).sorted()

        return (added, removed)
    }

    /// Permission changes
    var permissionChanges: (added: [String], removed: [String]) {
        let oldPermissions = Set(oldAnalysis.permissions ?? [])
        let newPermissions = Set(newAnalysis.permissions ?? [])

        let added = Array(newPermissions.subtracting(oldPermissions)).sorted()
        let removed = Array(oldPermissions.subtracting(newPermissions)).sorted()

        return (added, removed)
    }
}
