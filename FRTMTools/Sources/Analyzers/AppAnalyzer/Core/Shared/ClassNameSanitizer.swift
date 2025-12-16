import Foundation

struct ClassNameSanitizer: Sendable {
    private let map: ProguardClassMap?

    init(mappingURL: URL?) {
        if let url = mappingURL, let parsedMap = ProguardClassMap(fileURL: url) {
            map = parsedMap
        } else {
            map = nil
        }
    }

    func sanitize(_ className: String) -> String {
        guard let map else { return className }
        return map.originalName(forObfuscated: className)
    }

    var isActive: Bool {
        map != nil
    }
}

private struct ProguardClassMap: Sendable {
    private let entries: [String: String]

    init?(fileURL: URL) {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        guard let contents = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return nil
        }
        var parsed: [String: String] = [:]
        parsed.reserveCapacity(1024)
        contents.enumerateLines { line, _ in
            guard let mapping = ProguardClassMap.parseClassMapping(from: line) else { return }
            parsed[mapping.obfuscated] = mapping.original
        }
        guard !parsed.isEmpty else {
            return nil
        }
        entries = parsed
    }

    func originalName(forObfuscated name: String) -> String {
        entries[name] ?? name
    }

    private static func parseClassMapping(from rawLine: String) -> (original: String, obfuscated: String)? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(":") else { return nil }
        guard let arrowRange = trimmed.range(of: "->") else { return nil }
        let originalPart = trimmed[..<arrowRange.lowerBound].trimmingCharacters(in: .whitespaces)
        var obfuscatedPart = trimmed[arrowRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !originalPart.isEmpty else { return nil }
        guard obfuscatedPart.hasSuffix(":") else { return nil }
        obfuscatedPart.removeLast()
        let cleanedOriginal = normalizeClassName(originalPart)
        let cleanedObfuscated = normalizeClassName(obfuscatedPart)
        guard !cleanedOriginal.isEmpty && !cleanedObfuscated.isEmpty else { return nil }
        return (cleanedOriginal, cleanedObfuscated)
    }

    private static func normalizeClassName(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("L"), normalized.hasSuffix(";") {
            normalized = String(normalized.dropFirst().dropLast())
        }
        normalized = normalized.replacingOccurrences(of: "/", with: ".")
        return normalized
    }
}
