import Foundation

struct BadWordMatch: Codable, Hashable, Sendable {
    enum Source: String, Codable {
        case text
        case binaryStrings
        case filename
    }

    let path: String
    let word: String
    let context: String?
    let source: Source
}

struct BadWordScanResult: Codable, Sendable {
    let matches: [BadWordMatch]
    let scannedFiles: Int
    let dictionarySize: Int
}

enum BadWordDictionary {
    // Predefined, case-insensitive dictionary. Extend this list as needed.
    static let words: Set<String> = ["parolaccia"]
}

/// Scans an extracted IPA bundle for profanities, including Mach-O binaries via `strings`.
final class BadWordScanner: @unchecked Sendable {
    private let words: [String]
    private let regex: NSRegularExpression

    init(words: Set<String>) {
        self.words = Array(words).sorted()
        self.regex = BadWordScanner.makeRegex(from: words)
    }

    func scan(
        appBundleURL: URL,
        progress: (@Sendable (String) -> Void)? = nil,
        shouldCancel: (@Sendable () -> Bool)? = nil
    ) -> BadWordScanResult {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: appBundleURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return BadWordScanResult(matches: [], scannedFiles: 0, dictionarySize: words.count)
        }

        var filesToScan: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }
            filesToScan.append(fileURL)
        }

        final class Accumulator: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var matches: [BadWordMatch] = []
            private(set) var scannedFiles = 0

            func add(_ found: [BadWordMatch]) {
                lock.lock()
                matches.append(contentsOf: found)
                scannedFiles += 1
                lock.unlock()
            }
        }

        let accumulator = Accumulator()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated

        for fileURL in filesToScan {
            queue.addOperation {
                if shouldCancel?() == true { return }
                let relativePath = self.relativePath(for: fileURL, root: appBundleURL)
                progress?("Scanning \(relativePath)")
                let found = self.scanFile(at: fileURL, relativePath: relativePath, progress: progress)
                accumulator.add(found)
            }
        }

        if shouldCancel?() == true {
            queue.cancelAllOperations()
        }
        queue.waitUntilAllOperationsAreFinished()

        let unique = Array(Set(accumulator.matches)).sorted {
            if $0.path == $1.path { return $0.word < $1.word }
            return $0.path < $1.path
        }

        return BadWordScanResult(matches: unique, scannedFiles: accumulator.scannedFiles, dictionarySize: words.count)
    }

    // MARK: - File scanning

    private func scanFile(at url: URL, relativePath: String, progress: (@Sendable (String) -> Void)? = nil) -> [BadWordMatch] {
        var results: [BadWordMatch] = scanName(relativePath: relativePath)

        let sample = sampleData(at: url, length: 4096)

        if let sample, isLikelyText(data: sample) {
            if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                results.append(contentsOf: scan(content: utf8, relativePath: relativePath, source: .text))
                return results
            } else if let latin = try? String(contentsOf: url, encoding: .isoLatin1) {
                results.append(contentsOf: scan(content: latin, relativePath: relativePath, source: .text))
                return results
            }
        }

        guard shouldRunStrings(for: url, sample: sample) else { return results }
        guard let stringsOutput = stringsOutput(for: url, progress: progress) else { return results }
        results.append(contentsOf: scan(content: stringsOutput, relativePath: relativePath, source: .binaryStrings))
        return results
    }

    private func scan(content: String, relativePath: String, source: BadWordMatch.Source) -> [BadWordMatch] {
        var results: [BadWordMatch] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            let matches = regex.matches(in: trimmed, options: [], range: range)
            guard !matches.isEmpty else { continue }

            for match in matches {
                guard let wordRange = Range(match.range(at: 1), in: trimmed) else { continue }
                let word = trimmed[wordRange].lowercased()
                let context = trimmed.prefix(200)
                results.append(
                    BadWordMatch(
                        path: relativePath,
                        word: word,
                        context: String(context),
                        source: source
                    )
                )
            }
        }

        return results
    }

    // MARK: - Helpers

    private static func makeRegex(from words: Set<String>) -> NSRegularExpression {
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\b(\(escaped.joined(separator: "|")))\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private func string(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let ascii = String(data: data, encoding: .ascii) { return ascii }
        if let latin = String(data: data, encoding: .isoLatin1) { return latin }
        return nil
    }

    private func isLikelyText(data: Data) -> Bool {
        let sample = data.prefix(4096)
        guard !sample.isEmpty else { return false }

        if sample.contains(0) { return false }

        let controlBytes = sample.filter { byte in
            // Allow tab/newline, reject other ASCII control characters.
            return (byte < 0x09 || (byte > 0x0D && byte < 0x20))
        }
        let ratio = Double(controlBytes.count) / Double(sample.count)
        return ratio < 0.3
    }

    private func shouldRunStrings(for url: URL, sample: Data?) -> Bool {
        let ext = url.pathExtension.lowercased()
        let skipExtensions: Set<String> = [
            "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "pdf", "car",
            "plist", "xml", "json", "txt", "rtf", "strings", "stringsdict",
            "html", "htm", "css", "js", "mp3", "m4a", "wav", "mp4", "mov", "zip",
            "gz", "bz2", "7z", "rar", "aiff", "caf", "ttf", "otf", "woff", "woff2"
        ]

        if skipExtensions.contains(ext) {
            return false
        }

        if let sample, isMachO(sample: sample) {
            return true
        }

        if ext == "dylib" || ext == "so" || ext == "framework" {
            return true
        }

        if ext.isEmpty {
            return true
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            return size.intValue < 5_000_000
        }

        return false
    }

    private func isMachO(sample: Data) -> Bool {
        let magicNumbers: [UInt32] = [
            0xfeedface, 0xcefaedfe, // 32-bit
            0xfeedfacf, 0xcffaedfe, // 64-bit
            0xcafebabe, 0xbebafeca, // FAT
            0xcafed00d, 0xd00dfeca  // FAT (64-bit)
        ]

        guard sample.count >= 4 else { return false }
        let value = sample.prefix(4).withUnsafeBytes { ptr -> UInt32 in
            ptr.load(as: UInt32.self)
        }
        return magicNumbers.contains(value)
    }

    private func sampleData(at url: URL, length: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: length)
    }

    private func scanName(relativePath: String) -> [BadWordMatch] {
        var results: [BadWordMatch] = []
        let candidates = [
            relativePath,
            (relativePath as NSString).lastPathComponent
        ]

        for candidate in Set(candidates) where !candidate.isEmpty {
            let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
            let matches = regex.matches(in: candidate, options: [], range: range)
            for match in matches {
                guard let wordRange = Range(match.range(at: 1), in: candidate) else { continue }
                let word = candidate[wordRange].lowercased()
                results.append(
                    BadWordMatch(
                        path: relativePath,
                        word: word,
                        context: candidate,
                        source: .filename
                    )
                )
            }
        }

        return results
    }

    private func stringsOutput(for fileURL: URL, progress: (@Sendable (String) -> Void)? = nil) -> String? {
        progress?("strings \(fileURL.lastPathComponent)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/strings")
        process.arguments = [fileURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let start = Date()
            while process.isRunning {
                Thread.sleep(forTimeInterval: 0.1)
                if Date().timeIntervalSince(start) > 15 {
                    process.terminate()
                    progress?("strings timed out on \(fileURL.lastPathComponent)")
                    return nil
                }
            }
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
    }

    private func relativePath(for fileURL: URL, root: URL) -> String {
        var path = fileURL.path.replacingOccurrences(of: root.path, with: "")
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? fileURL.lastPathComponent : path
    }
}
