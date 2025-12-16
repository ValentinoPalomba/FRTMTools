import Foundation

enum AndroidToolchain {
    enum Tool {
        case aapt
        case aapt2
        case retrace
        case bundletool
    }

    struct Command {
        let executableURL: URL
        let argumentPrefix: [String]
    }

    private static let cacheQueue = DispatchQueue(label: "AndroidToolchain.cache", attributes: .concurrent)
    nonisolated(unsafe) private static var cachedCommands: [Tool: Command?] = [:]

    static func command(for tool: Tool) -> Command? {
        if let cached = cacheQueue.sync(execute: { cachedCommands[tool] }) {
            return cached ?? nil
        }
        let resolved = resolve(tool: tool, fm: FileManager.default, env: ProcessInfo.processInfo.environment)
        cacheQueue.async(flags: .barrier) {
            cachedCommands[tool] = resolved
        }
        return resolved
    }

    static func executableURL(for tool: Tool) -> URL? {
        command(for: tool)?.executableURL
    }

    private static func resolve(tool: Tool, fm: FileManager, env: [String: String]) -> Command? {
        switch tool {
        case .aapt:
            return resolveExecutableCommand(
                names: ["aapt"],
                envKeys: ["AAPT_PATH", "ANDROID_AAPT_PATH"],
                fm: fm,
                env: env
            )
        case .aapt2:
            return resolveExecutableCommand(
                names: ["aapt2"],
                envKeys: ["AAPT2_PATH", "ANDROID_AAPT2_PATH"],
                fm: fm,
                env: env
            )
        case .retrace:
            return resolveExecutableCommand(
                names: ["retrace"],
                envKeys: ["RETRACE_PATH", "ANDROID_RETRACE_PATH"],
                fm: fm,
                env: env
            )
        case .bundletool:
            return resolveBundletoolCommand(fm: fm, env: env)
        }
    }

    private static func resolveExecutableCommand(names: [String], envKeys: [String], fm: FileManager, env: [String: String]) -> Command? {
        guard let url = locateExecutable(named: names, envKeys: envKeys, fm: fm, env: env) else { return nil }
        return Command(executableURL: url, argumentPrefix: [])
    }

    private static func locateExecutable(named names: [String], envKeys: [String], fm: FileManager, env: [String: String]) -> URL? {
        let urls = candidateURLs(for: names, envKeys: envKeys, fm: fm, env: env)
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                continue
            }
            if fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func candidateURLs(for names: [String], envKeys: [String], fm: FileManager, env: [String: String]) -> [URL] {
        var candidates: [URL] = []
        let uniqueNames = names.removingDuplicates()

        func append(fromPath path: String, assumingDirectory: Bool = false) {
            let url = URL(fileURLWithPath: path, isDirectory: assumingDirectory)
            if assumingDirectory {
                for name in uniqueNames {
                    candidates.append(url.appendingPathComponent(name))
                }
            } else {
                candidates.append(url)
            }
        }

        // Explicit overrides
        for key in envKeys {
            guard let value = env[key], !value.isEmpty else { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: value, isDirectory: &isDir), isDir.boolValue {
                append(fromPath: value, assumingDirectory: true)
            } else {
                append(fromPath: value)
            }
        }

        // PATH entries
        if let pathEnv = env["PATH"], !pathEnv.isEmpty {
            for component in pathEnv.split(separator: ":") {
                let dir = String(component)
                for name in uniqueNames {
                    candidates.append(URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(name))
                }
            }
        }

        // Common user directories
        let home = fm.homeDirectoryForCurrentUser
        let userDirs: [URL] = [
            home.appendingPathComponent("bin", isDirectory: true),
            home.appendingPathComponent("homebrew/bin", isDirectory: true),
            home.appendingPathComponent("Library/Android/sdk/platform-tools", isDirectory: true)
        ]
        for dir in userDirs {
            for name in uniqueNames {
                candidates.append(dir.appendingPathComponent(name))
            }
        }

        // System-wide fallbacks
        let fallbackDirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/local/homebrew/bin",
            "/usr/bin"
        ]
        for dir in fallbackDirs {
            for name in uniqueNames {
                candidates.append(URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(name))
            }
        }

        // Build-tools directories
        candidates.append(contentsOf: searchBuildToolDirectories(names: uniqueNames, fm: fm, env: env))
        candidates.append(contentsOf: searchCommandLineToolDirectories(names: uniqueNames, fm: fm, env: env))

        return candidates.removingDuplicatePaths()
    }

    private static func searchBuildToolDirectories(names: [String], fm: FileManager, env: [String: String]) -> [URL] {
        var roots: [URL] = []
        let home = fm.homeDirectoryForCurrentUser
        roots.append(home.appendingPathComponent("Library/Android/sdk/build-tools", isDirectory: true))
        roots.append(home.appendingPathComponent("Android/Sdk/build-tools", isDirectory: true))
        roots.append(home.appendingPathComponent("Library/Developer/Xamarin/android-sdk-macosx/build-tools", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/Library/Android/sdk/build-tools", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/usr/local/share/android-sdk/build-tools", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/usr/local/opt/android-sdk/build-tools", isDirectory: true))

        if let androidHome = env["ANDROID_HOME"], !androidHome.isEmpty {
            roots.append(URL(fileURLWithPath: androidHome, isDirectory: true).appendingPathComponent("build-tools", isDirectory: true))
        }
        if let androidSDKRoot = env["ANDROID_SDK_ROOT"], !androidSDKRoot.isEmpty {
            roots.append(URL(fileURLWithPath: androidSDKRoot, isDirectory: true).appendingPathComponent("build-tools", isDirectory: true))
        }

        var results: [URL] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard let versionDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
            let sorted = versionDirs.sorted {
                $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
            }
            for dir in sorted {
                for name in names {
                    results.append(dir.appendingPathComponent(name))
                }
            }
        }
        return results
    }

    private static func searchCommandLineToolDirectories(names: [String], fm: FileManager, env: [String: String]) -> [URL] {
        var roots: [URL] = []
        let home = fm.homeDirectoryForCurrentUser
        roots.append(home.appendingPathComponent("Library/Android/sdk/cmdline-tools", isDirectory: true))
        roots.append(home.appendingPathComponent("Android/Sdk/cmdline-tools", isDirectory: true))

        if let androidHome = env["ANDROID_HOME"], !androidHome.isEmpty {
            roots.append(URL(fileURLWithPath: androidHome, isDirectory: true).appendingPathComponent("cmdline-tools", isDirectory: true))
        }
        if let androidSDKRoot = env["ANDROID_SDK_ROOT"], !androidSDKRoot.isEmpty {
            roots.append(URL(fileURLWithPath: androidSDKRoot, isDirectory: true).appendingPathComponent("cmdline-tools", isDirectory: true))
        }

        var results: [URL] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard let toolDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
            for dir in toolDirs {
                let bin = dir.appendingPathComponent("bin", isDirectory: true)
                for name in names {
                    results.append(bin.appendingPathComponent(name))
                }
            }
        }
        return results
    }

    // MARK: - Bundletool

    private static func resolveBundletoolCommand(fm: FileManager, env: [String: String]) -> Command? {
        let candidates = bundletoolCandidatePaths(fm: fm, env: env)
        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue { continue }

            if url.pathExtension.lowercased() == "jar" || candidate.lowercased().hasSuffix(".jar") {
                guard let javaURL = locateJavaExecutable(fm: fm, env: env) else {
                    continue
                }
                return Command(executableURL: javaURL, argumentPrefix: ["-jar", url.path])
            }

            if fm.isExecutableFile(atPath: url.path) {
                return Command(executableURL: url, argumentPrefix: [])
            }
        }

        if let url = locateExecutable(named: ["bundletool"], envKeys: [], fm: fm, env: env) {
            return Command(executableURL: url, argumentPrefix: [])
        }

        return nil
    }

    private static func bundletoolCandidatePaths(fm: FileManager, env: [String: String]) -> [String] {
        var candidates: [String] = []
        let explicitKeys = ["BUNDLETOOL_PATH", "BUNDLETOOL_JAR"]
        for key in explicitKeys {
            if let value = env[key], !value.isEmpty {
                candidates.append(value)
            }
        }

        let searchNames = ["bundletool", "bundletool-all.jar", "bundletool.jar"]
        let cwd = fm.currentDirectoryPath
        for name in searchNames {
            candidates.append(cwd + "/\(name)")
        }

        let home = fm.homeDirectoryForCurrentUser
        let homeBin = home.appendingPathComponent("bin").path
        for name in searchNames {
            candidates.append(homeBin + "/\(name)")
        }
        let userHomebrewBin = home.appendingPathComponent("homebrew/bin").path
        for name in searchNames {
            candidates.append(userHomebrewBin + "/\(name)")
        }

        let defaultDirectories = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/local/homebrew/bin",
            "/usr/bin"
        ]
        for directory in defaultDirectories {
            for name in searchNames {
                candidates.append(directory + "/\(name)")
            }
        }

        if let pathEnv = env["PATH"] {
            for component in pathEnv.split(separator: ":") {
                let path = String(component)
                for name in searchNames {
                    candidates.append(path + "/\(name)")
                }
            }
        }

        return candidates.removingDuplicates()
    }

    private static func locateJavaExecutable(fm: FileManager, env: [String: String]) -> URL? {
        if let javaHome = env["JAVA_HOME"], !javaHome.isEmpty {
            let candidate = URL(fileURLWithPath: javaHome, isDirectory: true)
            let bin = candidate.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("java")
            if fm.isExecutableFile(atPath: bin.path) {
                return bin
            }
        }

        let javaBinary = URL(fileURLWithPath: "/usr/bin/java")
        if fm.isExecutableFile(atPath: javaBinary.path) {
            return javaBinary
        }
        return nil
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Array where Element == URL {
    func removingDuplicatePaths() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            let path = url.standardizedFileURL.path
            if seen.contains(path) { return false }
            seen.insert(path)
            return true
        }
    }
}

// MARK: - Bundletool integration

struct BundletoolSizeEstimates {
    let installBytes: Int64
    let downloadBytes: Int64?
}

final class BundletoolInvoker: @unchecked Sendable {
    enum BundletoolError: LocalizedError {
        case executableNotFound
        case javaRuntimeMissing
        case commandFailed(arguments: [String], stderr: String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "bundletool executable or jar not found. Set BUNDLETOOL_PATH or ensure bundletool is on your PATH."
            case .javaRuntimeMissing:
                return "Unable to locate a Java runtime for bundletool."
            case .commandFailed(let arguments, let stderr):
                let joined = arguments.joined(separator: " ")
                if stderr.isEmpty {
                    return "bundletool command failed: \(joined)"
                } else {
                    return "bundletool command failed: \(joined) — \(stderr)"
                }
            }
        }
    }

    private struct Invocation {
        let executableURL: URL
        let argumentPrefix: [String]
    }

    private struct ProcessOutput {
        let stdout: String
        let stderr: String
    }

    private static let sizeLineRegex = try! NSRegularExpression(
        pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*([A-Za-z]+)(?:\s*\((min|max)\))?"#,
        options: [.caseInsensitive]
    )

    nonisolated(unsafe) private static var cachedInvocation: Invocation?

    private let fm = FileManager.default

    var isAvailable: Bool {
        currentInvocation() != nil
    }

    func buildAPKSet(bundleURL: URL, outputURL: URL) throws {
        try run(arguments: [
            "build-apks",
            "--bundle=\(bundleURL.path)",
            "--output=\(outputURL.path)",
            "--overwrite"
        ])
    }

    func calculateInstallSize(apksArchiveURL: URL, deviceSpecURL: URL?) -> BundletoolSizeEstimates? {
        var baseArguments = [
            "get-size",
            "total",
            "--apks=\(apksArchiveURL.path)"
        ]
        if let deviceSpecURL {
            baseArguments.append("--device-spec=\(deviceSpecURL.path)")
        }

        do {
            let baseOutput = try run(arguments: baseArguments)
            var estimates = parseSizeEstimates(from: baseOutput.stdout)
            var rawOutputs: [String] = []
            if estimates == nil {
                rawOutputs.append(baseOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            if estimates?.downloadBytes == nil {
                var dimensionArguments = baseArguments
                dimensionArguments.append("--dimensions=ALL")
                let dimensionOutput = try run(arguments: dimensionArguments)
                rawOutputs.append(dimensionOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                if let csvEstimates = parseCSVSizeEstimates(from: dimensionOutput.stdout) {
                    if let existing = estimates {
                        estimates = BundletoolSizeEstimates(
                            installBytes: existing.installBytes,
                            downloadBytes: csvEstimates.downloadBytes
                        )
                    } else {
                        estimates = csvEstimates
                    }
                }
            }

            if let estimates, estimates.installBytes == estimates.downloadBytes || estimates.downloadBytes == nil {
                if !rawOutputs.isEmpty {
                    print("ℹ️ bundletool raw size outputs for diagnostics:\n\(rawOutputs.joined(separator: "\n---\n"))")
                }
            }

            return estimates
        } catch {
            print("⚠️ bundletool size estimation failed: \(error)")
            return nil
        }
    }

    func generateDeviceSpec(to url: URL) -> Bool {
        do {
            try run(arguments: [
                "get-device-spec",
                "--output=\(url.path)"
            ])
            return true
        } catch {
            print("⚠️ bundletool get-device-spec failed: \(error)")
            return false
        }
    }

    func writeDefaultDeviceSpec(to url: URL) throws {
        let spec: [String: Any] = [
            "supportedAbis": ["arm64-v8a"],
            "supportedLocales": ["en"],
            "screenDensity": 480,
            "sdkVersion": 34
        ]
        let data = try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted])
        try data.write(to: url, options: [.atomic])
    }

    func dumpManifest(forModule moduleName: String, bundleURL: URL) -> String? {
        do {
            let output = try run(arguments: [
                "dump",
                "manifest",
                "--bundle=\(bundleURL.path)",
                "--module=\(moduleName)"
            ])
            return output.stdout
        } catch {
            print("⚠️ bundletool dump manifest failed for module \(moduleName): \(error)")
            return nil
        }
    }

    private func parseSizeEstimates(from text: String) -> BundletoolSizeEstimates? {
        if let csvEstimates = parseCSVSizeEstimates(from: text) {
            return csvEstimates
        }
        let install = parseSizeLine(named: "total install size", in: text)
        guard let install else { return nil }
        let download = parseSizeLine(named: "total download size", in: text)
        return BundletoolSizeEstimates(installBytes: install, downloadBytes: download)
    }

    private func parseCSVSizeEstimates(from text: String) -> BundletoolSizeEstimates? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let header = lines.first?.uppercased(),
              header.contains("MIN"),
              header.contains("MAX"),
              lines.count >= 2 else {
            return nil
        }
        let dataLine = lines[1]
        let components = dataLine.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count >= 2 else { return nil }
        let lastTwo = components.suffix(2)
        guard lastTwo.count == 2,
              let minBytes = asBytes(lastTwo[lastTwo.startIndex]),
              let maxBytes = asBytes(lastTwo[lastTwo.index(after: lastTwo.startIndex)]) else {
            return nil
        }
        let installBytes = max(minBytes, maxBytes)
        return BundletoolSizeEstimates(installBytes: installBytes, downloadBytes: installBytes)
    }

    private func asBytes<S: StringProtocol>(_ value: S) -> Int64? {
        let sanitized = value.replacingOccurrences(of: ",", with: "")
        return Int64(sanitized)
    }

    private func parseSizeLine(named key: String, in text: String) -> Int64? {
        let lowerKey = key.lowercased()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().contains(lowerKey) {
                if let bytes = extractBytes(from: line) {
                    return bytes
                }
            }
        }
        return nil
    }

    private func extractBytes(from line: String) -> Int64? {
        let nsLine = line as NSString
        let matches = BundletoolInvoker.sizeLineRegex.matches(
            in: line,
            options: [],
            range: NSRange(location: 0, length: nsLine.length)
        )

        var exact: Int64?
        var maxValue: Int64?
        var minValue: Int64?

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let valueString = nsLine.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
            let unitString = nsLine.substring(with: match.range(at: 2))
            guard let bytes = convertToBytes(valueString: valueString, unit: unitString) else { continue }

            if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                let qualifier = nsLine.substring(with: match.range(at: 3)).lowercased()
                if qualifier == "max" {
                    maxValue = bytes
                } else if qualifier == "min" {
                    minValue = bytes
                } else {
                    exact = bytes
                }
            } else {
                exact = bytes
            }
        }

        return exact ?? maxValue ?? minValue
    }

    private func convertToBytes(valueString: String, unit: String) -> Int64? {
        guard let value = Double(valueString) else { return nil }
        let multiplier: Double
        switch unit.lowercased() {
        case "b", "byte", "bytes":
            multiplier = 1
        case "kb", "kib":
            multiplier = 1_024
        case "mb", "mib":
            multiplier = 1_048_576
        case "gb", "gib":
            multiplier = 1_073_741_824
        default:
            multiplier = 1
        }
        return Int64((value * multiplier).rounded())
    }

    @discardableResult
    private func run(arguments: [String]) throws -> ProcessOutput {
        guard let invocation = currentInvocation() else {
            throw BundletoolError.executableNotFound
        }

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.argumentPrefix + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw BundletoolError.commandFailed(arguments: arguments, stderr: stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return ProcessOutput(stdout: stdoutString, stderr: stderrString)
    }

    private func currentInvocation() -> Invocation? {
        if let cached = BundletoolInvoker.cachedInvocation {
            return cached
        }
        guard let command = AndroidToolchain.command(for: .bundletool) else {
            return nil
        }
        let invocation = Invocation(executableURL: command.executableURL, argumentPrefix: command.argumentPrefix)
        BundletoolInvoker.cachedInvocation = invocation
        return invocation
    }
}
