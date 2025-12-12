import Foundation

struct ThirdPartyLibraryInsight: Identifiable, Codable {
    let id: UUID
    let name: String
    let identifier: String
    let version: String?
    let estimatedSize: Int64
    let packageMatches: [String]
    let hasManifestComponent: Bool
}

enum ThirdPartyLibraryDetector {
    private struct VersionEntry {
        let key: String
        let group: String
        let artifact: String
        let version: String
        let packagePrefix: String
    }
    
    private struct FallbackSignature {
        let key: String
        let displayName: String
        let packagePrefixes: [String]
        let manifestPrefixes: [String]
        let nativeLibHints: [String]
    }
    
    private static let allowedVendors: [String] = [
        "com.google",
        "com.facebook",
        "com.adjust",
        "com.appsflyer",
        "com.onesignal",
        "com.mixpanel",
        "com.amplitude",
        "com.segment",
        "io.branch",
        "io.sentry",
        "com.airbnb",
        "com.squareup",
        "com.tencent",
        "com.yandex",
        "com.bytedance",
        "com.inmobi",
        "com.ironsource",
        "com.applovin",
        "com.chartboost",
        "com.vungle",
        "com.unity3d",
        "androidx"
    ]
    
    private static let overrides: [String: (displayName: String, extraPackages: [String])] = [
        "com.google.firebase:firebase-analytics": ("Firebase Analytics", ["com.google.android.gms.measurement"]),
        "com.google.firebase:firebase-crashlytics": ("Firebase Crashlytics", ["com.google.firebase.crashlytics"]),
        "com.google.firebase:firebase-messaging": ("Firebase Cloud Messaging", ["com.google.firebase.messaging"]),
        "com.google.android.gms:play-services-ads": ("Google Ads", ["com.google.android.gms.ads"]),
        "com.google.android.gms:play-services-maps": ("Google Maps", ["com.google.android.gms.maps"]),
        "com.google.android.gms:play-services-location": ("Google Location Services", ["com.google.android.gms.location"]),
        "com.facebook.android:facebook-android-sdk": ("Facebook SDK", ["com.facebook"]),
        "com.airbnb.android:lottie": ("Lottie", ["com.airbnb.lottie"])
    ]
    
    private static let fallbackSignatures: [FallbackSignature] = [
        FallbackSignature(
            key: "com.appsflyer:af-android-sdk",
            displayName: "AppsFlyer",
            packagePrefixes: ["com.appsflyer"],
            manifestPrefixes: ["com.appsflyer"],
            nativeLibHints: ["appsflyer"]
        ),
        FallbackSignature(
            key: "com.adjust.sdk:adjust-android",
            displayName: "Adjust",
            packagePrefixes: ["com.adjust"],
            manifestPrefixes: ["com.adjust"],
            nativeLibHints: ["adjust"]
        ),
        FallbackSignature(
            key: "com.onesignal:one-signal",
            displayName: "OneSignal",
            packagePrefixes: ["com.onesignal"],
            manifestPrefixes: ["com.onesignal"],
            nativeLibHints: ["onesignal"]
        ),
        FallbackSignature(
            key: "com.mixpanel:mixpanel",
            displayName: "Mixpanel",
            packagePrefixes: ["com.mixpanel"],
            manifestPrefixes: ["com.mixpanel"],
            nativeLibHints: []
        ),
        FallbackSignature(
            key: "io.branch.sdk:branch",
            displayName: "Branch.io",
            packagePrefixes: ["io.branch"],
            manifestPrefixes: ["io.branch"],
            nativeLibHints: []
        ),
        FallbackSignature(
            key: "io.sentry:sentry-android",
            displayName: "Sentry",
            packagePrefixes: ["io.sentry"],
            manifestPrefixes: ["io.sentry"],
            nativeLibHints: []
        )
    ]
    
    static func detect(in rootFile: FileInfo, manifestInfo: AndroidManifestInfo?, classNameSanitizer: ClassNameSanitizer?) -> [ThirdPartyLibraryInsight] {
        let files = rootFile.flattened(includeDirectories: false)
        let dexFiles = files.filter { $0.name.lowercased().hasSuffix(".dex") }
        let nativeLibs = files.filter { $0.name.lowercased().hasSuffix(".so") }
        
        let versionEntries = collectVersionEntries(from: files)
        let packageStats = buildPackageStats(from: dexFiles, classNameSanitizer: classNameSanitizer)
        let manifestComponents = manifestInfo?.components ?? []
        
        var insights: [ThirdPartyLibraryInsight] = []
        var usedKeys: Set<String> = []
        
        for entry in versionEntries {
            guard allowedVendors.contains(where: { entry.group.hasPrefix($0) }) else { continue }
            let extra = overrides[entry.key]?.extraPackages ?? []
            let packagePrefixes = [entry.packagePrefix] + extra
            let packageMatches = matchedPackages(prefixes: packagePrefixes, packageCounts: packageStats.packageCounts)
            let classCount = packageMatches.reduce(0) { $0 + (packageStats.packageCounts[$1] ?? 0) }
            let manifestMatch = manifestComponents.contains { component in
                packagePrefixes.contains(where: { component.name.hasPrefix($0) })
            }
            let nativeSize = nativeSize(for: entry, hints: [], nativeLibs: nativeLibs)
            let estimatedSize = sizeEstimate(classCount: classCount, stats: packageStats) + nativeSize
            guard classCount > 0 || nativeSize > 0 || manifestMatch else { continue }
            
            let displayName = overrides[entry.key]?.displayName ?? defaultDisplayName(group: entry.group, artifact: entry.artifact)
            insights.append(ThirdPartyLibraryInsight(
                id: UUID(),
                name: displayName,
                identifier: entry.key,
                version: entry.version,
                estimatedSize: estimatedSize,
                packageMatches: packageMatches,
                hasManifestComponent: manifestMatch
            ))
            usedKeys.insert(entry.key)
        }
        
        // Fallback signatures for SDKs without .version markers
        for signature in fallbackSignatures where !usedKeys.contains(signature.key) {
            let packageMatches = matchedPackages(prefixes: signature.packagePrefixes, packageCounts: packageStats.packageCounts)
            let classCount = packageMatches.reduce(0) { $0 + (packageStats.packageCounts[$1] ?? 0) }
            let manifestMatch = manifestComponents.contains { component in
                signature.manifestPrefixes.contains(where: { component.name.hasPrefix($0) })
            }
            let nativeSize = sizeFromNativeHints(signature.nativeLibHints, nativeLibs: nativeLibs)
            let estimatedSize = sizeEstimate(classCount: classCount, stats: packageStats) + nativeSize
            guard classCount > 0 || nativeSize > 0 || manifestMatch else { continue }
            
            insights.append(ThirdPartyLibraryInsight(
                id: UUID(),
                name: signature.displayName,
                identifier: signature.key,
                version: nil,
                estimatedSize: estimatedSize,
                packageMatches: packageMatches,
                hasManifestComponent: manifestMatch
            ))
        }
        
        return insights
            .sorted { lhs, rhs in
                if lhs.estimatedSize == rhs.estimatedSize {
                    return lhs.name < rhs.name
                }
                return lhs.estimatedSize > rhs.estimatedSize
            }
    }
    
    private static func collectVersionEntries(from files: [FileInfo]) -> [VersionEntry] {
        var entries: [VersionEntry] = []
        for file in files {
            guard let path = file.path?.lowercased(),
                  path.contains("meta-inf"),
                  file.name.lowercased().hasSuffix(".version"),
                  let fullPath = file.fullPath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                  let versionString = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !versionString.isEmpty else { continue }

            let baseName = String(file.name.dropLast(".version".count))
            guard let separatorIndex = baseName.firstIndex(of: "_") else { continue }
            let group = baseName[..<separatorIndex].replacingOccurrences(of: "-", with: ".")
            let artifact = baseName[baseName.index(after: separatorIndex)...]
            let key = "\(group):\(artifact)"
            let packagePrefix = group.replacingOccurrences(of: "_", with: ".")
            entries.append(VersionEntry(
                key: key,
                group: group,
                artifact: String(artifact),
                version: versionString,
                packagePrefix: packagePrefix
            ))
        }
        return deduplicateVersionEntries(entries)
    }
    
    private static func deduplicateVersionEntries(_ entries: [VersionEntry]) -> [VersionEntry] {
        var seen: [String: VersionEntry] = [:]
        for entry in entries {
            if seen[entry.key] == nil {
                seen[entry.key] = entry
            }
        }
        return Array(seen.values)
    }
    
    private static func buildPackageStats(from dexFiles: [FileInfo], classNameSanitizer: ClassNameSanitizer?) -> (packageCounts: [String: Int], totalClasses: Int, totalDexSize: Int64) {
        var counts: [String: Int] = [:]
        var totalClasses = 0
        var totalDexSize: Int64 = 0
        
        for dex in dexFiles {
            totalDexSize += dex.size
            guard let path = dex.fullPath else { continue }
            let fileURL = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let descriptors = DexFileInspector.classDescriptors(from: data, fileURL: fileURL)
            for descriptor in descriptors {
                let sanitized = classNameSanitizer?.sanitize(descriptor) ?? descriptor
                let packageName = package(from: sanitized)
                counts[packageName, default: 0] += 1
                totalClasses += 1
            }
        }
        
        return (counts, totalClasses, totalDexSize)
    }
    
    private static func package(from descriptor: String) -> String {
        guard let lastDot = descriptor.lastIndex(of: ".") else { return descriptor }
        return String(descriptor[..<lastDot])
    }
    
    private static func matchedPackages(prefixes: [String], packageCounts: [String: Int]) -> [String] {
        var matches: Set<String> = []
        for (pkg, _) in packageCounts {
            if prefixes.contains(where: { pkg.hasPrefix($0) }) {
                matches.insert(pkg)
            }
        }
        return Array(matches)
    }
    
    private static func sizeEstimate(classCount: Int, stats: (packageCounts: [String: Int], totalClasses: Int, totalDexSize: Int64)) -> Int64 {
        guard stats.totalClasses > 0, stats.totalDexSize > 0, classCount > 0 else { return 0 }
        let ratio = Double(classCount) / Double(stats.totalClasses)
        return Int64(ratio * Double(stats.totalDexSize))
    }
    
    private static func nativeSize(for entry: VersionEntry, hints: [String], nativeLibs: [FileInfo]) -> Int64 {
        var libHints = hints
        let artifactHint = entry.artifact
        if !artifactHint.isEmpty {
            libHints.append(artifactHint)
        }
        return sizeFromNativeHints(libHints, nativeLibs: nativeLibs)
    }
    
    private static func sizeFromNativeHints(_ hints: [String], nativeLibs: [FileInfo]) -> Int64 {
        guard !hints.isEmpty else { return 0 }
        return nativeLibs.reduce(0) { total, file in
            if hints.contains(where: { file.name.lowercased().contains($0.lowercased()) }) {
                return total + file.size
            }
            return total
        }
    }
    
    private static func defaultDisplayName(group: String, artifact: String) -> String {
        if group.hasPrefix("androidx.") {
            let name = artifact
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
            return "AndroidX \(name)"
        }
        let artifactDisplay = artifact
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
        return "\(group) \(artifactDisplay)"
    }
}
