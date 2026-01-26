//
//  BinaryComposition.swift
//  FRTMTools
//
//  Created by Claude Code
//

import Foundation

// MARK: - Binary Composition Models

/// Overall result of binary composition analysis
struct BinaryComposition: Codable, Sendable {
    let binaryURL: URL
    let binaryName: String
    let totalSize: Int64
    let segments: [SegmentInfo]
    let isEncrypted: Bool
    let isStripped: Bool
    let analysisWarnings: [String]

    // SPM packages (dynamically linked)
    let spmPackages: [SPMPackageInfo]
    let systemFrameworks: [String]

    // Statically linked modules (detected from symbols)
    let staticModules: [StaticModuleInfo]

    var textSegmentSize: Int64 {
        segments.first { $0.name == "__TEXT" }?.size ?? 0
    }

    var dataSegmentSize: Int64 {
        segments.filter { $0.name == "__DATA" || $0.name == "__DATA_CONST" }
            .reduce(0) { $0 + $1.size }
    }

    var linkeditSegmentSize: Int64 {
        segments.first { $0.name == "__LINKEDIT" }?.size ?? 0
    }

    var spmPackageCount: Int {
        spmPackages.count
    }

    var staticModuleCount: Int {
        staticModules.count
    }

    init(
        binaryURL: URL,
        binaryName: String,
        totalSize: Int64,
        segments: [SegmentInfo],
        isEncrypted: Bool = false,
        isStripped: Bool = false,
        analysisWarnings: [String] = [],
        spmPackages: [SPMPackageInfo] = [],
        systemFrameworks: [String] = [],
        staticModules: [StaticModuleInfo] = []
    ) {
        self.binaryURL = binaryURL
        self.binaryName = binaryName
        self.totalSize = totalSize
        self.segments = segments
        self.isEncrypted = isEncrypted
        self.isStripped = isStripped
        self.analysisWarnings = analysisWarnings
        self.spmPackages = spmPackages
        self.systemFrameworks = systemFrameworks
        self.staticModules = staticModules
    }
}

/// Information about a Mach-O segment
struct SegmentInfo: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let size: Int64
    let vmAddress: UInt64
    let fileOffset: UInt64

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// Information about an SPM package detected from linked libraries
struct SPMPackageInfo: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let fullName: String
    let size: Int64

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// Information about a statically linked module detected from symbols
struct StaticModuleInfo: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let symbolCount: Int
    let estimatedSize: Int64

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file)
    }

    /// Known system/runtime modules to filter out
    static let systemModules: Set<String> = [
        "Swift", "Foundation", "UIKit", "SwiftUI", "Combine",
        "CoreFoundation", "CoreGraphics", "QuartzCore", "ObjectiveC",
        "Dispatch", "Darwin", "os", "simd"
    ]

    var isSystemModule: Bool {
        Self.systemModules.contains(name)
    }
}
