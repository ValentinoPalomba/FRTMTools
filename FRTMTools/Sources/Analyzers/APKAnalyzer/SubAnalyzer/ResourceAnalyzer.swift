//
//  ResourceAnalyzer.swift
//  FRTMTools
//
//

import Foundation

/// Analyzes Android resources
class ResourceAnalyzer {

    /// Information about resource usage
    struct ResourceInfo {
        let totalSize: Int64
        let drawableSize: Int64
        let layoutSize: Int64
        let rawSize: Int64
        let otherSize: Int64
        let resourceCount: Int
    }

    /// Analyzes resources in an APK
    /// - Parameter rootFile: Root file hierarchy from APK analysis
    /// - Returns: ResourceInfo with breakdown
    static func analyzeResources(in rootFile: FileInfo) -> ResourceInfo {
        var totalSize: Int64 = 0
        var drawableSize: Int64 = 0
        var layoutSize: Int64 = 0
        var rawSize: Int64 = 0
        var otherSize: Int64 = 0
        var resourceCount = 0

        findResources(in: rootFile, total: &totalSize, drawable: &drawableSize, layout: &layoutSize, raw: &rawSize, other: &otherSize, count: &resourceCount)

        return ResourceInfo(
            totalSize: totalSize,
            drawableSize: drawableSize,
            layoutSize: layoutSize,
            rawSize: rawSize,
            otherSize: otherSize,
            resourceCount: resourceCount
        )
    }

    /// Recursively finds and categorizes resources
    private static func findResources(in file: FileInfo, total: inout Int64, drawable: inout Int64, layout: inout Int64, raw: inout Int64, other: inout Int64, count: inout Int) {
        let path = file.fullPath ?? ""

        if path.contains("/res/") {
            total += file.size
            count += 1

            if path.contains("/drawable") || path.contains("/mipmap") {
                drawable += file.size
            } else if path.contains("/layout") {
                layout += file.size
            } else if path.contains("/raw") {
                raw += file.size
            } else {
                other += file.size
            }
        }

        if let subItems = file.subItems {
            for subItem in subItems {
                findResources(in: subItem, total: &total, drawable: &drawable, layout: &layout, raw: &raw, other: &other, count: &count)
            }
        }
    }

    /// Finds duplicate resources (same size files)
    /// - Parameter rootFile: Root file hierarchy
    /// - Returns: Array of file groups with duplicate sizes
    static func findDuplicateResources(in rootFile: FileInfo) -> [[FileInfo]] {
        var resourcesBySize: [Int64: [FileInfo]] = [:]

        collectResources(in: rootFile, into: &resourcesBySize)

        // Return only groups with more than one file
        return resourcesBySize.values
            .filter { $0.count > 1 && $0.first?.size ?? 0 > 1024 } // Only duplicates > 1KB
            .sorted { $0.first?.size ?? 0 > $1.first?.size ?? 0 }
    }

    /// Collects resources grouped by size
    private static func collectResources(in file: FileInfo, into dict: inout [Int64: [FileInfo]]) {
        let path = file.fullPath ?? ""

        if path.contains("/res/") && file.type == .file {
            dict[file.size, default: []].append(file)
        }

        if let subItems = file.subItems {
            for subItem in subItems {
                collectResources(in: subItem, into: &dict)
            }
        }
    }
}
