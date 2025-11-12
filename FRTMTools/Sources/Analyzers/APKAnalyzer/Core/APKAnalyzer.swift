//
//  APKAnalyzer.swift
//  FRTMTools
//
//

import Foundation
import AppKit

/// Main analyzer for Android APK files
class APKAnalyzer {
    private var extractedPath: URL?
    private var apkPath: URL?
    private var rootFile: FileInfo?
    private var metadata: APKMetadata?

    /// If true, will try to use aapt before falling back to Python script
    var preferAapt: Bool = true

    /// Metadata extracted from AndroidManifest.xml and APK
    struct APKMetadata {
        var packageName: String?
        var appLabel: String?
        var versionName: String?
        var versionCode: String?
        var minSdkVersion: Int?
        var targetSdkVersion: Int?
        var permissions: [String] = []
        var iconPath: String?
    }

    /// Analyzes an APK file at the given URL
    /// - Parameter url: The URL of the APK file
    /// - Returns: An APKAnalysis object containing all analysis data
    func analyze(at url: URL) async throws -> APKAnalysis {
        self.apkPath = url

        // Step 1: Extract APK
        try await extractAPK(at: url)

        guard let extractedPath = extractedPath else {
            throw APKAnalyzerError.extractionFailed
        }

        // Step 2: Parse AndroidManifest.xml to extract metadata
        await parseManifest(at: extractedPath)

        // Step 3: Scan file hierarchy
        let rootFile = try await scan(path: extractedPath)
        self.rootFile = rootFile

        // Step 4: Extract app icon
        let iconData = await extractIcon(from: extractedPath)

        // Step 5: Analyze DEX files
        let (dexCount, totalDexSize, isObfuscated) = await analyzeDexFiles(at: extractedPath)

        // Step 6: Detect supported ABIs
        let supportedABIs = await detectABIs(at: extractedPath)

        // Step 7: Create APKAnalysis object
        let analysis = APKAnalysis(
            fileName: url.lastPathComponent,
            packageName: metadata?.packageName,
            appLabel: metadata?.appLabel,
            url: url,
            rootFile: rootFile,
            versionName: metadata?.versionName,
            versionCode: metadata?.versionCode,
            minSdkVersion: metadata?.minSdkVersion,
            targetSdkVersion: metadata?.targetSdkVersion,
            permissions: metadata?.permissions,
            installedSize: nil, // Will be calculated separately
            dependencyGraph: nil, // Will be generated separately
            imageData: iconData,
            supportedABIs: supportedABIs,
            dexFileCount: dexCount,
            totalDexSize: totalDexSize,
            isObfuscated: isObfuscated
        )

        return analysis
    }

    /// Extracts the APK file to a temporary directory
    private func extractAPK(at url: URL) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FRTMTools_APK_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", url.path, "-d", tempDir.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw APKAnalyzerError.extractionFailed
        }

        self.extractedPath = tempDir

        // Also persist to cache for user access
        await persistExtractedAPK(from: tempDir, originalName: url.deletingPathExtension().lastPathComponent)
    }

    /// Persists extracted APK to cache directory
    private func persistExtractedAPK(from tempDir: URL, originalName: String) async {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FRTMTools/ExtractedAPKs", isDirectory: true)

        guard let cacheDir = cacheDir else { return }

        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            let destination = cacheDir.appendingPathComponent(originalName, isDirectory: true)

            // Remove if exists
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(at: tempDir, to: destination)
        } catch {
            print("Failed to persist extracted APK: \(error)")
        }
    }

    /// Parses AndroidManifest.xml using aapt tool
    private func parseManifest(at extractedPath: URL) async {
        guard let apkPath = apkPath else { return }

        // If user prefers Python script, skip aapt entirely
        if !preferAapt {
            await parseManifestFallback(at: extractedPath)
            return
        }

        // Try to use aapt or aapt2 from Android SDK if available
        // First check common Android SDK locations
        let possibleAaptPaths = [
            "/usr/local/bin/aapt",
            "/opt/homebrew/bin/aapt",
            "~/Library/Android/sdk/build-tools/*/aapt",
            "/Users/\(NSUserName())/Library/Android/sdk/build-tools/*/aapt"
        ]

        var aaptPath: String?
        for path in possibleAaptPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                aaptPath = expandedPath
                break
            }
        }

        // If aapt not found, try to find it in Android SDK build-tools
        if aaptPath == nil {
            aaptPath = await findAaptInSDK()
        }

        guard let aaptPath = aaptPath else {
            // Fallback: try to parse basic info from manifest file directly
            await parseManifestFallback(at: extractedPath)
            return
        }

        // Use aapt dump badging to extract metadata
        let process = Process()
        process.executableURL = URL(fileURLWithPath: aaptPath)
        process.arguments = ["dump", "badging", apkPath.path]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return }

            parseAaptOutput(output)
        } catch {
            await parseManifestFallback(at: extractedPath)
        }
    }

    /// Finds aapt in Android SDK build-tools directory
    private func findAaptInSDK() async -> String? {
        let sdkPaths = [
            "~/Library/Android/sdk",
            "/Users/\(NSUserName())/Library/Android/sdk"
        ]

        for sdkPath in sdkPaths {
            let expandedPath = NSString(string: sdkPath).expandingTildeInPath
            let buildToolsPath = URL(fileURLWithPath: expandedPath).appendingPathComponent("build-tools")

            guard FileManager.default.fileExists(atPath: buildToolsPath.path) else { continue }

            do {
                let versions = try FileManager.default.contentsOfDirectory(atPath: buildToolsPath.path)
                    .sorted()
                    .reversed()

                for version in versions {
                    let aaptPath = buildToolsPath
                        .appendingPathComponent(version)
                        .appendingPathComponent("aapt")
                        .path

                    if FileManager.default.fileExists(atPath: aaptPath) {
                        return aaptPath
                    }
                }
            } catch {
                continue
            }
        }

        return nil
    }

    /// Parses aapt dump badging output
    private func parseAaptOutput(_ output: String) {
        var meta = APKMetadata()

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Parse package info
            if line.starts(with: "package:") {
                // Extract package name
                if let nameRange = line.range(of: "name='([^']+)'", options: .regularExpression) {
                    let nameStr = String(line[nameRange])
                    meta.packageName = nameStr.replacingOccurrences(of: "name='", with: "").replacingOccurrences(of: "'", with: "")
                }

                // Extract version code
                if let versionCodeRange = line.range(of: "versionCode='([^']+)'", options: .regularExpression) {
                    let versionCodeStr = String(line[versionCodeRange])
                    meta.versionCode = versionCodeStr.replacingOccurrences(of: "versionCode='", with: "").replacingOccurrences(of: "'", with: "")
                }

                // Extract version name
                if let versionNameRange = line.range(of: "versionName='([^']+)'", options: .regularExpression) {
                    let versionNameStr = String(line[versionNameRange])
                    meta.versionName = versionNameStr.replacingOccurrences(of: "versionName='", with: "").replacingOccurrences(of: "'", with: "")
                }
            }

            // Parse SDK versions
            if line.starts(with: "sdkVersion:") {
                let version = line.replacingOccurrences(of: "sdkVersion:", with: "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "'", with: "")
                meta.minSdkVersion = Int(version)
            }

            if line.starts(with: "targetSdkVersion:") {
                let version = line.replacingOccurrences(of: "targetSdkVersion:", with: "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "'", with: "")
                meta.targetSdkVersion = Int(version)
            }

            // Parse permissions
            if line.starts(with: "uses-permission:") {
                if let nameRange = line.range(of: "name='([^']+)'", options: .regularExpression) {
                    let permission = String(line[nameRange])
                        .replacingOccurrences(of: "name='", with: "")
                        .replacingOccurrences(of: "'", with: "")
                    meta.permissions.append(permission)
                }
            }

            // Parse app label
            if line.starts(with: "application-label:") {
                let label = line.replacingOccurrences(of: "application-label:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "'", with: "")
                meta.appLabel = label
            }

            // Parse icon path
            if line.starts(with: "application-icon-") {
                if let pathRange = line.range(of: ":'([^']+)'", options: .regularExpression) {
                    let iconPath = String(line[pathRange])
                        .replacingOccurrences(of: ":'", with: "")
                        .replacingOccurrences(of: "'", with: "")
                    meta.iconPath = iconPath
                }
            }
        }

        self.metadata = meta
    }

    /// Fallback manifest parser using Python script
    private func parseManifestFallback(at extractedPath: URL) async {
        guard let apkPath = apkPath else { return }

        // Use Python script to parse binary XML
        let scriptPath = Bundle.main.path(forResource: "parse_apk_manifest", ofType: "py") ??
            Bundle.main.bundlePath + "/Contents/Resources/parse_apk_manifest.py"

        // Try to find the script in the source directory
        let possibleScriptPaths = [
            scriptPath,
            "/Users/dave/git/FRTMTools/FRTMTools/Sources/Analyzers/APKAnalyzer/Helpers/parse_apk_manifest.py",
            Bundle.main.resourcePath.map { $0 + "/parse_apk_manifest.py" } ?? ""
        ]

        var workingScriptPath: String?
        for path in possibleScriptPaths {
            if FileManager.default.fileExists(atPath: path) {
                workingScriptPath = path
                break
            }
        }

        guard let scriptPath = workingScriptPath else {
            print("Warning: Python manifest parser not found")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath, apkPath.path]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return }

            var meta = APKMetadata()
            let lines = output.components(separatedBy: .newlines)

            for line in lines {
                if line.starts(with: "package:") {
                    meta.packageName = line.replacingOccurrences(of: "package:", with: "")
                } else if line.starts(with: "versionName:") {
                    meta.versionName = line.replacingOccurrences(of: "versionName:", with: "")
                } else if line.starts(with: "versionCode:") {
                    meta.versionCode = line.replacingOccurrences(of: "versionCode:", with: "")
                } else if line.starts(with: "appLabel:") {
                    meta.appLabel = line.replacingOccurrences(of: "appLabel:", with: "")
                } else if line.starts(with: "permission:") {
                    let permission = line.replacingOccurrences(of: "permission:", with: "")
                    meta.permissions.append(permission)
                }
            }

            self.metadata = meta
        } catch {
            print("Error running Python parser: \(error)")
        }
    }

    /// Scans the extracted APK directory recursively
    private func scan(path: URL) async throws -> FileInfo {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        let size = attributes[.size] as? Int64 ?? 0

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)

        let name = path.lastPathComponent
        let fileType = determineFileType(for: path, isDirectory: isDirectory.boolValue)

        if isDirectory.boolValue {
            var subItems: [FileInfo] = []

            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: path.path)

                for item in contents {
                    let itemPath = path.appendingPathComponent(item)
                    let subItem = try await scan(path: itemPath)
                    subItems.append(subItem)
                }
            } catch {
                // Skip items that can't be read
            }

            // Calculate total size including all subitems
            let totalSize = subItems.reduce(0) { $0 + $1.size }

            return FileInfo(
                path: path.path,
                fullPath: path.path,
                name: name,
                type: fileType,
                size: totalSize,
                subItems: subItems.isEmpty ? nil : subItems
            )
        } else {
            return FileInfo(
                path: path.path,
                fullPath: path.path,
                name: name,
                type: fileType,
                size: size
            )
        }
    }

    /// Determines the file type based on extension and location
    private func determineFileType(for url: URL, isDirectory: Bool) -> FileType {
        if isDirectory {
            return .directory
        }

        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        switch ext {
        case "dex":
            return .dex
        case "so":
            return .so
        case "xml":
            return .xml
        case "arsc":
            return .arsc
        default:
            return .file
        }
    }

    /// Extracts the app icon from the APK
    private func extractIcon(from extractedPath: URL) async -> Data? {
        // Try to find icon from metadata first
        if let iconPath = metadata?.iconPath {
            let iconURL = extractedPath.appendingPathComponent(iconPath)
            if let iconData = try? Data(contentsOf: iconURL) {
                return iconData
            }
        }

        // Fallback: search for common icon locations
        let commonIconPaths = [
            "res/mipmap-xxxhdpi/ic_launcher.png",
            "res/mipmap-xxhdpi/ic_launcher.png",
            "res/mipmap-xhdpi/ic_launcher.png",
            "res/mipmap-hdpi/ic_launcher.png",
            "res/drawable-xxxhdpi/ic_launcher.png",
            "res/drawable-xxhdpi/ic_launcher.png",
            "res/drawable-xhdpi/ic_launcher.png",
            "res/drawable-hdpi/ic_launcher.png",
            "res/drawable/ic_launcher.png"
        ]

        for iconPath in commonIconPaths {
            let iconURL = extractedPath.appendingPathComponent(iconPath)
            if let iconData = try? Data(contentsOf: iconURL) {
                return iconData
            }
        }

        return nil
    }

    /// Analyzes DEX files in the APK
    private func analyzeDexFiles(at extractedPath: URL) async -> (count: Int, totalSize: Int64, isObfuscated: Bool) {
        var dexCount = 0
        var totalSize: Int64 = 0
        var isObfuscated = false

        guard let enumerator = FileManager.default.enumerator(atPath: extractedPath.path) else {
            return (0, 0, false)
        }

        let allFiles = enumerator.allObjects.compactMap { $0 as? String }

        for file in allFiles {
            if file.hasSuffix(".dex") {
                dexCount += 1

                let filePath = extractedPath.appendingPathComponent(file)
                if let attributes = try? FileManager.default.attributesOfItem(atPath: filePath.path),
                   let size = attributes[.size] as? Int64 {
                    totalSize += size
                }

                // Check for obfuscation (simple heuristic: look for ProGuard mapping file)
                if !isObfuscated {
                    let mappingPath = extractedPath.appendingPathComponent("mapping.txt")
                    isObfuscated = FileManager.default.fileExists(atPath: mappingPath.path)
                }
            }
        }

        return (dexCount, totalSize, isObfuscated)
    }

    /// Detects supported ABIs from the lib directory
    private func detectABIs(at extractedPath: URL) async -> [String]? {
        let libPath = extractedPath.appendingPathComponent("lib")

        guard FileManager.default.fileExists(atPath: libPath.path) else {
            return nil
        }

        do {
            let abis = try FileManager.default.contentsOfDirectory(atPath: libPath.path)
                .filter { !$0.starts(with: ".") }
                .sorted()

            return abis.isEmpty ? nil : abis
        } catch {
            return nil
        }
    }
}

/// Errors that can occur during APK analysis
enum APKAnalyzerError: Error {
    case extractionFailed
    case manifestParsingFailed
    case fileNotFound
    case invalidAPK
}
