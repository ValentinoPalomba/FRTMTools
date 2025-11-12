import Foundation

enum AndroidManifestInspector {
    static func inspect(apkURL: URL) -> AndroidManifestInfo? {
        guard apkURL.pathExtension.lowercased() == "apk" else {
            return nil
        }
        guard let toolURL = AndroidBuildTools.locateExecutable(named: "aapt")
                ?? AndroidBuildTools.locateExecutable(named: "aapt2") else {
            return nil
        }

        do {
            let output = try run(toolURL: toolURL, arguments: ["dump", "badging", apkURL.path])
            return parseBadging(output: output)
        } catch {
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
