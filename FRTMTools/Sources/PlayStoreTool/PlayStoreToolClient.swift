import Foundation
import AppKit

// MARK: - Models

struct PlayStoreApp: Identifiable, Codable, Hashable {
    let id: String
    let app_name: String
    let package_name: String
    let creator: String?
    let version: String?
    let size: String?

    // Convenience
    var displayName: String { app_name }
}

// MARK: - PlayStoreTool Client

final class PlayStoreToolClient: @unchecked Sendable {

    enum PlayStoreToolError: LocalizedError {
        case gplaycliNotFound
        case commandFailed(exitCode: Int32, output: String, error: String)
        case downloadFailed
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .gplaycliNotFound:
                return "gplaycli executable was not found. Install it with pip (pip install gplaycli) or place it in PATH."
            case .commandFailed(let code, let out, let err):
                return "gplaycli failed (code \(code)).\n\nOutput:\n\(out)\n\nError:\n\(err)"
            case .downloadFailed:
                return "Download appears to have failed. No .apk file was found at the destination."
            case .invalidOutput:
                return "Failed to parse command output."
            }
        }
    }

    // MARK: Internal State

    private var cachedExecutableURL: URL?

    // MARK: Public API

    func isInstalled() async -> Bool {
        await resolveExecutable() != nil
    }

    func searchApps(term: String, limit: Int = 25) async throws -> [PlayStoreApp] {
        guard let exe = await resolveExecutable() else { throw PlayStoreToolError.gplaycliNotFound }
        let args = ["-s", term, "-n", "\(limit)"]
        let json = try await runJSONCommand(executableURL: exe, arguments: args)
        return parseSearchResults(from: json)
    }

    /// Downloads the latest available APK for a package name into the given directory.
    /// Returns the URL of the downloaded .apk file.
    func downloadAPK(packageName: String, to directory: URL, log: @escaping @Sendable (String) -> Void) async throws -> URL {
        guard let exe = await resolveExecutable() else { throw PlayStoreToolError.gplaycliNotFound }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let beforeFiles = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []

        let args = ["-d", packageName, "-f", directory.path]
        let output = try await runTextCommand(executableURL: exe, arguments: args, onLine: log)
        log(output)

        let afterFiles = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let newFiles = afterFiles.filter { $0.pathExtension.lowercased() == "apk" && !beforeFiles.contains($0) }
        let chosen: URL?
        if newFiles.isEmpty {
            chosen = afterFiles.filter { $0.pathExtension.lowercased() == "apk" }
                .sorted { (a, b) in
                    let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return da > db
                }
                .first
        } else {
            chosen = newFiles.sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }.first
        }
        guard let apkURL = chosen else { throw PlayStoreToolError.downloadFailed }
        return apkURL
    }

    // MARK: - Internals

    private func parseSearchResults(from json: Any) -> [PlayStoreApp] {
        guard let array = json as? [[String: Any]] else {
            return []
        }
        return array.compactMap { dict -> PlayStoreApp? in
            guard let appName = dict["app_name"] as? String,
                  let packageName = dict["package_name"] as? String else {
                return nil
            }
            return PlayStoreApp(
                id: packageName,
                app_name: appName,
                package_name: packageName,
                creator: dict["creator"] as? String,
                version: dict["version"] as? String,
                size: dict["size"] as? String
            )
        }
    }

    private func resolveExecutable() async -> URL? {
        let fm = FileManager.default

        if let cachedExecutableURL,
           fm.isExecutableFile(atPath: cachedExecutableURL.path) {
            return cachedExecutableURL
        }

        if let override = ProcessInfo.processInfo.environment["GPLAYCLI_PATH"],
           !override.isEmpty,
           fm.isExecutableFile(atPath: override) {
            let url = URL(fileURLWithPath: override)
            cachedExecutableURL = url
            return url
        }

        // Try PATH via /usr/bin/env which
        if let path = try? await runTextCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["which", "gplaycli"]
        ).trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           fm.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path)
            cachedExecutableURL = url
            return url
        }

        // Accumulate candidate locations
        var candidates: [String] = []
        var seen: Set<String> = []

        func appendCandidate(_ path: String) {
            guard !path.isEmpty, !seen.contains(path) else { return }
            candidates.append(path)
            seen.insert(path)
        }

        appendCandidate("/opt/homebrew/bin/gplaycli")
        appendCandidate("/usr/local/bin/gplaycli")

        if let brewPrefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] {
            appendCandidate("\(brewPrefix)/bin/gplaycli")
        }

        let homeDirectory = fm.homeDirectoryForCurrentUser
        appendCandidate(homeDirectory.appendingPathComponent("homebrew/bin/gplaycli").path)
        appendCandidate(homeDirectory.appendingPathComponent(".homebrew/bin/gplaycli").path)
        appendCandidate(homeDirectory.appendingPathComponent(".local/bin/gplaycli").path)
        appendCandidate(homeDirectory.appendingPathComponent("bin/gplaycli").path)

        let pathComponents = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }
        for component in pathComponents {
            appendCandidate(URL(fileURLWithPath: component).appendingPathComponent("gplaycli").path)
        }

        for candidate in candidates {
            if fm.isExecutableFile(atPath: candidate) {
                let url = URL(fileURLWithPath: candidate)
                cachedExecutableURL = url
                return url
            }
        }

        cachedExecutableURL = nil
        return nil
    }

    private func runJSONCommand(executableURL: URL, arguments: [String]) async throws -> Any {
        let (out, _) = try await run(executableURL: executableURL, arguments: arguments)
        guard let data = out.data(using: .utf8) else { throw PlayStoreToolError.invalidOutput }
        return try JSONSerialization.jsonObject(with: data, options: [])
    }

    @discardableResult
    private func runTextCommand(executableURL: URL, arguments: [String], onLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let (out, err) = try await run(executableURL: executableURL, arguments: arguments, onLine: onLine)
        if !err.isEmpty {
            // gplaycli might print progress to stderr; do not treat as fatal unless process exited non-zero (handled in run)
        }
        return out
    }

    private func run(executableURL: URL, arguments: [String], onLine: (@Sendable (String) -> Void)? = nil) async throws -> (String, String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // Optional line streaming
        var outHandle: FileHandle?
        var errHandle: FileHandle?
        if let onLine {
            outHandle = outPipe.fileHandleForReading
            errHandle = errPipe.fileHandleForReading

            outHandle?.readabilityHandler = { [onLine] handle in
                if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                    onLine(line)
                }
            }
            errHandle?.readabilityHandler = { [onLine] handle in
                if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                    onLine(line)
                }
            }
        }

        process.waitUntilExit()
        outHandle?.readabilityHandler = nil
        errHandle?.readabilityHandler = nil

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw PlayStoreToolError.commandFailed(exitCode: process.terminationStatus, output: out, error: err)
        }
        return (out, err)
    }
}
