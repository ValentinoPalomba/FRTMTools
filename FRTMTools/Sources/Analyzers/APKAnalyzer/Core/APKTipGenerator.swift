//
//  TipGenerator.swift
//  FRTMTools
//
//

import Foundation

/// Generates optimization tips for APK files
class APKTipGenerator {

    /// Generates optimization tips based on APK analysis
    /// - Parameter analysis: The APK analysis
    /// - Returns: Array of optimization tips
    static func generateTips(for analysis: APKAnalysis) -> [Tip] {
        var tips: [Tip] = []

        // Check DEX size
        if let totalDexSize = analysis.totalDexSize, totalDexSize > 50 * 1024 * 1024 {
            tips.append(Tip(
                text: "Large DEX files detected: Your DEX files are larger than 50 MB. Consider enabling ProGuard/R8 code shrinking and obfuscation to reduce code size. Potential savings: Up to 40% reduction in DEX size.",
                category: .size
            ))
        }

        // Check if obfuscated
        if !analysis.isObfuscated {
            tips.append(Tip(
                text: "Code not obfuscated: Your APK doesn't appear to be obfuscated. Enable ProGuard or R8 to protect your code from reverse engineering and reduce APK size. Potential savings: 20-40% size reduction + improved security.",
                category: .security
            ))
        }

        // Check number of ABIs
        if let abiCount = analysis.supportedABIs?.count, abiCount > 2 {
            tips.append(Tip(
                text: "Multiple ABIs included: Your APK supports \(abiCount) different ABIs. Consider using App Bundle (AAB) to deliver ABI-specific APKs and reduce download size. Potential savings: Up to 60% smaller downloads.",
                category: .size
            ))
        }

        // Check minimum SDK version
        if let minSdk = analysis.minSdkVersion, minSdk < 21 {
            tips.append(Tip(
                text: "Low minimum SDK version: Your minimum SDK is \(minSdk). Consider raising it to 21 (Android 5.0) to enable modern features and optimizations. Devices below this version have minimal market share.",
                category: .compatibility
            ))
        }

        // Check total size
        let totalSizeMB = analysis.totalSize / (1024 * 1024)
        if totalSizeMB > 100 {
            tips.append(Tip(
                text: "Large APK size: Your APK is \(totalSizeMB) MB. Large APKs can reduce install conversion rates. Consider App Bundle, resource optimization, and removing unused resources. Potential savings: 30-50% size reduction.",
                category: .size
            ))
        }

        // Check for resources
        let categories = APKCategoryGenerator.generateCategories(from: analysis)
        if let resourceCategory = categories.first(where: { $0.name == "Resources" }) {
            let resourceSizeMB = resourceCategory.totalSize / (1024 * 1024)
            if resourceSizeMB > 30 {
                tips.append(Tip(
                    text: "Large resources: Your resources folder is \(resourceSizeMB) MB. Use WebP for images, remove unused resources with shrinkResources, and ensure proper image density variants. Potential savings: 20-40% resource size reduction.",
                    category: .size
                ))
            }
        }

        // Check for native libraries
        if let nativeLibCategory = categories.first(where: { $0.name == "Native Libraries" }) {
            let nativeLibSizeMB = nativeLibCategory.totalSize / (1024 * 1024)
            if nativeLibSizeMB > 20 {
                tips.append(Tip(
                    text: "Large native libraries: Your native libraries are \(nativeLibSizeMB) MB. Consider using App Bundle to deliver ABI-specific APKs, or use extractNativeLibs=false to reduce installed size. Potential savings: 40-60% smaller downloads with App Bundle.",
                    category: .size
                ))
            }
        }

        // Check permissions
        if let permissions = analysis.permissions {
            let dangerousPermissions = permissions.filter { permission in
                permission.contains("CAMERA") ||
                permission.contains("LOCATION") ||
                permission.contains("CONTACTS") ||
                permission.contains("STORAGE") ||
                permission.contains("MICROPHONE")
            }

            if !dangerousPermissions.isEmpty {
                tips.append(Tip(
                    text: "Review dangerous permissions: Your app requests \(dangerousPermissions.count) dangerous permission(s). Ensure all permissions are necessary and properly justified to users.",
                    category: .security
                ))
            }
        }

        // Check DEX count
        if let dexCount = analysis.dexFileCount, dexCount > 1 {
            tips.append(Tip(
                text: "Multiple DEX files (Multidex): Your app has \(dexCount) DEX files. This can slow down app startup. Consider modularizing your app, removing unused dependencies, and enabling R8 full mode.",
                category: .performance
            ))
        }

        return tips
    }
}
