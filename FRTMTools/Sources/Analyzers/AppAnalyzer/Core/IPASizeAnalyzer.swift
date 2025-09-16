
import Foundation

// MARK: - Tipi di Dati Pubblici

/// Contiene il risultato finale dell'analisi.
public struct IPASizeAnalysisResult {
    public let appName: String
    public let sizeInMB: Int
}

/// Errori specifici che possono essere lanciati durante l'analisi.
public enum IPASizeError: LocalizedError {
    case invalidIPAPath
    case simulatorNotFound
    case appBundleNotFound
    case installedAppNotFound
    case couldNotParseAppSize
    case shellCommandFailed(command: String, exitCode: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidIPAPath:
            return "The path to the .ipa file is invalid or the file does not exist."
        case .simulatorNotFound:
            return "Could not find an available iPhone simulator."
        case .appBundleNotFound:
            return "Could not find an .app bundle inside the IPA archive."
        case .installedAppNotFound:
            return "Could not find the app path after installation on the simulator."
        case .couldNotParseAppSize:
            return "Could not parse the command output to calculate the app size."
        case .shellCommandFailed(let command, let exitCode, let message):
            return "The shell command '\(command)' failed with code \(exitCode): \(message)"
        }
    }
}

// MARK: - Classe Principale

/// Una classe per analizzare un file .ipa, installarlo su un simulatore e calcolarne la dimensione.
public final class IPASizeAnalyzer {

    public init() {}

    /// Esegue l'intero processo di analisi in modo asincrono.
    public func analyze(ipaPath: String, progress: (String) -> Void) async throws -> IPASizeAnalysisResult {
        guard FileManager.default.fileExists(atPath: ipaPath) else {
            throw IPASizeError.invalidIPAPath
        }
        
        // 1. Trova e prepara il simulatore
        progress("🔎 Searching for a target simulator...")
        let deviceUDID = try await findAndPrepareSimulator(log: progress)
        progress("🎯 Simulator selected: \(deviceUDID)")
        
        // 2. Decomprimi e prepara l'app
        let tempDir = createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let appPath = try await unzipAndFindApp(ipaPath: ipaPath, in: tempDir, log: progress)
        
        // 3. Installa l'app
        progress("📲 Installing the app...")
        try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "install", deviceUDID, appPath])
        
        // 4. Calcola la dimensione
        progress("📊 Calculating installed size...")
        let result = try await calculateInstalledSize(for: appPath, on: deviceUDID)
        
        progress("🎉 Done!")
        return result
    }

    // MARK: - Logica Interna

    private func findAndPrepareSimulator(log: (String) -> Void) async throws -> String {
        // Cerca un simulatore già avviato
        if let bootedUDID = findFirstUUID(in: try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "list", "devices", "booted"])) {
            log("✅ Found booted simulator: \(bootedUDID). Shutting it down for a clean state.")
            try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "shutdown", bootedUDID])
            try await cleanAndBoot(udid: bootedUDID, log: log)
            return bootedUDID
        }
        
        log("No booted simulator found. Searching available devices...")
        let availableDevicesOutput = try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "list", "devices", "available"])
        let lines = availableDevicesOutput.components(separatedBy: .newlines)
        
        var foundUDID: String?
        // Prefer a recent iPhone model if available
        if let iPhone15Line = lines.first(where: { $0.contains("iPhone 15") }) {
            foundUDID = findFirstUUID(in: iPhone15Line)
        }
        
        if foundUDID == nil {
            log("iPhone 15 not found. Selecting the newest available iPhone...")
            if let newestIPhoneLine = lines.last(where: { $0.contains("iPhone") }) {
                foundUDID = findFirstUUID(in: newestIPhoneLine)
            }
        }
        
        guard let deviceUDID = foundUDID else { throw IPASizeError.simulatorNotFound }
        
        try await cleanAndBoot(udid: deviceUDID, log: log)
        return deviceUDID
    }
    
    private func cleanAndBoot(udid: String, log: (String) -> Void) async throws {
        log("🧼 Erasing all content and settings from the simulator...")
        try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "erase", udid])
        log("🚀 Booting the clean simulator...")
        try await shell(cmd: "/usr/bin/xcrun", args: ["simctl", "boot", udid])
    }
    
    private func unzipAndFindApp(ipaPath: String, in tempDir: URL, log: (String) -> Void) async throws -> String {
        log("📦 Unzipping IPA to a temporary location...")
        try await shell(cmd: "/usr/bin/unzip", args: ["-q", ipaPath, "-d", tempDir.path])
        
        let payloadDir = tempDir.appendingPathComponent("Payload")
        guard let appFileName = try? FileManager.default.contentsOfDirectory(atPath: payloadDir.path).first(where: { $0.hasSuffix(".app") }) else {
            throw IPASizeError.appBundleNotFound
        }
        return payloadDir.appendingPathComponent(appFileName).path
    }
    
    private func calculateInstalledSize(for appPath: String, on deviceUDID: String) async throws -> IPASizeAnalysisResult {
        let appName = URL(fileURLWithPath: appPath).lastPathComponent
        let searchPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(deviceUDID)/data/Containers/Bundle/Application")
        
        let findOutput = try await shell(cmd: "/usr/bin/find", args: [searchPath.path, "-name", appName, "-type", "d"])
        guard let installedAppPath = findOutput.components(separatedBy: .newlines).first, !installedAppPath.isEmpty else {
            throw IPASizeError.installedAppNotFound
        }
        
        let duOutput = try await shell(cmd: "/usr/bin/du", args: ["-sm", installedAppPath])
        guard let sizeMBString = duOutput.components(separatedBy: .whitespaces).first, let sizeMB = Int(sizeMBString) else {
            throw IPASizeError.couldNotParseAppSize
        }
        
        return IPASizeAnalysisResult(appName: appName, sizeInMB: sizeMB)
    }

    // MARK: - Helpers
    
    private func createTempDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        return tempDir
    }

    private func findFirstUUID(in text: String) -> String? {
        let pattern = "[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}"
        return text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }

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
            throw IPASizeError.shellCommandFailed(command: "\(cmd) \(args.joined(separator: " "))", exitCode: process.terminationStatus, message: errorMessage)
        }
        
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
