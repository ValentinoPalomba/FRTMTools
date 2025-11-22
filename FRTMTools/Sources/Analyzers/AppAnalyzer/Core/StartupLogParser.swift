import Foundation

// MARK: - Models

/// Result of parsing startup logs
public struct StartupTimeResult: Sendable, Codable {
    public let bundleIdentifier: String
    public let processID: Int?
    public let bootstrapTime: Date?
    public let activationTime: Date?
    public let startupDuration: TimeInterval?
    public let warnings: [String]

    /// Human-readable startup duration
    public var formattedDuration: String {
        guard let duration = startupDuration else {
            return "N/A"
        }
        if duration < 1.0 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }
}

// MARK: - Parser

/// Parses iOS console logs to extract app startup times
public final class StartupLogParser {

    public init() {}

    /// Parse a log file to extract startup time for a specific bundle identifier
    /// - Parameters:
    ///   - logPath: Path to the log file (.txt or .log)
    ///   - bundleIdentifier: Bundle identifier to search for (e.g., "com.netflix.Netflix")
    /// - Returns: Startup time result
    public func parse(logPath: String, bundleIdentifier: String) throws -> StartupTimeResult {
        guard FileManager.default.fileExists(atPath: logPath) else {
            throw StartupLogError.logFileNotFound(path: logPath)
        }

        let content = try String(contentsOfFile: logPath, encoding: .utf8)
        return try parse(logContent: content, bundleIdentifier: bundleIdentifier)
    }

    /// Parse log content to extract all startup times (supports multiple launches)
    /// - Parameters:
    ///   - logContent: Raw log content
    ///   - bundleIdentifier: Bundle identifier to search for
    /// - Returns: Array of startup time results (one per launch)
    public func parseAll(logContent: String, bundleIdentifier: String) throws -> [StartupTimeResult] {
        let lines = logContent.components(separatedBy: .newlines)

        // Check if logs contain any iOS-related content
        let hasIOSContent = lines.contains { line in
            line.contains("SpringBoard") ||
            line.contains("runningboardd") ||
            line.contains("simctl") ||
            line.contains("devicectl") ||
            line.contains("Bootstrap success")
        }

        if !hasIOSContent && lines.count > 10 {
            throw StartupLogError.parsingFailed(message: "These logs don't appear to be iOS device/simulator logs.\n\nPlease ensure you:\n1. Launched the app on an iOS simulator or device\n2. Captured logs from Console.app while filtering for the device\n3. Exported the logs that include app launch events\n\nTip: Look for logs containing 'SpringBoard', 'Bootstrap success', or the app's bundle identifier.")
        }

        // Find all bootstrap events
        var bootstrapEvents: [(timestamp: Date, pid: Int)] = []
        for line in lines {
            if line.contains(bundleIdentifier) && line.contains("Bootstrap success") {
                if let (timestamp, pid) = parseBootstrapLine(line, bundleIdentifier: bundleIdentifier) {
                    bootstrapEvents.append((timestamp, pid))
                }
            }
        }

        // For each bootstrap, find the corresponding activation
        var results: [StartupTimeResult] = []
        for (index, bootstrap) in bootstrapEvents.enumerated() {
            var activationTime: Date?
            var warnings: [String] = []

            // Define search window: from this bootstrap to next bootstrap (or end of log)
            let searchStartTime = bootstrap.timestamp
            let searchEndTime = index < bootstrapEvents.count - 1 ? bootstrapEvents[index + 1].timestamp : Date.distantFuture

            // Search for activation within this window
            for line in lines {
                guard let lineTimestamp = parseTimestamp(from: line) else { continue }

                // Only look within the window for this specific launch
                guard lineTimestamp > searchStartTime && lineTimestamp < searchEndTime else { continue }

                // Look for deactivation reasons removed (this indicates app became active)
                // Note: The log may use process name instead of bundle ID, so we don't filter by bundle ID here
                if line.contains("Deactivation reason removed: 5") &&
                   line.contains("deactivation reasons:") &&
                   line.contains("-> 0") {
                    activationTime = lineTimestamp
                    break
                }

                // Also look for applicationDidBecomeActive as backup
                if line.contains(bundleIdentifier) &&
                   line.contains("applicationDidBecomeActive") {
                    if activationTime == nil {
                        activationTime = lineTimestamp
                    }
                }
            }

            // Check for hang warnings in this window
            for line in lines {
                guard let lineTimestamp = parseTimestamp(from: line) else { continue }
                guard lineTimestamp > searchStartTime && lineTimestamp < searchEndTime else { continue }

                if line.contains(bundleIdentifier) && line.contains("Hang detected") {
                    warnings.append("Hang detected during startup")
                    break
                }
            }

            // Calculate duration
            var duration: TimeInterval?
            if let activation = activationTime {
                duration = activation.timeIntervalSince(bootstrap.timestamp)
            }

            // Add diagnostic information
            if activationTime == nil {
                warnings.append("App was launched (bootstrap found) but never became active. The app may have crashed during startup.")
            }

            results.append(StartupTimeResult(
                bundleIdentifier: bundleIdentifier,
                processID: bootstrap.pid,
                bootstrapTime: bootstrap.timestamp,
                activationTime: activationTime,
                startupDuration: duration,
                warnings: warnings
            ))
        }

        if results.isEmpty {
            var warnings: [String] = []
            warnings.append("No app launch event (bootstrap) found in logs. Make sure the logs capture the actual app launch.")
            results.append(StartupTimeResult(
                bundleIdentifier: bundleIdentifier,
                processID: nil,
                bootstrapTime: nil,
                activationTime: nil,
                startupDuration: nil,
                warnings: warnings
            ))
        }

        return results
    }

    /// Parse log content to extract startup time (returns first launch only)
    /// - Parameters:
    ///   - logContent: Raw log content
    ///   - bundleIdentifier: Bundle identifier to search for
    /// - Returns: Startup time result
    public func parse(logContent: String, bundleIdentifier: String) throws -> StartupTimeResult {
        let allResults = try parseAll(logContent: logContent, bundleIdentifier: bundleIdentifier)
        return allResults.first ?? StartupTimeResult(
            bundleIdentifier: bundleIdentifier,
            processID: nil,
            bootstrapTime: nil,
            activationTime: nil,
            startupDuration: nil,
            warnings: ["No launch events found"]
        )
    }

    /// DEPRECATED: Use parseAll instead for better multi-launch support
    private func parseOld(logContent: String, bundleIdentifier: String) throws -> StartupTimeResult {
        let lines = logContent.components(separatedBy: .newlines)

        // Check if logs contain any iOS-related content
        let hasIOSContent = lines.contains { line in
            line.contains("SpringBoard") ||
            line.contains("runningboardd") ||
            line.contains("simctl") ||
            line.contains("devicectl") ||
            line.contains("Bootstrap success")
        }

        if !hasIOSContent && lines.count > 10 {
            throw StartupLogError.parsingFailed(message: "These logs don't appear to be iOS device/simulator logs.\n\nPlease ensure you:\n1. Launched the app on an iOS simulator or device\n2. Captured logs from Console.app while filtering for the device\n3. Exported the logs that include app launch events\n\nTip: Look for logs containing 'SpringBoard', 'Bootstrap success', or the app's bundle identifier.")
        }

        var bootstrapTime: Date?
        var activationTime: Date?
        var processID: Int?
        var warnings: [String] = []

        // Search for bootstrap success
        for line in lines {
            if line.contains(bundleIdentifier) && line.contains("Bootstrap success") {
                if let (timestamp, pid) = parseBootstrapLine(line, bundleIdentifier: bundleIdentifier) {
                    bootstrapTime = timestamp
                    processID = pid
                    break
                }
            }
        }

        // If we found a bootstrap, search for activation (deactivation reasons removed)
        if bootstrapTime != nil {
            for line in lines {
                // Look for the app becoming fully active
                // Pattern: "Deactivation reason removed: 5; deactivation reasons: 32 -> 0"
                if line.contains("Deactivation reason removed: 5") &&
                   line.contains("deactivation reasons:") &&
                   line.contains("-> 0") {
                    if let timestamp = parseTimestamp(from: line) {
                        // Verify this is after bootstrap time
                        if let bootstrap = bootstrapTime, timestamp > bootstrap {
                            activationTime = timestamp
                            break
                        }
                    }
                }

                // Also look for applicationDidBecomeActive
                if line.contains(bundleIdentifier) &&
                   line.contains("applicationDidBecomeActive") {
                    if let timestamp = parseTimestamp(from: line) {
                        if let bootstrap = bootstrapTime, timestamp > bootstrap {
                            // Only use this if we don't already have an activation time
                            if activationTime == nil {
                                activationTime = timestamp
                            }
                        }
                    }
                }
            }
        }

        // Check for hang warnings
        for line in lines {
            if line.contains(bundleIdentifier) && line.contains("Hang detected") {
                warnings.append("Hang detected during startup")
                break
            }
        }

        // Calculate duration
        var duration: TimeInterval?
        if let bootstrap = bootstrapTime, let activation = activationTime {
            duration = activation.timeIntervalSince(bootstrap)
        }

        // Add helpful diagnostic information if we couldn't find complete startup info
        if bootstrapTime != nil && activationTime == nil {
            warnings.append("App was launched (bootstrap found) but never became active. The app may have crashed during startup.")
        } else if bootstrapTime == nil {
            warnings.append("No app launch event (bootstrap) found in logs. Make sure the logs capture the actual app launch.")
        }

        return StartupTimeResult(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            bootstrapTime: bootstrapTime,
            activationTime: activationTime,
            startupDuration: duration,
            warnings: warnings
        )
    }

    // MARK: - Private Helpers

    private func parseBootstrapLine(_ line: String, bundleIdentifier: String) -> (timestamp: Date, pid: Int)? {
        guard let timestamp = parseTimestamp(from: line) else { return nil }

        // Try to extract PID from patterns like "[app<com.bundle.id>:123]"
        let pidPattern = "\\[app<[^>]+>:(\\d+)\\]"
        if let regex = try? NSRegularExpression(pattern: pidPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let pidRange = Range(match.range(at: 1), in: line),
           let pid = Int(line[pidRange]) {
            return (timestamp, pid)
        }

        return nil
    }

    private func parseTimestamp(from line: String) -> Date? {
        // iOS console log format: "default	22:32:18.393197+0100	..."
        // Pattern: HH:mm:ss.SSSSSS+ZZZZ or HH:mm:ss.SSSSSS-ZZZZ
        let pattern = "(\\d{2}):(\\d{2}):(\\d{2})\\.(\\d{6})([+-]\\d{4})"

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let timestampRange = Range(match.range, in: line) else {
            return nil
        }

        let timestampStr = String(line[timestampRange])

        // Parse the components
        let components = timestampStr.split(separator: ":")
        guard components.count >= 3 else { return nil }

        let hourStr = String(components[0])
        let minuteStr = String(components[1])
        let secondAndMicrosStr = String(components[2])

        // Split seconds and microseconds+timezone
        let secondComponents = secondAndMicrosStr.split(separator: ".")
        guard secondComponents.count == 2 else { return nil }

        let secondStr = String(secondComponents[0])
        let microAndTZStr = String(secondComponents[1])

        // Extract microseconds (6 digits) and timezone
        guard microAndTZStr.count >= 6 else { return nil }
        let microStr = String(microAndTZStr.prefix(6))

        guard let hour = Int(hourStr),
              let minute = Int(minuteStr),
              let second = Int(secondStr),
              let micro = Int(microStr) else {
            return nil
        }

        // Use today's date with the parsed time
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        var dateComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = second
        dateComponents.nanosecond = micro * 1000 // Convert microseconds to nanoseconds

        return calendar.date(from: dateComponents)
    }
}

// MARK: - Errors

public enum StartupLogError: LocalizedError, Sendable {
    case logFileNotFound(path: String)
    case parsingFailed(message: String)
    case noBundleIdentifierFound

    public var errorDescription: String? {
        switch self {
        case .logFileNotFound(let path):
            return "Log file not found at path: \(path)"
        case .parsingFailed(let message):
            return "Failed to parse log: \(message)"
        case .noBundleIdentifierFound:
            return "Could not find bundle identifier in log"
        }
    }
}
