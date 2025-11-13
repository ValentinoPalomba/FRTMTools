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
    private let signatureAnalyzer = APKSignatureAnalyzer()

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

        let inspectorInfo: AndroidManifestInfo?
        if url.pathExtension.lowercased() == "apk",
           needsAAPTMetadata(for: manifestResult.info) {
            inspectorInfo = AndroidManifestInspector.inspect(apkURL: url)
        } else {
            inspectorInfo = nil
        }

        let rootFile = fileScanner.scanRoot(at: layout.resourcesRoot)
        let manifestInfo = mergeManifestInfo(preferred: inspectorInfo, fallback: manifestResult.info)
        let cleanedAppLabel = manifestInfo?.appLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appLabel = (cleanedAppLabel?.isEmpty == false) ? cleanedAppLabel : nil
        let supportedABIs = abiDetector.supportedABIs(in: layout, manifestInfo: manifestInfo)
        let icon = iconExtractor.icon(in: layout, manifestInfo: manifestInfo)
        let signatureInfo = signatureAnalyzer.analyzeSignature(in: layout)

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
            allowsArbitraryLoads: allowsArbitraryLoads,
            signatureInfo: signatureInfo
        )
    }

    private func mergeManifestInfo(preferred: AndroidManifestInfo?, fallback: AndroidManifestInfo?) -> AndroidManifestInfo? {
        guard preferred != nil || fallback != nil else { return nil }
        var merged = preferred ?? fallback ?? AndroidManifestInfo()

        func updateIfNil(_ keyPath: WritableKeyPath<AndroidManifestInfo, String?>, from source: AndroidManifestInfo?) {
            if merged[keyPath: keyPath] == nil {
                merged[keyPath: keyPath] = source?[keyPath: keyPath]
            }
        }

        updateIfNil(\.packageName, from: fallback)
        updateIfNil(\.versionName, from: fallback)
        updateIfNil(\.versionCode, from: fallback)
        updateIfNil(\.appLabel, from: fallback)
        updateIfNil(\.minSDK, from: fallback)
        updateIfNil(\.targetSDK, from: fallback)
        updateIfNil(\.iconResource, from: fallback)
        updateIfNil(\.iconPath, from: fallback)

        if let fallbackPermissions = fallback?.permissions {
            merged.permissions = Array(Set(merged.permissions).union(fallbackPermissions)).sorted()
        }
        if let fallbackNativeCodes = fallback?.nativeCodes {
            merged.nativeCodes = Array(Set(merged.nativeCodes).union(fallbackNativeCodes)).sorted()
        }
        return merged
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
}

// MARK: - Android build-tools helpers (aapt integration)

extension APKAnalyzer {
    /// Utility that locates Android build-tools executables (aapt/aapt2).
    enum AndroidBuildTools {
        nonisolated(unsafe) private static var cachedExecutables: [String: URL?] = [:]

        static func locateExecutable(named executable: String) -> URL? {
            if let cached = cachedExecutables[executable] {
                return cached
            }

            let fm = FileManager.default
            let env = ProcessInfo.processInfo.environment
            let result = resolveExecutable(named: executable, fm: fm, env: env)
            cachedExecutables[executable] = result
            return result
        }

        private static func resolveExecutable(named executable: String, fm: FileManager, env: [String: String]) -> URL? {
            for candidate in candidatePaths(named: executable, fm: fm, env: env) {
                if fm.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
            return nil
        }

        private static func candidatePaths(named executable: String, fm: FileManager, env: [String: String]) -> [URL] {
            var candidates: [URL] = []

            let explicitKeys = ["AAPT_PATH", "ANDROID_AAPT_PATH"]
            for key in explicitKeys {
                if let explicit = env[key], !explicit.isEmpty {
                    candidates.append(URL(fileURLWithPath: explicit))
                }
            }
            if let buildToolsBin = env["ANDROID_BUILD_TOOLS"], !buildToolsBin.isEmpty {
                candidates.append(URL(fileURLWithPath: buildToolsBin, isDirectory: true).appendingPathComponent(executable))
            }

            if let pathEnv = env["PATH"], !pathEnv.isEmpty {
                for path in pathEnv.split(separator: ":") {
                    candidates.append(URL(fileURLWithPath: String(path), isDirectory: true).appendingPathComponent(executable))
                }
            }

            candidates.append(contentsOf: searchBuildToolDirectories(named: executable, fm: fm, env: env))
            candidates.append(contentsOf: searchCommandLineToolDirectories(named: executable, fm: fm, env: env))

            return candidates
        }

        private static func searchBuildToolDirectories(named executable: String, fm: FileManager, env: [String: String]) -> [URL] {
            var roots: [URL] = []
            let home = fm.homeDirectoryForCurrentUser
            roots.append(appendComponents(home, components: ["Library", "Android", "sdk", "build-tools"]))
            roots.append(appendComponents(home, components: ["Android", "Sdk", "build-tools"]))
            roots.append(appendComponents(home, components: ["Library", "Developer", "Xamarin", "android-sdk-macosx", "build-tools"]))
            roots.append(URL(fileURLWithPath: "/Library/Android/sdk/build-tools", isDirectory: true))
            roots.append(URL(fileURLWithPath: "/usr/local/share/android-sdk/build-tools", isDirectory: true))
            roots.append(URL(fileURLWithPath: "/usr/local/opt/android-sdk/build-tools", isDirectory: true))

            if let androidHome = env["ANDROID_HOME"] {
                roots.append(URL(fileURLWithPath: androidHome, isDirectory: true).appendingPathComponent("build-tools", isDirectory: true))
            }
            if let androidSDKRoot = env["ANDROID_SDK_ROOT"] {
                roots.append(URL(fileURLWithPath: androidSDKRoot, isDirectory: true).appendingPathComponent("build-tools", isDirectory: true))
            }

            var candidates: [URL] = []
            for root in roots {
                guard fm.fileExists(atPath: root.path) else { continue }
                guard let versionDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
                let sorted = versionDirs.sorted {
                    $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
                }
                for dir in sorted {
                    candidates.append(dir.appendingPathComponent(executable))
                }
            }
            return candidates
        }

        private static func searchCommandLineToolDirectories(named executable: String, fm: FileManager, env: [String: String]) -> [URL] {
            var cmdlineRoots: [URL] = []
            let home = fm.homeDirectoryForCurrentUser
            let librarySDK = home
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Android", isDirectory: true)
                .appendingPathComponent("sdk", isDirectory: true)
            let androidSdk = home
                .appendingPathComponent("Android", isDirectory: true)
                .appendingPathComponent("Sdk", isDirectory: true)

            cmdlineRoots.append(librarySDK.appendingPathComponent("cmdline-tools", isDirectory: true))
            cmdlineRoots.append(androidSdk.appendingPathComponent("cmdline-tools", isDirectory: true))

            if let androidHome = env["ANDROID_HOME"], !androidHome.isEmpty {
                cmdlineRoots.append(URL(fileURLWithPath: androidHome, isDirectory: true).appendingPathComponent("cmdline-tools", isDirectory: true))
            }
            if let androidSDKRoot = env["ANDROID_SDK_ROOT"], !androidSDKRoot.isEmpty {
                cmdlineRoots.append(URL(fileURLWithPath: androidSDKRoot, isDirectory: true).appendingPathComponent("cmdline-tools", isDirectory: true))
            }

            var candidates: [URL] = []
            for root in cmdlineRoots {
                guard fm.fileExists(atPath: root.path) else { continue }
                guard let toolDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
                for dir in toolDirs {
                    let bin = dir.appendingPathComponent("bin", isDirectory: true).appendingPathComponent(executable)
                    candidates.append(bin)
                }
            }
            return candidates
        }
        private static func appendComponents(_ base: URL, components: [String]) -> URL {
            components.reduce(base) { partial, component in
                partial.appendingPathComponent(component, isDirectory: true)
            }
        }
    }

    /// Legacy manifest inspector powered by `aapt dump badging`.
    /// Left here for archival purposes; the current analyzer uses local manifest parsing instead.
    enum AndroidManifestInspector {
        static func inspect(apkURL: URL) -> AndroidManifestInfo? {
            guard apkURL.pathExtension.lowercased() == "apk" else {
                return nil
            }
            guard let toolURL = AndroidBuildTools.locateExecutable(named: "aapt2") else {
                print("⚠️ Unable to locate aapt/aapt2. Install Android SDK build-tools and expose them via ANDROID_HOME/ANDROID_SDK_ROOT or PATH.")
                return nil
            }

            do {
                let output = try run(toolURL: toolURL, arguments: ["dump", "badging", apkURL.path])
                return parseBadging(output: output)
            } catch {
                print("⚠️ aapt dump badging failed for \(apkURL.lastPathComponent): \(error)")
                return nil
            }
        }

        private static func run(toolURL: URL, arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = toolURL
            process.arguments = arguments

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
                }
            }

            info.permissions = Array(permissions).sorted()
            info.nativeCodes = Array(Set(nativeCodes)).sorted()
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
