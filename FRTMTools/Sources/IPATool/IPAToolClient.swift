import Foundation
import AppKit

// MARK: - Models

struct IPAToolStoreApp: Identifiable, Codable, Hashable {
    let id: Int
    let trackName: String
    let bundleId: String
    let sellerName: String?
    let version: String?
    let formattedPrice: String?
    let artworkUrl100: String?
    let price: Double?

    // Convenience
    var displayName: String { trackName }
}

extension Notification.Name {
    static let clearIPAToolMetadataCache = Notification.Name("clearIPAToolMetadataCache")
}

struct IPAToolAppVersion: Identifiable, Codable, Hashable {
    let id: String
    let version: String
    let build: String?
    let displayVersion: String?
    let externalIdentifier: String?

    init(
        id: String = UUID().uuidString,
        version: String,
        build: String? = nil,
        displayVersion: String? = nil,
        externalIdentifier: String? = nil
    ) {
        self.id = id
        self.version = version
        self.build = build
        self.displayVersion = displayVersion
        self.externalIdentifier = externalIdentifier
    }

    var effectiveIdentifier: String { externalIdentifier ?? version }
}

// iTunes Search API response
private struct ITunesSearchResponse: Decodable {
    let resultCount: Int
    let results: [ITunesSearchItem]
}

private struct ITunesSearchItem: Decodable {
    let trackId: Int
    let trackName: String
    let bundleId: String
    let sellerName: String?
    let version: String?
    let formattedPrice: String?
    let artworkUrl100: String?
    let price: Double?
}

// MARK: - IPATool Client

final class IPAToolClient: @unchecked Sendable {
    private struct VersionMetadataCacheEntry: Codable {
        let externalVersionID: String
        let displayVersion: String?
    }

    enum IPAToolError: LocalizedError {
        case ipatoolNotFound
        case commandFailed(exitCode: Int32, output: String, error: String)
        case downloadFailed
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .ipatoolNotFound:
                return "ipatool executable was not found. Install it with Homebrew (brew install ipatool) or place it in PATH."
            case .commandFailed(let code, let out, let err):
                return "ipatool failed (code \(code)).\n\nOutput:\n\(out)\n\nError:\n\(err)"
            case .downloadFailed:
                return "Download appears to have failed. No .ipa file was found at the destination."
            case .invalidOutput:
                return "Failed to parse command output."
            }
        }
    }

    // MARK: Internal State

    private var versionMetadataCache: [String: VersionMetadataCacheEntry] = [:]
    private var cachedExecutableURL: URL?
    private var attemptedPurchases: Set<String> = []
    private var failedMetadataIdentifiers: Set<String> = []
    private static let metadataCacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("FRTMTools", isDirectory: true)
            .appendingPathComponent("ipatool_version_cache.json")
    }()
    private var metadataCacheURL: URL { Self.metadataCacheURL }

    init() {
        loadMetadataCache()
    }

    func clearMetadataCache() {
        versionMetadataCache.removeAll()
        Self.removePersistedMetadataCache()
    }

    static func removePersistedMetadataCache() {
        let fm = FileManager.default
        let url = metadataCacheURL
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: Public API

    func isInstalled() async -> Bool {
        await resolveExecutable() != nil
    }

    func login(email: String, password: String, otp: String?) async throws -> String {
        guard let exe = await resolveExecutable() else { throw IPAToolError.ipatoolNotFound }
        let args = ["auth", "login", "--email", email, "--password", password]
        if let otp, !otp.isEmpty {
            do {
                return try await runTextCommand(executableURL: exe, arguments: args + ["--one-time-code", otp])
            } catch {
                return try await runTextCommand(executableURL: exe, arguments: args + ["--otp", otp])
            }
        } else {
            return try await runTextCommand(executableURL: exe, arguments: args)
        }
    }

    func authStatus() async throws -> String {
        guard let exe = await resolveExecutable() else { throw IPAToolError.ipatoolNotFound }
        return try await runTextCommand(executableURL: exe, arguments: ["auth", "status"])
    }

    func authInfo() async throws -> Bool {
        guard let exe = await resolveExecutable() else { throw IPAToolError.ipatoolNotFound }
        let jsonArgs = ["auth", "info", "--format", "json"]
        if let json = try? await runJSONCommand(executableURL: exe, arguments: jsonArgs),
           let dict = json as? [String: Any],
           let success = dict["success"] as? Bool {
            return success
        }
        let text = try await runTextCommand(executableURL: exe, arguments: ["auth", "info"])
        return text.contains("success=true")
    }

    func searchApps(term: String, country: String = "us", limit: Int = 25) async throws -> [IPAToolStoreApp] {
        if let viaIPATool = await searchAppsViaIPATool(term: term, country: country, limit: limit), !viaIPATool.isEmpty {
            return viaIPATool
        }
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let urlString = "https://itunes.apple.com/search?term=\(encodedTerm)&entity=software&country=\(country)&limit=\(limit)"
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        return decoded.results.map { item in
            IPAToolStoreApp(
                id: item.trackId,
                trackName: item.trackName,
                bundleId: item.bundleId,
                sellerName: item.sellerName,
                version: item.version,
                formattedPrice: item.formattedPrice,
                artworkUrl100: item.artworkUrl100,
                price: item.price
            )
        }
    }
    
    private func searchAppsViaIPATool(term: String, country: String, limit: Int) async -> [IPAToolStoreApp]? {
        guard let exe = await resolveExecutable() else { return nil }
        var args: [String] = [
            "search",
            "--term", term,
            "--country", country,
            "--limit", "\(limit)",
            "--format", "json"
        ]
        if term.contains(".") {
            // ipatool search occasionally requires --bundle-identifier when searching by bundle id
            args += ["--bundle-identifier", term]
        }
        guard let json = try? await runJSONCommand(executableURL: exe, arguments: args) else { return nil }
        return parseSearchResults(from: json)
    }

    /// Best-effort versions listing using ipatool (if supported). Falls back to a single version if not supported.
    func listVersions(
        bundleId: String,
        appId: Int?,
        fallbackCurrentVersion: String?,
        ensurePurchaseIfFree: Bool = false
    ) async -> [IPAToolAppVersion] {
        guard let exe = await resolveExecutable() else {
            if let v = fallbackCurrentVersion { return [IPAToolAppVersion(version: v)] }
            return []
        }
        if ensurePurchaseIfFree {
            await attemptPurchaseIfPossible(executableURL: exe, bundleId: bundleId, appId: appId)
        }
        var resolvedVersions: [IPAToolAppVersion]?

        // Try a few likely subcommands/flags to retrieve versions in JSON; if they fail, fallback.
        let candidates: [[String]] = [
            ["list-versions", "-b", bundleId, "--format", "json"],
            ["app", "versions", "-b", bundleId, "--format", "json"],
            ["list-versions", "-b", bundleId],
            ["versions", "--bundle-identifier", bundleId, "--format", "json"]
        ]
        for args in candidates {
            if let json = try? await runJSONCommand(executableURL: exe, arguments: args),
               let versions = parseVersions(from: json), !versions.isEmpty {
                resolvedVersions = versions
                break
            }
        }

        if resolvedVersions == nil {
        // Many ipatool builds only output plain text; attempt to parse that format too.
            let textCandidates: [[String]] = [
                ["list-versions", "-b", bundleId],
                ["app", "versions", "-b", bundleId]
            ]
            for args in textCandidates {
                if let text = try? await runTextCommand(executableURL: exe, arguments: args),
                   let versions = parseTextVersions(from: text), !versions.isEmpty {
                    resolvedVersions = versions
                    break
                }
            }
        }
        if let versions = resolvedVersions {
            let enriched = await attachMetadataIfPossible(
                versions,
                bundleId: bundleId,
                appId: appId,
                executableURL: exe
            )
            if !enriched.isEmpty { return enriched }
            return versions
        }

        if let v = fallbackCurrentVersion { return [IPAToolAppVersion(version: v)] }
        return []
    }

    /// Downloads the latest available IPA for a bundle identifier into the given directory.
    /// Returns the URL of the downloaded .ipa file.
    func downloadIPA(bundleId: String, to directory: URL, log: @escaping @Sendable (String) -> Void) async throws -> URL {
        try await downloadIPA(bundleId: bundleId, appId: nil, externalVersionId: nil, to: directory, log: log)
    }

    func downloadIPA(
        bundleId: String,
        appId: Int?,
        externalVersionId: String?,
        to directory: URL,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        guard let exe = await resolveExecutable() else { throw IPAToolError.ipatoolNotFound }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let beforeFiles = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []

        var args = ["download", "-b", bundleId, "-o", directory.path]
        if let appId { args += ["-i", "\(appId)"] }
        if let externalVersionId, !externalVersionId.isEmpty {
            args += ["--external-version-id", externalVersionId]
        }
        let output = try await runTextCommand(executableURL: exe, arguments: args, onLine: log)
        log(output)

        let afterFiles = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let newFiles = afterFiles.filter { $0.pathExtension.lowercased() == "ipa" && !beforeFiles.contains($0) }
        let chosen: URL?
        if newFiles.isEmpty {
            chosen = afterFiles.filter { $0.pathExtension.lowercased() == "ipa" }
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
        guard let ipaURL = chosen else { throw IPAToolError.downloadFailed }
        return ipaURL
    }

    // MARK: - Internals

    private func parseVersions(from json: Any) -> [IPAToolAppVersion]? {
        let payloads: [[String: Any]]
        if let dict = json as? [String: Any] {
            if let versions = dict["versions"] as? [[String: Any]] {
                payloads = versions
            } else if let data = dict["data"] as? [[String: Any]] {
                payloads = data
            } else if let results = dict["results"] as? [[String: Any]] {
                payloads = results
            } else {
                payloads = []
            }
        } else if let arr = json as? [[String: Any]] {
            payloads = arr
        } else {
            payloads = []
        }

        guard !payloads.isEmpty else { return nil }

        let mapped = payloads.compactMap { payload -> IPAToolAppVersion? in
            guard let version = (payload["version"] as? String)
                ?? (payload["bundleShortVersionString"] as? String)
                ?? (payload["softwareVersionExternalIdentifier"] as? String) else {
                return nil
            }
            let build = (payload["build"] as? String)
                ?? (payload["bundleVersion"] as? String)
                ?? (payload["buildNumber"] as? String)
            let identifier = (payload["externalVersionIdentifier"] as? String)
                ?? (payload["externalVersionId"] as? String)
                ?? (payload["external_version_id"] as? String)
            let releaseDate = parseReleaseDate(
                payload["released"]
                    ?? payload["releaseDate"]
                    ?? payload["releaseTimestamp"]
                    ?? payload["releasedAt"]
            )
            return IPAToolAppVersion(
                version: version,
                build: build,
                displayVersion: version,
                releaseDate: releaseDate,
                externalIdentifier: identifier
            )
        }
        return mapped.isEmpty ? nil : mapped
    }

    private func parseTextVersions(from text: String) -> [IPAToolAppVersion]? {
        let cleanedText = stripANSICodes(from: text)
        if let identifiers = parseExternalIdentifiers(from: cleanedText) {
            return identifiers
        }

        let lines = cleanedText.components(separatedBy: .newlines)
        var versions: [IPAToolAppVersion] = []
        var seen = Set<String>()

        let regexPatterns = [
            #"(?i)version[s]?:?\s*([A-Za-z0-9][A-Za-z0-9\.\-_]+)(?:\s*\(([^)]+)\))?"#,
            #"^\s*([A-Za-z0-9][A-Za-z0-9\.\-_]+)(?:\s*\(([^)]+)\))?"#
        ]
        let regexes: [NSRegularExpression] = regexPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }

        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // Drop bullet characters
            if let first = line.first, ["-", "•", "*"].contains(first) {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var parsedVersion: String?
            var parsedBuild: String?

            for regex in regexes {
                let range = NSRange(location: 0, length: line.utf16.count)
                if let match = regex.firstMatch(in: line, options: [], range: range),
                   match.range(at: 1).location != NSNotFound,
                   let versionRange = Range(match.range(at: 1), in: line) {
                    parsedVersion = String(line[versionRange])
                    if match.numberOfRanges > 2,
                       match.range(at: 2).location != NSNotFound,
                       let buildRange = Range(match.range(at: 2), in: line) {
                        parsedBuild = String(line[buildRange])
                    }
                    break
                }
            }

            if parsedVersion == nil {
                // Fall back to first whitespace-delimited token
                if let token = line.split(whereSeparator: { $0.isWhitespace }).first {
                    parsedVersion = String(token)
                }
            }

            guard let versionString = parsedVersion else { continue }
            let buildString: String?
            if let parsedBuild, !parsedBuild.isEmpty {
                buildString = parsedBuild
            } else {
                buildString = nil
            }
            let dedupeKey = versionString + (buildString ?? "")

            if seen.insert(dedupeKey).inserted {
                versions.append(IPAToolAppVersion(version: versionString, build: buildString))
            }
        }

        return versions.isEmpty ? nil : versions
    }
    
    private func parseSearchResults(from json: Any) -> [IPAToolStoreApp]? {
        if let dict = json as? [String: Any] {
            if let success = dict["success"] as? Bool, success == false {
                return nil
            }
            if let results = dict["results"] as? [[String: Any]] {
                return results.compactMap(makeStoreApp(from:))
            }
            if let data = dict["data"] as? [[String: Any]] {
                return data.compactMap(makeStoreApp(from:))
            }
        } else if let array = json as? [[String: Any]] {
            return array.compactMap(makeStoreApp(from:))
        }
        return nil
    }
    
    private func makeStoreApp(from payload: [String: Any]) -> IPAToolStoreApp? {
        func intValue(forKeys keys: [String]) -> Int? {
            for key in keys {
                if let value = payload[key] as? Int { return value }
                if let string = payload[key] as? String, let value = Int(string) { return value }
            }
            return nil
        }
        
        guard
            let trackId = intValue(forKeys: ["trackId", "id", "softwareId", "software_id"]),
            let name = (payload["trackName"] as? String)
                ?? (payload["name"] as? String)
                ?? (payload["title"] as? String),
            let bundleId = (payload["bundleId"] as? String)
                ?? (payload["bundleIdentifier"] as? String)
                ?? (payload["bundle_identifier"] as? String)
        else {
            return nil
        }
        
        let seller = (payload["sellerName"] as? String)
            ?? (payload["developerName"] as? String)
            ?? (payload["artistName"] as? String)
        let version = (payload["version"] as? String)
            ?? (payload["bundleShortVersionString"] as? String)
        let formattedPrice = (payload["formattedPrice"] as? String)
            ?? (payload["priceFormatted"] as? String)
            ?? (payload["formatted-price"] as? String)
        let artwork = (payload["artworkUrl100"] as? String)
            ?? (payload["artworkUrl60"] as? String)
            ?? (payload["artwork_url_100"] as? String)
        let priceValue: Double? = {
            if let double = payload["price"] as? Double {
                return double
            }
            if let number = payload["price"] as? NSNumber {
                return number.doubleValue
            }
            if let string = payload["price"] as? String {
                let normalized = string.replacingOccurrences(of: ",", with: ".")
                return Double(normalized)
            }
            return nil
        }()
        
        return IPAToolStoreApp(
            id: trackId,
            trackName: name,
            bundleId: bundleId,
            sellerName: seller,
            version: version,
            formattedPrice: formattedPrice,
            artworkUrl100: artwork,
            price: priceValue
        )
    }

    private func parseExternalIdentifiers(from text: String) -> [IPAToolAppVersion]? {
        let pattern = #"externalVersionIdentifiers=\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let payload = text[captureRange]
        let identifiers = payload
            .split(separator: ",")
            .compactMap { component -> String? in
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return stripped.isEmpty ? nil : stripped
            }

        guard !identifiers.isEmpty else { return nil }
        return identifiers.map { IPAToolAppVersion(version: $0, externalIdentifier: $0) }
    }

    private func stripANSICodes(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*m", options: []) else {
            return text
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private func attachMetadataIfPossible(
        _ versions: [IPAToolAppVersion],
        bundleId: String,
        appId: Int?,
        executableURL: URL
    ) async -> [IPAToolAppVersion] {
        guard let appId else { return versions }
        guard versions.contains(where: { $0.displayVersion == nil || $0.releaseDate == nil }) else { return versions }

        var enriched: [String: VersionMetadataCacheEntry] = [:]
        let chunkSize = 5
        var index = 0
        var didUpdateCache = false

        while index < versions.count {
            let upperBound = min(index + chunkSize, versions.count)
            let chunk = Array(versions[index..<upperBound])
            var lookupTargets: [String] = []
            for version in chunk {
                let identifier = version.externalIdentifier ?? version.version
                if failedMetadataIdentifiers.contains(identifier) {
                    continue
                }
                if let cached = cachedMetadata(appId: appId, identifier: identifier) {
                    enriched[identifier] = cached
                } else {
                    lookupTargets.append(identifier)
                }
            }

            if !lookupTargets.isEmpty {
                await withTaskGroup(of: (String, VersionMetadataCacheEntry?).self) { group in
                    for identifier in lookupTargets {
                        group.addTask { [bundleId] in
                            let metadata = await self.fetchVersionMetadata(
                                for: identifier,
                                bundleId: bundleId,
                                appId: appId,
                                executableURL: executableURL
                            )
                            return (identifier, metadata)
                        }
                    }

                    for await (identifier, metadata) in group {
                        if let metadata {
                            enriched[identifier] = metadata
                            self.versionMetadataCache[self.metadataCacheKey(appId: appId, identifier: identifier)] = metadata
                            didUpdateCache = true
                        } else {
                            self.failedMetadataIdentifiers.insert(identifier)
                        }
                    }
                }
            }
            index = upperBound
        }

        if didUpdateCache {
            saveMetadataCache()
        }

        guard !enriched.isEmpty else { return versions }

        return versions.map { version in
            let identifier = version.externalIdentifier ?? version.version
            guard let metadata = enriched[identifier] else { return version }
            return IPAToolAppVersion(
                id: version.id,
                version: version.version,
                build: version.build,
                displayVersion: metadata.displayVersion ?? version.displayVersion,
                externalIdentifier: metadata.externalVersionID
            )
        }
    }

    private func fetchVersionMetadata(
        for identifier: String,
        bundleId: String,
        appId: Int,
        executableURL: URL
    ) async -> VersionMetadataCacheEntry? {
        var args = [
            "get-version-metadata",
            "-i", "\(appId)",
            "--external-version-id", identifier,
            "--format", "json"
        ]
        if !bundleId.isEmpty {
            args += ["-b", bundleId]
        }

        guard let json = try? await runJSONCommand(executableURL: executableURL, arguments: args),
              let dict = json as? [String: Any] else {
            return nil
        }

        if let success = dict["success"] as? Bool, success == false {
            logMetadataFailure(from: dict, identifier: identifier)
            return nil
        }

        let payload = dict["data"] as? [String: Any]
            ?? dict["Data"] as? [String: Any]
            ?? dict

        if let status = payload["StatusCode"] as? Int, status >= 400 {
            logMetadataFailure(from: dict, identifier: identifier)
            return nil
        }

        let entry = VersionMetadataCacheEntry(
            externalVersionID: (dict["externalVersionID"] as? String) ?? identifier,
            displayVersion: dict["displayVersion"] as? String
        )
        return entry
    }

    private func logMetadataFailure(from dict: [String: Any], identifier: String) {
        var message = "ipatool metadata fetch failed for \(identifier)"
        if let payload = dict["Data"] as? [String: Any] {
            if let failureType = payload["FailureType"] {
                message += " (FailureType: \(failureType))"
            }
            if let customerMessage = payload["CustomerMessage"] as? String, !customerMessage.isEmpty {
                message += " - \(customerMessage)"
            }
        } else if let error = dict["error"] as? String {
            message += " - \(error)"
        }
        print(message)
    }

    private func metadataCacheKey(appId: Int, identifier: String) -> String {
        "\(appId)#\(identifier)"
    }

    private func cachedMetadata(appId: Int, identifier: String) -> VersionMetadataCacheEntry? {
        versionMetadataCache[metadataCacheKey(appId: appId, identifier: identifier)]
    }

    private func loadMetadataCache() {
        let fm = FileManager.default
        let directory = metadataCacheURL.deletingLastPathComponent()
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: metadataCacheURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: VersionMetadataCacheEntry].self, from: data) {
            versionMetadataCache = decoded
        }
    }

    private func saveMetadataCache() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(versionMetadataCache) else { return }
        do {
            try data.write(to: metadataCacheURL, options: .atomic)
        } catch {
            print("Failed to persist ipatool metadata cache: \(error)")
        }
    }


    private func resolveExecutable() async -> URL? {
        let fm = FileManager.default

        if let cachedExecutableURL,
           fm.isExecutableFile(atPath: cachedExecutableURL.path) {
            return cachedExecutableURL
        }

        if let override = ProcessInfo.processInfo.environment["IPATOOL_PATH"],
           !override.isEmpty,
           fm.isExecutableFile(atPath: override) {
            let url = URL(fileURLWithPath: override)
            cachedExecutableURL = url
            return url
        }

        // Try PATH via /usr/bin/env which
        if let path = try? await runTextCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["which", "ipatool"]
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

        appendCandidate("/opt/homebrew/bin/ipatool")
        appendCandidate("/usr/local/bin/ipatool")

        if let brewPrefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] {
            appendCandidate("\(brewPrefix)/bin/ipatool")
        }

        let homeDirectory = fm.homeDirectoryForCurrentUser
        appendCandidate(homeDirectory.appendingPathComponent("homebrew/bin/ipatool").path)
        appendCandidate(homeDirectory.appendingPathComponent(".homebrew/bin/ipatool").path)
        appendCandidate(homeDirectory.appendingPathComponent(".local/bin/ipatool").path)
        appendCandidate(homeDirectory.appendingPathComponent("bin/ipatool").path)

        let pathComponents = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }
        for component in pathComponents {
            appendCandidate(URL(fileURLWithPath: component).appendingPathComponent("ipatool").path)
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

    private func attemptPurchaseIfPossible(executableURL: URL, bundleId: String, appId: Int?) async {
        let attemptKey = "\(bundleId)#\(appId ?? 0)"
        if attemptedPurchases.contains(attemptKey) { return }
        attemptedPurchases.insert(attemptKey)

        let args = ["purchase", "--bundle-identifier", bundleId]
        
        do {
            _ = try await runTextCommand(executableURL: executableURL, arguments: args)
        } catch {
            // Purchasing a paid/non-owned app will fail; swallow and continue listing versions.
            print("ipatool purchase attempt failed for \(bundleId): \(error.localizedDescription)")
        }
    }

    private func runJSONCommand(executableURL: URL, arguments: [String]) async throws -> Any {
        let (out, _) = try await run(executableURL: executableURL, arguments: arguments)
        let cleaned = stripANSICodes(from: out)
        guard let data = cleaned.data(using: .utf8) else { throw IPAToolError.invalidOutput }
        return try JSONSerialization.jsonObject(with: data, options: [])
    }

    @discardableResult
    private func runTextCommand(executableURL: URL, arguments: [String], onLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let (out, err) = try await run(executableURL: executableURL, arguments: arguments, onLine: onLine)
        if !err.isEmpty {
            // ipatool often prints progress to stderr; do not treat as fatal unless process exited non-zero (handled in run)
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
            throw IPAToolError.commandFailed(exitCode: process.terminationStatus, output: out, error: err)
        }
        return (out, err)
    }
}
