import Foundation
import AppKit

// MARK: - Layout

struct AndroidPackageLayout {
    let rootURL: URL
    let manifestURL: URL?

    var resourcesRoot: URL {
        rootURL
    }
}

// MARK: - Analyzer
extension ByteCountFormatter: @unchecked Sendable {}
final class APKAnalyzer: Analyzer {
    private static let supportedExtensions: Set<String> = ["apk", "aab", "abb"]

    private let archiveExtractor = APKArchiveExtractor()
    private let manifestAnalyzer = APKManifestAnalyzer()
    private let fileScanner = APKFileScanner()
    private let iconExtractor = APKIconExtractor()
    private let abiDetector = APKABIDetector()
    private let signatureAnalyzer = APKSignatureAnalyzer()
    private let imageExtractor = APKImageExtractor()
    private let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let maxImagePreviewFileSize = 512 * 1024 // 512 KB per inline preview
    private struct ManifestArtifacts {
        let inspectorInfo: AndroidManifestInfo?
        let mergedInfo: AndroidManifestInfo?
    }

    private struct FileArtifacts {
        let rootFile: FileInfo
        let enrichedRootFile: FileInfo
        let previewMap: [String: Data]
    }

    func analyze(at url: URL) async throws -> APKAnalysis? {
        let lowercasedExtension = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(lowercasedExtension) else {
            return nil
        }

        guard let extractionResult = archiveExtractor.extractPackage(at: url) else {
            return nil
        }
        defer { archiveExtractor.cleanup(extractionResult) }

        let manifestResult = manifestAnalyzer.inspectManifest(atRoot: extractionResult.analysisRoot)
        let layout = AndroidPackageLayout(rootURL: extractionResult.analysisRoot, manifestURL: manifestResult.manifestURL)
        logManifestLocation(manifestURL: manifestResult.manifestURL, packageRoot: layout.rootURL)
        let fileName = url.lastPathComponent
        let classNameSanitizer = configureClassNameSanitizer(in: layout)
        let manifestArtifacts = makeManifestArtifacts(for: layout, manifestResult: manifestResult, inspectorArchiveURL: extractionResult.inspectorArchiveURL)
        let fileArtifacts = makeFileArtifacts(in: layout)
        let manifestInfo = manifestArtifacts.mergedInfo
        let appLabel = normalizedAppLabel(from: manifestInfo)
        let supportedABIs = abiDetector.supportedABIs(in: layout, manifestInfo: manifestInfo)
        let icon = iconExtractor.icon(in: layout, manifestInfo: manifestInfo)
        let signatureInfo = signatureAnalyzer.analyzeSignature(in: layout)
        let thirdPartyLibraries = ThirdPartyLibraryDetector.detect(
            in: fileArtifacts.enrichedRootFile,
            manifestInfo: manifestInfo,
            classNameSanitizer: classNameSanitizer
        )
        // Package attribution is currently disabled to avoid expensive heuristics
        let packageAttributions: [PackageAttribution] = []

        // TODO: Da investigare - calcolare lo stripping dei binari Android
        let isStripped = false
        // TODO: Da investigare - determinare l'equivalente ATS per APK
        let allowsArbitraryLoads = false

        let bundletoolEstimates = extractionResult.bundletoolEstimates
        let bundletoolInstallSizeBytes = bundletoolEstimates?.installBytes
        let bundletoolDownloadSizeBytes = bundletoolEstimates?.downloadBytes
        logBundletoolEstimates(bundletoolEstimates, fileName: fileName)

        let shouldPrefillInstalledSize = (lowercasedExtension == "aab" || lowercasedExtension == "abb")
        let installedSizeMetrics = makeInstalledSizeMetrics(
            for: fileArtifacts.enrichedRootFile,
            overrideBytes: bundletoolInstallSizeBytes,
            shouldPrefill: shouldPrefillInstalledSize
        )

        logIconAndLaunchDiagnostics(
            for: fileName,
            manifestInfo: manifestInfo,
            iconFound: icon != nil
        )
        logSectionAvailability(
            for: fileName,
            manifestInfo: manifestInfo,
            thirdPartyLibraries: thirdPartyLibraries,
            assetPackCount: extractionResult.assetPacks.count,
            dynamicFeatureCount: extractionResult.dynamicFeatures.count
        )

        return APKAnalysis(
            url: layout.rootURL,
            fileName: fileName,
            executableName: appLabel ?? manifestInfo?.packageName ?? url.deletingPathExtension().lastPathComponent,
            appLabel: appLabel,
            rootFile: fileArtifacts.enrichedRootFile,
            image: icon,
            version: manifestInfo?.versionName,
            buildNumber: manifestInfo?.versionCode,
            packageName: manifestInfo?.packageName,
            minSDK: manifestInfo?.minSDK,
            targetSDK: manifestInfo?.targetSDK,
            permissions: manifestInfo?.permissions ?? [],
            supportedABIs: supportedABIs,
            isStripped: isStripped,
            allowsArbitraryLoads: allowsArbitraryLoads,
            installedSize: installedSizeMetrics,
            bundletoolInstallSizeBytes: bundletoolInstallSizeBytes,
            bundletoolDownloadSizeBytes: bundletoolDownloadSizeBytes,
            signatureInfo: signatureInfo,
            launchableActivity: manifestInfo?.launchableActivity,
            launchableActivityLabel: manifestInfo?.launchableActivityLabel,
            supportedLocales: manifestInfo?.supportedLocales ?? [],
            supportsScreens: manifestInfo?.supportsScreens ?? [],
            densities: manifestInfo?.densities ?? [],
            supportsAnyDensity: manifestInfo?.supportsAnyDensity,
            requiredFeatures: manifestInfo?.requiredFeatures ?? [],
            optionalFeatures: manifestInfo?.optionalFeatures ?? [],
            components: manifestInfo?.components ?? [],
            deepLinks: manifestInfo?.deepLinks ?? [],
            thirdPartyLibraries: thirdPartyLibraries,
            playAssetPacks: extractionResult.assetPacks,
            dynamicFeatures: extractionResult.dynamicFeatures,
            packageAttributions: packageAttributions
        )
    }

    private func logIconAndLaunchDiagnostics(for fileName: String, manifestInfo: AndroidManifestInfo?, iconFound: Bool) {
        let iconPath = manifestInfo?.iconPath ?? "—"
        let iconResource = manifestInfo?.iconResource ?? "—"
        if iconFound {
            print("ℹ️ Icon resolved for \(fileName) (iconPath: \(iconPath), iconResource: \(iconResource))")
        } else {
            print("⚠️ Icon missing for \(fileName). iconPath: \(iconPath), iconResource: \(iconResource)")
        }

        if let launchable = manifestInfo?.launchableActivity {
            let label = manifestInfo?.launchableActivityLabel ?? "—"
            print("ℹ️ Launch activity for \(fileName): \(launchable) [label=\(label)]")
        } else {
            let activityCount = manifestInfo?.components.filter { $0.type == .activity || $0.type == .activityAlias }.count ?? 0
            print("⚠️ Launch activity not detected for \(fileName) (activities discovered: \(activityCount))")
        }
    }

    private func logSectionAvailability(for fileName: String, manifestInfo: AndroidManifestInfo?, thirdPartyLibraries: [ThirdPartyLibraryInsight], assetPackCount: Int, dynamicFeatureCount: Int) {
        let permissionsCount = manifestInfo?.permissions.count ?? 0
        let requiredFeatures = manifestInfo?.requiredFeatures.count ?? 0
        let optionalFeatures = manifestInfo?.optionalFeatures.count ?? 0
        let deepLinks = manifestInfo?.deepLinks.count ?? 0
        let exportedComponents = manifestInfo?.components.filter { $0.exported == true }.count ?? 0
        let locales = manifestInfo?.supportedLocales.count ?? 0
        print("ℹ️ \(fileName) manifest data — permissions: \(permissionsCount), features: \(requiredFeatures) required / \(optionalFeatures) optional, deep links: \(deepLinks), exported components: \(exportedComponents), locales: \(locales), asset packs: \(assetPackCount), dynamic features: \(dynamicFeatureCount), third-party SDKs: \(thirdPartyLibraries.count)")

        if thirdPartyLibraries.isEmpty {
            print("⚠️ No third-party SDKs detected for \(fileName).")
        }
        if permissionsCount == 0 && (manifestInfo?.permissions != nil) {
            print("⚠️ Permissions array parsed but empty for \(fileName).")
        }
    }

    private func mergeManifestInfo(preferred: AndroidManifestInfo?, fallback: AndroidManifestInfo?) -> AndroidManifestInfo? {
        guard preferred != nil || fallback != nil else { return nil }
        var merged = preferred ?? fallback ?? AndroidManifestInfo()

        func updateIfNil(_ keyPath: WritableKeyPath<AndroidManifestInfo, String?>, from source: AndroidManifestInfo?) {
            if merged[keyPath: keyPath] == nil {
                merged[keyPath: keyPath] = source?[keyPath: keyPath]
            }
        }

        func updateBoolIfNil(_ keyPath: WritableKeyPath<AndroidManifestInfo, Bool?>, from source: AndroidManifestInfo?) {
            if merged[keyPath: keyPath] == nil {
                merged[keyPath: keyPath] = source?[keyPath: keyPath]
            }
        }

        func appendUniqueStrings(_ keyPath: WritableKeyPath<AndroidManifestInfo, [String]>, from source: AndroidManifestInfo?) {
            guard let sourceValues = source?[keyPath: keyPath], !sourceValues.isEmpty else { return }
            var existing = merged[keyPath: keyPath]
            var seen = Set(existing)
            for value in sourceValues where !seen.contains(value) {
                existing.append(value)
                seen.insert(value)
            }
            merged[keyPath: keyPath] = existing
        }

        updateIfNil(\.packageName, from: fallback)
        updateIfNil(\.versionName, from: fallback)
        updateIfNil(\.versionCode, from: fallback)
        updateIfNil(\.appLabel, from: fallback)
        updateIfNil(\.minSDK, from: fallback)
        updateIfNil(\.targetSDK, from: fallback)
        updateIfNil(\.iconResource, from: fallback)
        updateIfNil(\.iconPath, from: fallback)
        updateIfNil(\.launchableActivity, from: fallback)
        updateIfNil(\.launchableActivityLabel, from: fallback)
        updateBoolIfNil(\.supportsAnyDensity, from: fallback)

        if let fallbackPermissions = fallback?.permissions {
            merged.permissions = Array(Set(merged.permissions).union(fallbackPermissions)).sorted()
        }
        if let fallbackNativeCodes = fallback?.nativeCodes {
            merged.nativeCodes = Array(Set(merged.nativeCodes).union(fallbackNativeCodes)).sorted()
        }
        appendUniqueStrings(\.supportedLocales, from: fallback)
        appendUniqueStrings(\.supportsScreens, from: fallback)
        appendUniqueStrings(\.densities, from: fallback)
        appendUniqueStrings(\.requiredFeatures, from: fallback)
        appendUniqueStrings(\.optionalFeatures, from: fallback)
        mergeComponents(from: fallback)
        mergeDeepLinks(from: fallback)
        return merged

        func mergeComponents(from source: AndroidManifestInfo?) {
            guard let source else { return }
            let existing = Set(merged.components.map(\.name))
            let additions = source.components.filter { !existing.contains($0.name) }
            if !additions.isEmpty {
                merged.components.append(contentsOf: additions)
            }
        }

        func mergeDeepLinks(from source: AndroidManifestInfo?) {
            guard let source else { return }
            let existingKeys = Set(merged.deepLinks.map(deepLinkKey))
            let additions = source.deepLinks.filter { !existingKeys.contains(deepLinkKey($0)) }
            if !additions.isEmpty {
                merged.deepLinks.append(contentsOf: additions)
            }
        }

        func deepLinkKey(_ link: AndroidDeepLinkInfo) -> String {
            let scheme = link.scheme ?? "-"
            let host = link.host ?? "-"
            let path = link.path ?? "-"
            let mime = link.mimeType ?? "-"
            return "\(link.componentName)|\(scheme)|\(host)|\(path)|\(mime)"
        }
    }

    private func shouldInvokeAAPTInspector(for manifestInfo: AndroidManifestInfo?) -> Bool {
        if needsAAPTMetadata(for: manifestInfo) {
            return true
        }
        return AndroidManifestInspector.isAvailable()
    }

    private func needsAAPTMetadata(for manifestInfo: AndroidManifestInfo?) -> Bool {
        guard let info = manifestInfo else { return true }
        if needsResolvedLabel(info.appLabel) {
            return true
        }
        if info.iconPath != nil {
            return false
        }
        if needsResolvedIconResource(info.iconResource) {
            return true
        }
        return false
    }

    private func needsResolvedLabel(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return true
        }
        return value.hasPrefix("@")
    }

    private func needsResolvedIconResource(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return true
        }
        if value.hasPrefix("@0x") || value.hasPrefix("@0X") {
            return true
        }
        return false
    }

    private func collectImagePreviewData(in layout: AndroidPackageLayout) -> [String: Data] {
        let imageURLs = imageExtractor.findAllImages(in: layout)
        var previews: [String: Data] = [:]

        for url in imageURLs {
            guard let relativePath = relativePath(for: url, rootURL: layout.rootURL) else { continue }
            guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize,
                  fileSize <= Self.maxImagePreviewFileSize else {
                continue
            }
            guard let data = try? Data(contentsOf: url) else { continue }
            previews[relativePath] = data
        }

        return previews
    }

    private func makeFileArtifacts(in layout: AndroidPackageLayout) -> FileArtifacts {
        let rootFile = fileScanner.scanRoot(at: layout.resourcesRoot)
        let previewMap = collectImagePreviewData(in: layout)
        let enriched = previewMap.isEmpty ? rootFile : attachImagePreviews(previewMap, to: rootFile)
        return FileArtifacts(rootFile: rootFile, enrichedRootFile: enriched, previewMap: previewMap)
    }

    private func attachImagePreviews(_ previews: [String: Data], to file: FileInfo) -> FileInfo {
        var updatedFile = file
        if let path = file.path, let data = previews[path] {
            updatedFile.internalImageData = data
        }

        if var children = file.subItems {
            for index in children.indices {
                children[index] = attachImagePreviews(previews, to: children[index])
            }
            updatedFile.subItems = children
        }

        return updatedFile
    }

    private func relativePath(for fileURL: URL, rootURL: URL) -> String? {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return nil }
        var relative = String(filePath.dropFirst(rootPath.count))
        relative = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? nil : relative
    }

    private func makeManifestArtifacts(for layout: AndroidPackageLayout, manifestResult: APKManifestResult, inspectorArchiveURL: URL?) -> ManifestArtifacts {
        let inspectorInfo: AndroidManifestInfo?
        if let inspectorArchiveURL,
           shouldInvokeAAPTInspector(for: manifestResult.info) {
            inspectorInfo = AndroidManifestInspector.inspect(apkURL: inspectorArchiveURL)
        } else {
            inspectorInfo = nil
        }
        let merged = mergeManifestInfo(preferred: inspectorInfo, fallback: manifestResult.info)
        return ManifestArtifacts(inspectorInfo: inspectorInfo, mergedInfo: merged)
    }

    private func configureClassNameSanitizer(in layout: AndroidPackageLayout) -> ClassNameSanitizer? {
        print("🔍 Checking dex mapping assets under \(layout.rootURL.path)")
        guard let mappingURL = locateProguardMapping(in: layout.rootURL) else {
            let note = "No proguard.map file found under \(layout.rootURL.path)"
            print("⚠️ \(note)")
            return nil
        }
        print("ℹ️ proguard.map discovered at \(mappingURL.path)")
        let sanitizer = ClassNameSanitizer(mappingURL: mappingURL)
        guard sanitizer.isActive else {
            print("⚠️ Unable to parse proguard.map at \(mappingURL.path). Continuing without deobfuscation.")
            return nil
        }
        removeConsumedMappingFile(at: mappingURL, within: layout.rootURL)
        print("ℹ️ Dex class sanitization enabled using \(mappingURL.path)")
        return sanitizer
    }

    private func normalizedAppLabel(from manifestInfo: AndroidManifestInfo?) -> String? {
        let value = manifestInfo?.appLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func makeInstalledSizeMetrics(for rootFile: FileInfo, overrideBytes: Int64?, shouldPrefill: Bool) -> InstalledSizeMetrics? {
        if let overrideBytes {
            return APKSizeBreakdownCalculator.calculate(from: rootFile, overridingTotalBytes: overrideBytes)
        }
        if shouldPrefill {
            return APKSizeBreakdownCalculator.calculate(from: rootFile)
        }
        return nil
    }

    private func logBundletoolEstimates(_ estimates: BundletoolSizeEstimates?, fileName: String) {
        guard let estimates else { return }
        if let downloadBytes = estimates.downloadBytes {
            let installLabel = sizeFormatter.string(fromByteCount: estimates.installBytes)
            let downloadLabel = sizeFormatter.string(fromByteCount: downloadBytes)
            print("ℹ️ bundletool size output for \(fileName): install \(installLabel) · download \(downloadLabel)")
            if estimates.installBytes == downloadBytes {
                print("ℹ️ bundletool reported identical install/download sizes for \(fileName).")
            }
        } else {
            let installLabel = sizeFormatter.string(fromByteCount: estimates.installBytes)
            print("⚠️ bundletool download size unavailable for \(fileName). Install estimate \(installLabel) is available.")
        }
    }

    private func removeConsumedMappingFile(at mappingURL: URL, within rootURL: URL) {
        let fm = FileManager.default
        let normalizedRoot = rootURL.standardizedFileURL.path
        let normalizedMapping = mappingURL.standardizedFileURL.path
        guard normalizedMapping.hasPrefix(normalizedRoot) else { return }
        do {
            try fm.removeItem(at: mappingURL)
            print("ℹ️ Removed proguard.map from analysis payload after importing for dex deobfuscation.")
            pruneEmptyMetadataDirectory(startingAt: mappingURL.deletingLastPathComponent(), stopAt: rootURL)
        } catch {
            print("⚠️ Unable to delete proguard.map after deobfuscation setup: \(error)")
        }
    }

    private func pruneEmptyMetadataDirectory(startingAt directory: URL, stopAt rootURL: URL) {
        let fm = FileManager.default
        var current = directory
        let rootPath = rootURL.standardizedFileURL.path
        while current.standardizedFileURL.path.hasPrefix(rootPath) {
            if current.standardizedFileURL.path == rootPath { break }
            guard let contents = try? fm.contentsOfDirectory(atPath: current.path) else { break }
            guard contents.isEmpty else { break }
            do {
                try fm.removeItem(at: current)
            } catch {
                break
            }
            current.deleteLastPathComponent()
        }
    }

    private func logManifestLocation(manifestURL: URL?, packageRoot: URL) {
        guard let manifestURL else {
            print("⚠️ AndroidManifest.xml not found inside \(packageRoot.path)")
            return
        }

        let fullPath = manifestURL.path
        let relative = relativePath(for: manifestURL, rootURL: packageRoot)
        let module = manifestModuleName(for: manifestURL, rootURL: packageRoot)
        var components: [String] = ["full: \(fullPath)"]
        if let relative {
            components.append("relative: \(relative)")
        }
        if let module {
            components.append("module: \(module)")
        }
        print("ℹ️ AndroidManifest.xml located (\(components.joined(separator: ", "))).")
    }

    private func manifestModuleName(for manifestURL: URL, rootURL: URL) -> String? {
        guard let relative = relativePath(for: manifestURL, rootURL: rootURL) else { return nil }
        var pieces = relative.split(separator: "/")
        guard !pieces.isEmpty else { return nil }
        pieces = pieces.dropLast() // remove file name
        if let last = pieces.last,
           ["manifest", "manifests"].contains(last.lowercased()) {
            pieces = pieces.dropLast()
        }
        guard let module = pieces.last else { return nil }
        return String(module)
    }

    private func locateProguardMapping(in rootURL: URL) -> URL? {
        let fm = FileManager.default
        let metadataRoot = rootURL
            .appendingPathComponent("BUNDLE-METADATA", isDirectory: true)
            .appendingPathComponent("com.android.tools.build.obfuscation", isDirectory: true)
        guard fm.fileExists(atPath: metadataRoot.path) else { return nil }

        let direct = metadataRoot.appendingPathComponent("proguard.map")
        if fm.fileExists(atPath: direct.path) {
            return direct
        }

        if let enumerator = fm.enumerator(at: metadataRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.lastPathComponent == "proguard.map" {
                return url
            }
        }

        return nil
    }
}

// MARK: - Android build-tools helpers (aapt integration)

extension APKAnalyzer {
    /// Legacy manifest inspector powered by `aapt dump badging`.
    /// Left here for archival purposes; the current analyzer uses local manifest parsing instead.
    enum AndroidManifestInspector {
        nonisolated(unsafe) private static var cachedAvailability: Bool?

        static func isAvailable() -> Bool {
            if let cachedAvailability {
                return cachedAvailability
            }
            let available = AndroidToolchain.executableURL(for: .aapt) != nil
                || AndroidToolchain.executableURL(for: .aapt2) != nil
            cachedAvailability = available
            return available
        }

        static func inspect(apkURL: URL) -> AndroidManifestInfo? {
            guard apkURL.pathExtension.lowercased() == "apk" else {
                return nil
            }
            guard let command = AndroidToolchain.command(for: .aapt2) ?? AndroidToolchain.command(for: .aapt) else {
                print("⚠️ Unable to locate aapt/aapt2. Install Android SDK build-tools and expose them via ANDROID_HOME/ANDROID_SDK_ROOT or PATH.")
                return nil
            }

            do {
                let output = try run(command: command, arguments: ["dump", "badging", apkURL.path])
                return parseBadging(output: output)
            } catch {
                print("⚠️ aapt dump badging failed for \(apkURL.lastPathComponent): \(error)")
                return nil
            }
        }

        private static func run(command: AndroidToolchain.Command, arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = command.executableURL
            process.arguments = command.argumentPrefix + arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "AndroidManifestInspector", code: Int(process.terminationStatus), userInfo: nil)
            }
            return String(data: data, encoding: .utf8) ?? ""
        }

        private static func parseBadging(output: String) -> AndroidManifestInfo? {
            var info = AndroidManifestInfo()
            var permissions: Set<String> = []
            var nativeCodes: [String] = []
            var iconCandidates: [(density: Int, path: String)] = []
            var requiredFeatures: Set<String> = []
            var optionalFeatures: Set<String> = []

            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                if trimmed.hasPrefix("package:") {
                    info.packageName = value(for: "name", in: trimmed)
                    info.versionCode = value(for: "versionCode", in: trimmed)
                    info.versionName = value(for: "versionName", in: trimmed)
                } else if trimmed.hasPrefix("sdkVersion:") {
                    info.minSDK = valueAfterColon(in: trimmed)
                } else if trimmed.hasPrefix("targetSdkVersion:") {
                    info.targetSDK = valueAfterColon(in: trimmed)
                } else if trimmed.hasPrefix("uses-permission:") {
                    if let permission = value(for: "name", in: trimmed) {
                        permissions.insert(permission)
                    }
                } else if trimmed.hasPrefix("application-label:") {
                    if let label = singleQuotedValue(in: trimmed) {
                        info.appLabel = label
                    }
                } else if trimmed.hasPrefix("application-icon-") {
                    let density = densityValue(from: trimmed)
                    if let path = singleQuotedValue(in: trimmed) {
                        iconCandidates.append((density, path))
                    }
                } else if trimmed.hasPrefix("application:") {
                    if let iconPath = value(for: "icon", in: trimmed) {
                        iconCandidates.append((Int.max, iconPath))
                    }
                    if info.appLabel == nil, let label = value(for: "label", in: trimmed) {
                        info.appLabel = label
                    }
                } else if trimmed.hasPrefix("native-code:") {
                    let codes = singleQuotedValues(in: trimmed)
                    nativeCodes.append(contentsOf: codes)
                } else if trimmed.hasPrefix("launchable-activity:") {
                    info.launchableActivity = value(for: "name", in: trimmed)
                    if let label = value(for: "label", in: trimmed), !label.isEmpty {
                        info.launchableActivityLabel = label
                    }
                } else if trimmed.hasPrefix("supports-screens:") {
                    info.supportsScreens = singleQuotedValues(in: trimmed)
                } else if trimmed.hasPrefix("supports-any-density:") {
                    if let flag = singleQuotedValue(in: trimmed)?.lowercased() {
                        info.supportsAnyDensity = (flag == "true")
                    }
                } else if trimmed.hasPrefix("locales:") {
                    info.supportedLocales = singleQuotedValues(in: trimmed)
                } else if trimmed.hasPrefix("densities:") {
                    info.densities = singleQuotedValues(in: trimmed)
                } else if trimmed.hasPrefix("uses-feature-not-required:") {
                    if let feature = value(for: "name", in: trimmed) {
                        optionalFeatures.insert(feature)
                    }
                } else if trimmed.hasPrefix("uses-feature:") {
                    if let feature = value(for: "name", in: trimmed) {
                        requiredFeatures.insert(feature)
                    }
                }
            }

            info.permissions = Array(permissions).sorted()
            info.nativeCodes = Array(Set(nativeCodes)).sorted()
            info.requiredFeatures = Array(requiredFeatures).sorted()
            info.optionalFeatures = Array(optionalFeatures).sorted()
            if let bestIcon = iconCandidates.sorted(by: { $0.density > $1.density }).first {
                info.iconPath = bestIcon.path
            }

            if info.packageName == nil && info.versionName == nil && info.minSDK == nil && info.permissions.isEmpty {
                return nil
            }

            return info
        }

        private static func value(for attribute: String, in line: String) -> String? {
            let token = "\(attribute)='"
            guard let range = line.range(of: token) else { return nil }
            let remainder = line[range.upperBound...]
            guard let end = remainder.firstIndex(of: "'") else { return nil }
            return String(remainder[..<end])
        }

        private static func valueAfterColon(in line: String) -> String? {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let remainder = line[line.index(after: colon)...]
            return singleQuotedValue(in: String(remainder))
        }

        private static func singleQuotedValue(in line: String) -> String? {
            guard let first = line.firstIndex(of: "'") else { return nil }
            let afterFirst = line.index(after: first)
            guard let second = line[afterFirst...].firstIndex(of: "'") else { return nil }
            return String(line[afterFirst..<second])
        }

        private static func singleQuotedValues(in line: String) -> [String] {
            var results: [String] = []
            var index = line.startIndex
            while index < line.endIndex {
                guard let start = line[index...].firstIndex(of: "'") else { break }
                let afterStart = line.index(after: start)
                guard afterStart < line.endIndex else { break }
                guard let end = line[afterStart...].firstIndex(of: "'") else { break }
                results.append(String(line[afterStart..<end]))
                index = line.index(after: end)
            }
            return results
        }

        private static func densityValue(from line: String) -> Int {
            let prefix = "application-icon-"
            guard let range = line.range(of: prefix) else { return 0 }
            let remainder = line[range.upperBound...]
            if let dash = remainder.firstIndex(of: ":") {
                let densityString = remainder[..<dash]
                return Int(densityString) ?? 0
            }
            return 0
        }
    }
}
