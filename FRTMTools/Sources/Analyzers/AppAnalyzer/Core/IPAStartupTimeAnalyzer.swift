import Foundation

/// Analyzes app startup time by installing on a device/simulator and capturing logs
public final class IPAStartupTimeAnalyzer {

    private let logParser = StartupLogParser()

    public init() {}

    // MARK: - Public Install-Only Methods

    /// Install app on device/simulator without launching
    /// - Parameters:
    ///   - ipaPath: Path to the .ipa file or .app bundle
    ///   - deviceUDID: Device or simulator UDID
    ///   - progress: Progress callback
    public func installOnly(
        ipaPath: String,
        deviceUDID: String,
        progress: (String) -> Void
    ) async throws -> (appName: String, bundleID: String) {
        let normalizedIPAPath = sanitizePath(ipaPath)
        guard FileManager.default.fileExists(atPath: normalizedIPAPath) else {
            throw StartupTimeAnalysisError.invalidIPAPath
        }

        progress("📦 Extracting app info...")
        let (appName, bundleID) = try await extractAppInfo(from: normalizedIPAPath)
        progress("🔍 Found app: \(appName) (\(bundleID))")

        // Check if it's a simulator
        let isSimulator = try await checkIfSimulator(udid: deviceUDID)

        if isSimulator {
            progress("📱 Preparing simulator...")
            try await prepareSimulator(udid: deviceUDID, progress: progress)
        }

        progress("📲 Installing app on \(isSimulator ? "simulator" : "device")...")
        try await installApp(ipaPath: normalizedIPAPath, deviceUDID: deviceUDID)

        progress("✅ Installation complete!")

        return (appName, bundleID)
    }

    // MARK: - Private Helpers

    private func checkIfSimulator(udid: String) async throws -> Bool {
        // List all simulators and check if UDID matches
        let output = try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "list", "devices"])
        return output.contains(udid)
    }

    private func prepareSimulator(udid: String, progress: (String) -> Void) async throws {
        // Check if simulator is booted
        let listOutput = try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "list", "devices", "booted"])

        if !listOutput.contains(udid) {
            progress("   Booting simulator...")
            try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "boot", udid])
            // Wait for simulator to boot
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        } else {
            progress("   Simulator already booted")
        }
    }

    private func installApp(ipaPath: String, deviceUDID: String) async throws {
        let cleanPath = ipaPath.hasSuffix("/") ? String(ipaPath.dropLast()) : ipaPath
        let isSimulator = try await checkIfSimulator(udid: deviceUDID)

        if isSimulator {
            // For simulators, use simctl (works with both .ipa and .app)
            try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "install", deviceUDID, cleanPath])
        } else {
            // For physical devices, we need an IPA file
            var ipaToInstall = cleanPath
            var tempIPA: URL?

            // If we have a .app bundle, create a temporary IPA
            if cleanPath.hasSuffix(".app") {
                ipaToInstall = try await createTemporaryIPA(from: cleanPath)
                tempIPA = URL(fileURLWithPath: ipaToInstall)
            }

            defer {
                // Clean up temporary IPA if we created one
                if let tempIPA = tempIPA {
                    try? FileManager.default.removeItem(at: tempIPA)
                }
            }

            // Try devicectl first (iOS 17+)
            do {
                try await shell(cmd: "/usr/bin/xcrun", args: ["devicectl", "device", "install", "app", "--device", deviceUDID, ipaToInstall])
            } catch {
                // If devicectl fails, show helpful error
                throw StartupTimeAnalysisError.shellCommandFailed(
                    command: "devicectl device install app",
                    exitCode: -1,
                    message: "Failed to install on physical device. This feature requires:\n\n1. iOS 17 or later on the device\n2. The device to be connected and trusted\n3. Developer Mode enabled on the device\n\nAlternatively, use a simulator or import logs manually.\n\nOriginal error: \(error.localizedDescription)"
                )
            }
        }
    }

    private func createTemporaryIPA(from appPath: String) async throws -> String {
        let tempDir = createTempDirectory()
        let payloadDir = tempDir.appendingPathComponent("Payload")

        // Create Payload directory
        try FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        // Copy the .app bundle into Payload
        let appURL = URL(fileURLWithPath: appPath)
        let destinationAppURL = payloadDir.appendingPathComponent(appURL.lastPathComponent)
        try FileManager.default.copyItem(at: appURL, to: destinationAppURL)

        // Create IPA (which is just a zip file)
        let ipaPath = tempDir.appendingPathComponent("temp.ipa").path

        // Zip the Payload directory
        let currentDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempDir.path)
        try await shell(cmd: "/usr/bin/zip", args: ["-r", "-q", ipaPath, "Payload"])
        FileManager.default.changeCurrentDirectoryPath(currentDir)

        return ipaPath
    }

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
