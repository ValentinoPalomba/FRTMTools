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

final class APKAnalyzer: Analyzer {
    private static let supportedExtensions: Set<String> = ["apk", "aab", "abb"]

    private let archiveExtractor = APKArchiveExtractor()
    private let manifestAnalyzer = APKManifestAnalyzer()
    private let fileScanner = APKFileScanner()
    private let iconExtractor = APKIconExtractor()
    private let abiDetector = APKABIDetector()

    func analyze(at url: URL) async throws -> APKAnalysis? {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }

        guard let extractionResult = archiveExtractor.extractPackage(at: url) else {
            return nil
        }
        defer { archiveExtractor.cleanup(extractionResult) }

        let manifestResult = manifestAnalyzer.inspectManifest(atRoot: extractionResult.analysisRoot)
        let layout = AndroidPackageLayout(rootURL: extractionResult.analysisRoot, manifestURL: manifestResult.manifestURL)

        let rootFile = fileScanner.scanRoot(at: layout.resourcesRoot)
        let manifestInfo = manifestResult.info
        let cleanedAppLabel = manifestInfo?.appLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appLabel = (cleanedAppLabel?.isEmpty == false) ? cleanedAppLabel : nil
        let supportedABIs = abiDetector.supportedABIs(in: layout, manifestInfo: manifestInfo)
        let icon = iconExtractor.icon(in: layout, manifestInfo: manifestInfo)

        // TODO: Da investigare - calcolare lo stripping dei binari Android
        let isStripped = false
        // TODO: Da investigare - determinare l'equivalente ATS per APK
        let allowsArbitraryLoads = false

        return APKAnalysis(
            url: layout.rootURL,
            fileName: url.lastPathComponent,
            executableName: appLabel ?? manifestInfo?.packageName ?? url.deletingPathExtension().lastPathComponent,
            appLabel: appLabel,
            rootFile: rootFile,
            image: icon,
            version: manifestInfo?.versionName,
            buildNumber: manifestInfo?.versionCode,
            packageName: manifestInfo?.packageName,
            minSDK: manifestInfo?.minSDK,
            targetSDK: manifestInfo?.targetSDK,
            permissions: manifestInfo?.permissions ?? [],
            supportedABIs: supportedABIs,
            isStripped: isStripped,
            allowsArbitraryLoads: allowsArbitraryLoads
        )
    }
}
