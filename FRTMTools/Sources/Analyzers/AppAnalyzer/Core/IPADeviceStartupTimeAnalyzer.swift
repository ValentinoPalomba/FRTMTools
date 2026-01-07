import Foundation

// MARK: - Models

/// Options for startup time analysis
public struct StartupTimeAnalysisOptions: Sendable {
    /// Number of times to launch the app and measure startup time
    public let launchCount: Int
    /// Whether to capture logs automatically (macOS only)
    public let captureLogsAutomatically: Bool

    public init(launchCount: Int = 3, captureLogsAutomatically: Bool = false) {
        self.launchCount = launchCount
        self.captureLogsAutomatically = captureLogsAutomatically
    }
}

/// Result of startup time analysis
public struct StartupTimeAnalysisResult: Sendable, Codable {
    public let appName: String
    public let bundleIdentifier: String
    /// Results from log parsing (if logs were imported)
    public let logBasedResults: [StartupTimeResult]
    /// Average startup time from log-based measurements
    public let averageStartupTime: TimeInterval?
    /// Warnings collected during analysis
    public let warnings: [String]

    public var formattedAverageTime: String {
        guard let avg = averageStartupTime else {
            return "N/A"
        }
        if avg < 1.0 {
            let ms = Int((avg * 1000).rounded())
            return "\(ms) ms"
        }
        return avg.formatted(.number.precision(.fractionLength(2))) + " s"
    }

    public var minStartupTime: TimeInterval? {
        logBasedResults.compactMap { $0.startupDuration }.min()
    }

    public var maxStartupTime: TimeInterval? {
        logBasedResults.compactMap { $0.startupDuration }.max()
    }
}

// MARK: - Analyzer Errors

public enum StartupTimeAnalysisError: LocalizedError, Sendable {
    case invalidIPAPath
    case simulatorNotFound
    case appBundleNotFound
    case bundleIdentifierNotFound
    case logImportFailed(String)
    case shellCommandFailed(command: String, exitCode: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidIPAPath:
            return "The path to the .ipa file is invalid or the file does not exist."
        case .simulatorNotFound:
            return "Could not find an available iPhone simulator."
        case .appBundleNotFound:
            return "Could not find an .app bundle inside the IPA archive."
        case .bundleIdentifierNotFound:
            return "Could not determine the app's bundle identifier."
        case .logImportFailed(let message):
            return "Failed to import log file: \(message)"
        case .shellCommandFailed(let command, let exitCode, let message):
            return "The shell command '\(command)' failed with code \(exitCode): \(message)"
        }
    }
}

// MARK: - Main Analyzer

/// Analyzes app startup time by importing console logs
public final class IPADeviceStartupTimeAnalyzer {

    private let logParser = StartupLogParser()

    public init() {}

    /// Analyze startup time from imported log files
    /// - Parameters:
    ///   - ipaPath: Path to the .ipa file
    ///   - logPaths: Array of paths to console log files (.txt or .log)
    ///   - progress: Progress callback
    /// - Returns: Startup time analysis result
    public func analyzeFromLogs(
        ipaPath: String,
        logPaths: [String],
        progress: (String) -> Void
    ) async throws -> StartupTimeAnalysisResult {
        let normalizedIPAPath = sanitizePath(ipaPath)
        guard FileManager.default.fileExists(atPath: normalizedIPAPath) else {
            throw StartupTimeAnalysisError.invalidIPAPath
        }

        progress("📦 Extracting app info...")
        let (appName, bundleID) = try await extractAppInfo(from: normalizedIPAPath)
        progress("🔍 Found app: \(appName) (\(bundleID))")

        var results: [StartupTimeResult] = []
        var warnings: [String] = []

        for (index, logPath) in logPaths.enumerated() {
            progress("📖 Parsing log file \(index + 1)/\(logPaths.count)...")
            do {
                let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
                let logResults = try logParser.parseAll(logContent: logContent, bundleIdentifier: bundleID)

                let successfulResults = logResults.filter { $0.startupDuration != nil }
                let failedResults = logResults.filter { $0.startupDuration == nil }

                results.append(contentsOf: logResults)
                logResults.forEach { warnings.append(contentsOf: $0.warnings) }

                if successfulResults.count > 0 {
                    progress("   ✅ Found \(successfulResults.count) launch(es) in this log")
                    for result in successfulResults {
                        progress("      • Launch: \(result.formattedDuration)")
                    }
                }

                if failedResults.count > 0 {
                    progress("   ⚠️ \(failedResults.count) launch(es) failed or incomplete")
                }
            } catch {
                progress("   ⚠️ Error parsing log: \(error.localizedDescription)")
                warnings.append("Failed to parse log: \(logPath)")
            }
        }

        // Calculate average
        let durations = results.compactMap { $0.startupDuration }
        let average = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)

        // Add summary information
        if !results.isEmpty {
            let successfulLaunches = results.filter { $0.startupDuration != nil }.count
            let failedLaunches = results.count - successfulLaunches

            if successfulLaunches > 0 {
                progress("✅ Successfully measured \(successfulLaunches) launch(es)")
            }
            if failedLaunches > 0 {
                progress("⚠️ Failed to measure \(failedLaunches) launch(es)")
                warnings.append("Could not measure startup time for \(failedLaunches) of \(results.count) launches. Check logs for details.")
            }
        }

        progress("✨ Analysis complete!")

        return StartupTimeAnalysisResult(
            appName: appName,
            bundleIdentifier: bundleID,
            logBasedResults: results,
            averageStartupTime: average,
            warnings: warnings
        )
    }

    // MARK: - Private Helpers

    private func extractAppInfo(from ipaPath: String) async throws -> (appName: String, bundleID: String) {
        // Check if it's already a .app bundle
        if ipaPath.hasSuffix(".app") || ipaPath.hasSuffix(".app/") {
            return try extractInfoFromAppBundle(ipaPath)
        }

        // Otherwise, treat it as an IPA file
        let tempDir = createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Unzip the IPA
        try await shell(cmd: "/usr/bin/unzip", args: ["-q", ipaPath, "-d", tempDir.path])

        // Find the .app bundle
        let payloadDir = tempDir.appendingPathComponent("Payload")
        guard let appFileName = try? FileManager.default.contentsOfDirectory(atPath: payloadDir.path)
            .first(where: { $0.hasSuffix(".app") }) else {
            throw StartupTimeAnalysisError.appBundleNotFound
        }

        let appPath = payloadDir.appendingPathComponent(appFileName)
        return try extractInfoFromAppBundle(appPath.path)
    }

    private func extractInfoFromAppBundle(_ appPath: String) throws -> (appName: String, bundleID: String) {
        let appURL = URL(fileURLWithPath: appPath)
        let appName = appURL.deletingPathExtension().lastPathComponent

        // Read Info.plist to get bundle identifier
        let infoPlistPath = appURL.appendingPathComponent("Info.plist")
        guard let plistData = try? Data(contentsOf: infoPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String else {
            throw StartupTimeAnalysisError.bundleIdentifierNotFound
        }

        return (appName, bundleID)
    }

    private func sanitizePath(_ path: String) -> String {
        if let url = URL(string: path), url.scheme != nil {
            if url.isFileURL {
                return url.path
            }
        }
        let decoded = path.removingPercentEncoding ?? path
        if decoded.hasPrefix("~") {
            return (decoded as NSString).expandingTildeInPath
        }
        return decoded
    }

    private func createTempDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    @discardableResult
    private func shell(cmd: String, args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "No error output"
            throw StartupTimeAnalysisError.shellCommandFailed(
                command: "\(cmd) \(args.joined(separator: " "))",
                exitCode: process.terminationStatus,
                message: errorMessage
            )
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
