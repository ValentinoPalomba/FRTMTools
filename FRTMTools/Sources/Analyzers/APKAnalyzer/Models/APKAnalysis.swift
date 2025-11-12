//
//  APKAnalysis.swift
//  FRTMTools
//
//

import Foundation
import SwiftUI

/// Represents a complete analysis of an Android APK file
struct APKAnalysis: Identifiable, Codable, Sendable {
    /// Unique identifier for this analysis
    let id: UUID

    /// Original APK file name
    let fileName: String

    /// Package name from AndroidManifest.xml
    let packageName: String?

    /// App display name/label from AndroidManifest.xml
    let appLabel: String?

    /// File system URL of the APK
    let url: URL

    /// Root file hierarchy representing the APK contents
    let rootFile: FileInfo

    /// Version name (e.g., "1.0.0")
    let versionName: String?

    /// Version code (numeric)
    let versionCode: String?

    /// Minimum SDK version
    let minSdkVersion: Int?

    /// Target SDK version
    let targetSdkVersion: Int?

    /// List of permissions requested by the app
    let permissions: [String]?

    /// Installed size breakdown
    let installedSize: InstalledSize?

    /// Dependency information for native libraries
    let dependencyGraph: DependencyGraph?

    /// App icon image data (PNG format)
    private let imageData: Data?

    /// Supported ABIs (Application Binary Interfaces)
    let supportedABIs: [String]?

    /// Total number of DEX files
    let dexFileCount: Int?

    /// Total size of all DEX files in bytes
    let totalDexSize: Int64?

    /// Whether the APK is obfuscated (ProGuard/R8)
    let isObfuscated: Bool

    /// App icon as SwiftUI Image
    var image: Image? {
        guard let data = imageData else { return nil }
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }

    /// Breakdown of installed size by category
    struct InstalledSize: Codable, Sendable {
        /// Total installed size in MB
        let total: Int

        /// DEX files size in MB
        let dex: Int

        /// Native libraries size in MB
        let nativeLibs: Int

        /// Resources size in MB
        let resources: Int

        /// Assets size in MB
        let assets: Int
    }

    init(
        id: UUID = UUID(),
        fileName: String,
        packageName: String?,
        appLabel: String? = nil,
        url: URL,
        rootFile: FileInfo,
        versionName: String?,
        versionCode: String?,
        minSdkVersion: Int?,
        targetSdkVersion: Int?,
        permissions: [String]?,
        installedSize: InstalledSize?,
        dependencyGraph: DependencyGraph?,
        imageData: Data?,
        supportedABIs: [String]?,
        dexFileCount: Int?,
        totalDexSize: Int64?,
        isObfuscated: Bool
    ) {
        self.id = id
        self.fileName = fileName
        self.packageName = packageName
        self.appLabel = appLabel
        self.url = url
        self.rootFile = rootFile
        self.versionName = versionName
        self.versionCode = versionCode
        self.minSdkVersion = minSdkVersion
        self.targetSdkVersion = targetSdkVersion
        self.permissions = permissions
        self.installedSize = installedSize
        self.dependencyGraph = dependencyGraph
        self.imageData = imageData
        self.supportedABIs = supportedABIs
        self.dexFileCount = dexFileCount
        self.totalDexSize = totalDexSize
        self.isObfuscated = isObfuscated
    }

    /// Total uncompressed size of all files
    var totalSize: Int64 {
        calculateSize(of: rootFile)
    }

    private func calculateSize(of fileInfo: FileInfo) -> Int64 {
        var total = fileInfo.size
        if let subItems = fileInfo.subItems {
            for item in subItems {
                total += calculateSize(of: item)
            }
        }
        return total
    }
}
