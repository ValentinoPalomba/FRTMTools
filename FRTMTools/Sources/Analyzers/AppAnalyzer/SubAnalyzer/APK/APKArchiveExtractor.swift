import Foundation

struct APKExtractionResult: Sendable {
    let workingDirectory: URL
    let analysisRoot: URL
    let shouldCleanupWorkingDirectory: Bool
    let bundletoolEstimates: BundletoolSizeEstimates?
    let assetPacks: [PlayAssetPackInfo]
    let dynamicFeatures: [DynamicFeatureInfo]
    let inspectorArchiveURL: URL?
}

final class APKArchiveExtractor: @unchecked Sendable {
    private let fm = FileManager.default
    private let persistor = APKPayloadPersistor()
    private let bundletool = BundletoolInvoker()
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    func extractPackage(at archiveURL: URL) -> APKExtractionResult? {
        let ext = archiveURL.pathExtension.lowercased()
        switch ext {
        case "aab", "abb":
            return extractBundle(at: archiveURL)
        default:
            return extractArchive(at: archiveURL, originalFileURL: archiveURL)
        }
    }

    func cleanup(_ result: APKExtractionResult) {
        guard result.shouldCleanupWorkingDirectory else { return }
        try? fm.removeItem(at: result.workingDirectory)
    }

    private func extractArchive(at archiveURL: URL, originalFileURL: URL) -> APKExtractionResult? {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("APK-\(UUID().uuidString)", isDirectory: true)
        let payloadRoot = tempRoot.appendingPathComponent("Payload", isDirectory: true)

        do {
            try fm.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
            try unzip(archiveURL, into: payloadRoot)

            if let persistedURL = persistor.persistPayload(at: payloadRoot, originalFileURL: originalFileURL) {
                return APKExtractionResult(
                    workingDirectory: tempRoot,
                    analysisRoot: persistedURL,
                    shouldCleanupWorkingDirectory: true,
                    bundletoolEstimates: nil,
                    assetPacks: [],
                    dynamicFeatures: [],
                    inspectorArchiveURL: originalFileURL
                )
            } else {
                return APKExtractionResult(
                    workingDirectory: tempRoot,
                    analysisRoot: payloadRoot,
                    shouldCleanupWorkingDirectory: false,
                    bundletoolEstimates: nil,
                    assetPacks: [],
                    dynamicFeatures: [],
                    inspectorArchiveURL: originalFileURL
                )
            }
        } catch {
            try? fm.removeItem(at: tempRoot)
            print("⚠️ Failed to extract \(archiveURL.lastPathComponent): \(error)")
            return nil
        }
    }

    private func extractBundle(at bundleURL: URL) -> APKExtractionResult? {
        guard bundletool.isAvailable else {
            print("⚠️ bundletool not available. Falling back to direct extraction for \(bundleURL.lastPathComponent).")
            return extractArchive(at: bundleURL, originalFileURL: bundleURL)
        }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Bundle-\(UUID().uuidString)", isDirectory: true)
        let apksArchive = tempRoot.appendingPathComponent("Generated.apks")
        let apksExtractionDir = tempRoot.appendingPathComponent("APKs", isDirectory: true)
        let payloadRoot = tempRoot.appendingPathComponent("Payload", isDirectory: true)
        let deviceSpecURL = tempRoot.appendingPathComponent("device-spec.json")
        let bundleContentsDir = tempRoot.appendingPathComponent("BundleContents", isDirectory: true)

        do {
            try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try fm.createDirectory(at: bundleContentsDir, withIntermediateDirectories: true)
            try bundletool.buildAPKSet(bundleURL: bundleURL, outputURL: apksArchive)
            if bundletool.generateDeviceSpec(to: deviceSpecURL) == false {
                try bundletool.writeDefaultDeviceSpec(to: deviceSpecURL)
            }
            let sizeEstimates = bundletool.calculateInstallSize(apksArchiveURL: apksArchive, deviceSpecURL: deviceSpecURL)
            logSizeEstimates(sizeEstimates, for: bundleURL)
            try unzip(bundleURL, into: bundleContentsDir)
            let dynamicFeatures = discoverDynamicFeatures(in: bundleContentsDir, bundleURL: bundleURL)

            try fm.createDirectory(at: apksExtractionDir, withIntermediateDirectories: true)
            try unzip(apksArchive, into: apksExtractionDir)

            try fm.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
            let primarySplit = try primarySplitAPK(in: apksExtractionDir)
            try unzip(primarySplit, into: payloadRoot)
            copyBundleMetadataIfPresent(from: bundleContentsDir, to: payloadRoot)

            let assetPacks = discoverAssetPacks(in: apksExtractionDir, bundleURL: bundleURL)

            if let persistedURL = persistor.persistPayload(at: payloadRoot, originalFileURL: bundleURL) {
                return APKExtractionResult(
                    workingDirectory: tempRoot,
                    analysisRoot: persistedURL,
                    shouldCleanupWorkingDirectory: true,
                    bundletoolEstimates: sizeEstimates,
                    assetPacks: assetPacks,
                    dynamicFeatures: dynamicFeatures,
                    inspectorArchiveURL: primarySplit
                )
            } else {
                return APKExtractionResult(
                    workingDirectory: tempRoot,
                    analysisRoot: payloadRoot,
                    shouldCleanupWorkingDirectory: false,
                    bundletoolEstimates: sizeEstimates,
                    assetPacks: assetPacks,
                    dynamicFeatures: dynamicFeatures,
                    inspectorArchiveURL: primarySplit
                )
            }
        } catch {
            print("⚠️ Failed to process \(bundleURL.lastPathComponent) with bundletool: \(error)")
            try? fm.removeItem(at: tempRoot)
            return extractArchive(at: bundleURL, originalFileURL: bundleURL)
        }
    }

    private func logSizeEstimates(_ estimates: BundletoolSizeEstimates?, for bundleURL: URL) {
        guard let estimates else {
            print("⚠️ bundletool did not return install-size data for \(bundleURL.lastPathComponent).")
            return
        }
        let install = byteFormatter.string(fromByteCount: estimates.installBytes)
        var message = "ℹ️ bundletool size for \(bundleURL.lastPathComponent): install \(install)"
        if let downloadBytes = estimates.downloadBytes {
            let download = byteFormatter.string(fromByteCount: downloadBytes)
            message += " · download \(download)"
        }
        print(message)
    }

    private func primarySplitAPK(in apksRoot: URL) throws -> URL {
        let splitsDir = apksRoot.appendingPathComponent("splits", isDirectory: true)
        guard let contents = try? fm.contentsOfDirectory(at: splitsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles), !contents.isEmpty else {
            throw BundletoolInvoker.BundletoolError.commandFailed(arguments: ["build-apks"], stderr: "no splits produced")
        }
        if let master = contents.first(where: { $0.lastPathComponent.contains("base-master") }) {
            return master
        }
        if let base = contents.first(where: { $0.lastPathComponent == "base.apk" }) {
            return base
        }
        if let first = contents.first(where: { $0.pathExtension.lowercased() == "apk" }) {
            return first
        }
        throw BundletoolInvoker.BundletoolError.commandFailed(arguments: ["build-apks"], stderr: "no primary split found")
    }

    private func unzip(_ archiveURL: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // -o avoids interactive replace prompts when archives contain duplicate entries
        process.arguments = ["-qq", "-o", archiveURL.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "APKArchiveExtractor", code: Int(process.terminationStatus), userInfo: nil)
        }
    }

    private func copyBundleMetadataIfPresent(from bundleContentsURL: URL, to payloadRoot: URL) {
        let metadataSource = bundleContentsURL.appendingPathComponent("BUNDLE-METADATA", isDirectory: true)
        guard fm.fileExists(atPath: metadataSource.path) else { return }

        let metadataDestination = payloadRoot.appendingPathComponent("BUNDLE-METADATA", isDirectory: true)
        do {
            if fm.fileExists(atPath: metadataDestination.path) {
                try fm.removeItem(at: metadataDestination)
            }
            try fm.copyItem(at: metadataSource, to: metadataDestination)
            print("ℹ️ Preserved bundle metadata for analysis at \(metadataDestination.path)")
        } catch {
            print("⚠️ Failed to copy bundle metadata for dex deobfuscation: \(error)")
        }
    }

    private func discoverAssetPacks(in apksRoot: URL, bundleURL: URL) -> [PlayAssetPackInfo] {
        let splitsDir = apksRoot.appendingPathComponent("splits", isDirectory: true)
        guard fm.fileExists(atPath: splitsDir.path) else { return [] }
        let files = (try? fm.contentsOfDirectory(at: splitsDir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)) ?? []
        var packs: [PlayAssetPackInfo] = []
        for file in files where file.pathExtension.lowercased() == "apk" {
            guard let parsed = parseAssetPackFilename(file.lastPathComponent) else { continue }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? file.allocatedSize()
            let delivery = determineModuleDeliveryType(for: parsed.moduleName, bundleURL: bundleURL)
            packs.append(PlayAssetPackInfo(
                name: parsed.displayName,
                moduleName: parsed.moduleName,
                deliveryType: delivery,
                compressedSizeBytes: size
            ))
        }
        return packs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func parseAssetPackFilename(_ filename: String) -> (moduleName: String, displayName: String)? {
        let trimmed = filename.replacingOccurrences(of: ".apk", with: "")
        let prefixes = ["asset-pack.", "asset-pack_"]
        guard let prefix = prefixes.first(where: { trimmed.hasPrefix($0) }) else { return nil }
        var remainder = String(trimmed.dropFirst(prefix.count))
        guard !remainder.isEmpty else { return nil }
        if let dashRange = remainder.range(of: "-") {
            remainder = String(remainder[..<dashRange.lowerBound])
        }
        guard !remainder.isEmpty else { return nil }
        let moduleName = "asset-pack.\(remainder)"
        return (moduleName, remainder)
    }

    private func discoverDynamicFeatures(in bundleRoot: URL, bundleURL: URL) -> [DynamicFeatureInfo] {
        guard fm.fileExists(atPath: bundleRoot.path) else { return [] }
        let moduleDirs = (try? fm.contentsOfDirectory(at: bundleRoot, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        var features: [DynamicFeatureInfo] = []
        for moduleDir in moduleDirs {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: moduleDir.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let moduleName = moduleDir.lastPathComponent
            guard shouldInspectModule(named: moduleName) else { continue }
            let manifestURL = moduleDir.appendingPathComponent("manifest/AndroidManifest.xml")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            let delivery = determineModuleDeliveryType(for: moduleName, bundleURL: bundleURL)
            let sizeBytes = directorySize(at: moduleDir)
            let displayName = prettifiedModuleName(moduleName)
            let files = topFiles(in: moduleDir)
            features.append(DynamicFeatureInfo(
                name: displayName,
                moduleName: moduleName,
                deliveryType: delivery,
                estimatedSizeBytes: sizeBytes,
                files: files
            ))
        }
        return features.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func shouldInspectModule(named moduleName: String) -> Bool {
        if moduleName == "base" { return false }
        if moduleName == "BUNDLE-METADATA" { return false }
        if moduleName.hasPrefix("asset-pack") { return false }
        if moduleName.hasPrefix("asset_pack") { return false }
        return true
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: .skipsHiddenFiles, errorHandler: nil) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    private func topFiles(in moduleURL: URL, limit: Int = 15) -> [DynamicFeatureFileInfo] {
        guard let enumerator = fm.enumerator(at: moduleURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles], errorHandler: nil) else {
            return []
        }
        var entries: [(name: String, path: String, size: Int64)] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            let relative = relativePath(in: moduleURL, fileURL: fileURL)
            entries.append((fileURL.lastPathComponent, relative, size))
        }
        return entries
            .sorted { $0.size > $1.size }
            .prefix(limit)
            .map { DynamicFeatureFileInfo(name: $0.name, path: $0.path, sizeBytes: $0.size) }
    }

    private func relativePath(in base: URL, fileURL: URL) -> String {
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        let path = fileURL.path
        if path.hasPrefix(basePath) {
            let start = path.index(path.startIndex, offsetBy: basePath.count)
            return String(path[start...])
        }
        return fileURL.lastPathComponent
    }

    private func prettifiedModuleName(_ name: String) -> String {
        let replaced = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return name }
        return trimmed.capitalized
    }

    private func determineModuleDeliveryType(for moduleName: String, bundleURL: URL) -> PlayAssetDeliveryType {
        guard bundletool.isAvailable else { return .unknown }
        guard let manifestText = bundletool.dumpManifest(forModule: moduleName, bundleURL: bundleURL) else {
            return .unknown
        }
        if manifestText.contains("dist:on-demand") {
            return .onDemand
        }
        if manifestText.contains("dist:fast-follow") {
            return .fastFollow
        }
        if manifestText.contains("dist:install-time") {
            return .installTime
        }
        return .unknown
    }
}

private final class APKPayloadPersistor: @unchecked Sendable {
    private let fm = FileManager.default

    func persistPayload(at sourceURL: URL, originalFileURL: URL) -> URL? {
        CacheLocations.ensureExtractedAPKsDirectoryExists()
        let folderName = originalFileURL.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString
        let destination = CacheLocations.extractedAPKsDirectory.appendingPathComponent(folderName, isDirectory: true)

        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: sourceURL, to: destination)
            return destination
        } catch {
            print("⚠️ Unable to persist extracted payload: \(error)")
            return nil
        }
    }
}
