//
//  StaticLibraryAnalyzer.swift
//  FRTMTools
//
//  Created by Claude Code
//

import Foundation

/// Analyzer for detecting SPM packages, embedded frameworks, and modules in a Mach-O binary
public final class StaticLibraryAnalyzer: @unchecked Sendable {

    // MARK: - Public API

    /// Analyze a binary to detect embedded SPM packages, frameworks, and modules
    /// - Parameters:
    ///   - binaryURL: URL to the main executable binary
    ///   - appBundleURL: Optional URL to the .app bundle (for framework size calculation)
    func analyze(binaryURL: URL, appBundleURL: URL? = nil) async -> BinaryComposition? {
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            return nil
        }

        var warnings: [String] = []

        // Get binary file size
        let totalSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: binaryURL.path)
            totalSize = attrs[.size] as? Int64 ?? 0
        } catch {
            totalSize = 0
        }

        // Check if binary is encrypted
        let isEncrypted = await checkIfEncrypted(at: binaryURL)
        if isEncrypted {
            warnings.append("Binary is encrypted (FairPlay DRM)")
        }

        // Analyze segments (filter out __PAGEZERO)
        let segments = await analyzeSegments(at: binaryURL)
            .filter { $0.name != "__PAGEZERO" }

        // Check if binary is stripped
        let isStripped = await checkIfStripped(at: binaryURL)

        // Extract linked libraries using otool -L
        let (linkedLibs, systemFrameworks) = await extractLinkedLibraries(from: binaryURL)

        // Detect SPM packages from linked libraries (dynamic)
        let spmPackages = detectSPMPackages(from: linkedLibs, frameworksURL: appBundleURL?.appendingPathComponent("Frameworks"))

        // Detect statically linked modules from symbols
        let textSize = segments.first { $0.name == "__TEXT" }?.size ?? 0
        let staticModules = await extractStaticModules(from: binaryURL, textSegmentSize: textSize, isStripped: isStripped)

        return BinaryComposition(
            binaryURL: binaryURL,
            binaryName: binaryURL.lastPathComponent,
            totalSize: totalSize,
            segments: segments,
            isEncrypted: isEncrypted,
            isStripped: isStripped,
            analysisWarnings: warnings,
            spmPackages: spmPackages,
            systemFrameworks: systemFrameworks,
            staticModules: staticModules
        )
    }

    // MARK: - Encryption Check

    private func checkIfEncrypted(at binaryURL: URL) async -> Bool {
        guard let output = await runProcess(
            executablePath: "/usr/bin/otool",
            arguments: ["-l", binaryURL.path]
        ) else { return false }

        // Look for LC_ENCRYPTION_INFO with cryptid 1
        let lines = output.components(separatedBy: "\n")
        var inEncryptionInfo = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("LC_ENCRYPTION_INFO") {
                inEncryptionInfo = true
            } else if inEncryptionInfo && trimmed.hasPrefix("cryptid") {
                let parts = trimmed.components(separatedBy: " ")
                if let cryptid = parts.last, cryptid == "1" {
                    return true
                }
                inEncryptionInfo = false
            }
        }
        return false
    }

    // MARK: - Segment Analysis

    private func analyzeSegments(at binaryURL: URL) async -> [SegmentInfo] {
        guard let output = await runProcess(
            executablePath: "/usr/bin/otool",
            arguments: ["-l", binaryURL.path]
        ) else { return [] }

        return parseSegments(from: output)
    }

    private func parseSegments(from output: String) -> [SegmentInfo] {
        var segments: [SegmentInfo] = []
        let lines = output.components(separatedBy: "\n")

        var currentSegmentName: String?
        var currentVMSize: Int64 = 0
        var currentVMAddr: UInt64 = 0
        var currentFileOff: UInt64 = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("segname") {
                // Save previous segment if exists
                if let name = currentSegmentName, currentVMSize > 0 {
                    segments.append(SegmentInfo(
                        name: name,
                        size: currentVMSize,
                        vmAddress: currentVMAddr,
                        fileOffset: currentFileOff
                    ))
                }
                // Parse new segment name
                let parts = trimmed.components(separatedBy: " ")
                currentSegmentName = parts.last
                currentVMSize = 0
                currentVMAddr = 0
                currentFileOff = 0
            } else if trimmed.hasPrefix("vmsize") {
                if let hexStr = trimmed.components(separatedBy: " ").last,
                   let value = parseHexOrDecimal(hexStr) {
                    currentVMSize = Int64(value)
                }
            } else if trimmed.hasPrefix("vmaddr") {
                if let hexStr = trimmed.components(separatedBy: " ").last,
                   let value = parseHexOrDecimal(hexStr) {
                    currentVMAddr = value
                }
            } else if trimmed.hasPrefix("fileoff") {
                if let hexStr = trimmed.components(separatedBy: " ").last,
                   let value = parseHexOrDecimal(hexStr) {
                    currentFileOff = value
                }
            }
        }

        // Don't forget the last segment
        if let name = currentSegmentName, currentVMSize > 0 {
            segments.append(SegmentInfo(
                name: name,
                size: currentVMSize,
                vmAddress: currentVMAddr,
                fileOffset: currentFileOff
            ))
        }

        return segments
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
    }

    private func parseHexOrDecimal(_ str: String) -> UInt64? {
        if str.hasPrefix("0x") {
            return UInt64(str.dropFirst(2), radix: 16)
        }
        return UInt64(str)
    }

    // MARK: - Stripped Check

    private func checkIfStripped(at binaryURL: URL) async -> Bool {
        guard let output = await runProcess(
            executablePath: "/usr/bin/file",
            arguments: [binaryURL.path]
        ) else { return false }

        return output.contains("stripped")
    }

    // MARK: - Static Module Extraction

    /// Extract Swift module names from binary symbols using nm
    private func extractStaticModules(from binaryURL: URL, textSegmentSize: Int64, isStripped: Bool) async -> [StaticModuleInfo] {
        // Don't try symbol extraction on stripped binaries
        if isStripped {
            return []
        }

        guard let output = await runProcess(
            executablePath: "/usr/bin/nm",
            arguments: [binaryURL.path]
        ) else { return [] }

        // Count symbols per Swift module
        var moduleCounts: [String: Int] = [:]
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            // Swift mangled symbols start with _$s followed by module name length and name
            // Example: _$s8DGCharts15ChartDataEntryC... -> module "DGCharts" (length 8)
            guard let range = line.range(of: "_$s") ?? line.range(of: " _$s") else { continue }

            let afterPrefix = String(line[range.upperBound...])
            guard let moduleName = parseSwiftModuleName(from: afterPrefix) else { continue }

            // Skip very short names (likely parsing errors)
            guard moduleName.count >= 2 else { continue }

            moduleCounts[moduleName, default: 0] += 1
        }

        // Filter out system modules and sort by count
        let totalSymbols = moduleCounts.values.reduce(0, +)

        var modules: [StaticModuleInfo] = []
        for (name, count) in moduleCounts {
            // Skip system modules
            if StaticModuleInfo.systemModules.contains(name) { continue }

            // Skip modules with very few symbols (likely noise)
            guard count >= 10 else { continue }

            // Estimate size based on symbol proportion
            let proportion = Double(count) / Double(max(totalSymbols, 1))
            let estimatedSize = Int64(proportion * Double(textSegmentSize))

            modules.append(StaticModuleInfo(
                name: name,
                symbolCount: count,
                estimatedSize: estimatedSize
            ))
        }

        return modules.sorted { $0.symbolCount > $1.symbolCount }
    }

    /// Parse Swift module name from mangled symbol
    /// Format: <length><name>... where length is decimal digits
    private func parseSwiftModuleName(from str: String) -> String? {
        var index = str.startIndex
        var lengthStr = ""

        // Read digits for length
        while index < str.endIndex, str[index].isNumber {
            lengthStr.append(str[index])
            index = str.index(after: index)
        }

        guard let length = Int(lengthStr), length > 0, length <= 50 else { return nil }

        // Read module name
        let endIndex = str.index(index, offsetBy: length, limitedBy: str.endIndex) ?? str.endIndex
        let moduleName = String(str[index..<endIndex])

        // Validate it looks like a module name (alphanumeric + underscore)
        guard moduleName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }

        return moduleName
    }

    // MARK: - Linked Libraries Extraction

    private func extractLinkedLibraries(from binaryURL: URL) async -> (embedded: [String], system: [String]) {
        guard let output = await runProcess(
            executablePath: "/usr/bin/otool",
            arguments: ["-L", binaryURL.path]
        ) else { return ([], []) }

        var embedded: [String] = []
        var system: [String] = []

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip the first line (binary path) and empty lines
            guard !trimmed.isEmpty else { continue }

            // Extract the library path (before version info)
            let libPath = trimmed.components(separatedBy: " (").first ?? trimmed

            if libPath.contains("@rpath") {
                // Embedded library - extract framework/dylib name
                // Format: @rpath/Name.framework/Name or @rpath/libName.dylib
                var name = libPath.replacingOccurrences(of: "@rpath/", with: "")

                if name.contains(".framework/") {
                    // Extract framework name (part before .framework/)
                    name = name.components(separatedBy: ".framework/").first ?? name
                } else if name.hasSuffix(".dylib") {
                    // Remove .dylib extension
                    name = String(name.dropLast(6))
                }

                // Remove any remaining path components
                name = name.components(separatedBy: "/").first ?? name

                embedded.append(name)
            } else if libPath.hasPrefix("/System/Library/Frameworks/") {
                // System framework
                let name = libPath
                    .replacingOccurrences(of: "/System/Library/Frameworks/", with: "")
                    .components(separatedBy: ".framework").first ?? ""
                if !name.isEmpty {
                    system.append(name)
                }
            }
        }

        return (Array(Set(embedded)).sorted(), Array(Set(system)).sorted())
    }

    // MARK: - SPM Package Detection

    /// SPM Package Product pattern: ModuleName_HASH_PackageProduct
    private let spmPackagePattern = try! NSRegularExpression(
        pattern: "^(.+)_-?[A-Fa-f0-9]+_PackageProduct$",
        options: []
    )

    private func detectSPMPackages(from linkedLibs: [String], frameworksURL: URL?) -> [SPMPackageInfo] {
        var packages: [SPMPackageInfo] = []

        for lib in linkedLibs {
            let range = NSRange(lib.startIndex..., in: lib)
            if let match = spmPackagePattern.firstMatch(in: lib, options: [], range: range),
               let nameRange = Range(match.range(at: 1), in: lib) {
                let packageName = String(lib[nameRange])
                let size = getFrameworkSize(named: lib, in: frameworksURL)

                packages.append(SPMPackageInfo(
                    name: packageName,
                    fullName: lib,
                    size: size
                ))
            }
        }

        return packages.sorted { $0.size > $1.size }
    }

    // MARK: - Framework Size Helper

    private func getFrameworkSize(named name: String, in frameworksURL: URL?) -> Int64 {
        guard let frameworksURL = frameworksURL else { return 0 }

        // Try .framework first
        let frameworkPath = frameworksURL.appendingPathComponent("\(name).framework")
        if let size = directorySize(at: frameworkPath) {
            return size
        }

        // Try .dylib
        let dylibPath = frameworksURL.appendingPathComponent("\(name).dylib")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dylibPath.path),
           let size = attrs[.size] as? Int64 {
            return size
        }

        // Try without extension (some packages have different structures)
        let plainPath = frameworksURL.appendingPathComponent(name)
        if let size = directorySize(at: plainPath) {
            return size
        }

        return 0
    }

    private func directorySize(at url: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        var totalSize: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])

        while let fileURL = enumerator?.nextObject() as? URL {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }

        return totalSize > 0 ? totalSize : nil
    }

    // MARK: - Process Helper

    private func runProcess(executablePath: String, arguments: [String]) async -> String? {
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            FileManager.default.createFile(atPath: tempFile.path, contents: nil)
            guard let fileHandle = FileHandle(forWritingAtPath: tempFile.path) else { return nil }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = fileHandle
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            try? fileHandle.close()

            let data = try Data(contentsOf: tempFile)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
