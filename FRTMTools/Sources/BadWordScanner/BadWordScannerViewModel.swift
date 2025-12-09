import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class BadWordScannerViewModel: ObservableObject {
    @Published var selectedIPA: URL?
    @Published var scanResult: BadWordScanResult?
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var progressMessage: String?
    @Published var logMessages: [String] = []
    @Published var history: [BadWordScanRecord] = []
    @Published var lastDuration: TimeInterval?
    @Published var dictionaryURL: URL?
    @Published var dictionaryCount: Int = 0
    @Published var selectedRecordID: UUID?

    private let analyzer = IPAAnalyzer()
    private let store = BadWordScanStore()
    internal var dictionaryWords: Set<String> = []
    private let defaults = UserDefaults.standard
    private let dictionaryPathKey = "BadWordScanner.dictionaryPath"
    private var currentScanTask: Task<Void, Never>?

    init() {
        Task { await loadHistory() }
        loadPersistedDictionaryIfAvailable()
    }

    func pickIPA() {
        let panel = NSOpenPanel()
        let ipaType = UTType(filenameExtension: "ipa")
        panel.allowedContentTypes = [ipaType, .application].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select an IPA or .app bundle"

        if panel.runModal() == .OK, let url = panel.url {
            selectedIPA = url
            scan(ipaURL: url)
        }
    }

    func scan(ipaURL: URL) {
        guard !dictionaryWords.isEmpty else {
            errorMessage = "Select a dictionary JSON file before scanning."
            return
        }

        isScanning = true
        errorMessage = nil
        scanResult = nil
        progressMessage = "Starting scan…"
        logMessages.removeAll()
        lastDuration = nil
        let start = Date()

        currentScanTask?.cancel()
        currentScanTask = Task {
            do {
                log("Analyzing \(ipaURL.lastPathComponent)…")
                guard let badWordScan = try await analyzer.scanBadWords(at: ipaURL, dictionary: dictionaryWords, progress: { [weak self] message in
                    Task { @MainActor in
                        self?.progressMessage = message
                        self?.log(message)
                    }
                }, shouldCancel: { @Sendable in Task.isCancelled }) else {
                    throw ScannerError.analysisFailed
                }

                let elapsed = Date().timeIntervalSince(start)
                let record = BadWordScanRecord(
                    fileName: ipaURL.lastPathComponent,
                    fileURL: ipaURL,
                    result: badWordScan,
                    duration: elapsed
                )
                try await store.save(record)

                await MainActor.run {
                    self.scanResult = badWordScan
                    self.lastDuration = elapsed
                    self.progressMessage = "Completed in \(Self.formatDuration(elapsed))"
                    self.log("Scan completed in \(Self.formatDuration(elapsed)): \(badWordScan.matches.count) hits in \(badWordScan.scannedFiles) files.")
                    self.upsertHistory(record)
                    self.selectedRecordID = record.id
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.log("Error: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                self.isScanning = false
                self.currentScanTask = nil
                if self.progressMessage == "Starting scan…" {
                    self.progressMessage = nil
                }
            }
        }
    }

    func stopScan() {
        currentScanTask?.cancel()
        currentScanTask = nil
        isScanning = false
        progressMessage = "Cancelled"
        log("Scan cancelled")
    }

    func pickDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select JSON bad-words dictionary"

        if panel.runModal() == .OK, let url = panel.url {
            loadDictionary(from: url)
        }
    }

    private func loadDictionary(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONSerialization.jsonObject(with: data, options: [])
            let words = extractWords(from: decoded)
            guard !words.isEmpty else { throw ScannerError.invalidDictionary }

            dictionaryWords = Set(words.map { $0.lowercased() })
            dictionaryURL = url
            dictionaryCount = dictionaryWords.count
            defaults.set(url.path, forKey: dictionaryPathKey)
            errorMessage = nil
        } catch {
            dictionaryWords = []
            dictionaryURL = nil
            dictionaryCount = 0
            errorMessage = "Could not load dictionary: \(error.localizedDescription)"
        }
    }

    private func extractWords(from json: Any) -> [String] {
        if let array = json as? [String] {
            return array
        }
        if let dict = json as? [String: Any],
           let array = dict["words"] as? [String] {
            return array
        }
        return []
    }

    private func loadPersistedDictionaryIfAvailable() {
        if let path = defaults.string(forKey: dictionaryPathKey) {
            let url = URL(fileURLWithPath: path)
            loadDictionary(from: url)
        }
    }

    private func log(_ message: String) {
        logMessages.append(message)
        if logMessages.count > 200 {
            logMessages.removeFirst(logMessages.count - 200)
        }
    }

    static func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "–" }
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.1f s", seconds)
        } else {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return "\(mins)m \(secs)s"
        }
    }

    func loadHistory() async {
        do {
            let loaded = try await store.loadAll()
            await MainActor.run { self.history = loaded }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    func select(record: BadWordScanRecord) {
        selectedIPA = record.fileURL
        scanResult = record.result
        progressMessage = "Loaded from history"
        lastDuration = record.duration
        errorMessage = nil
        logMessages = ["Loaded saved scan for \(record.fileName) (\(record.result.matches.count) hits)"]
        selectedRecordID = record.id
    }

    private func upsertHistory(_ record: BadWordScanRecord) {
        history.removeAll { $0.id == record.id }
        history.insert(record, at: 0)
    }

    func delete(record: BadWordScanRecord) async {
        do {
            try await store.delete(recordID: record.id)
            await loadHistory()
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func reveal(record: BadWordScanRecord) {
        Task {
            let url = await store.persistedFileURL(for: record.id)
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}

private enum ScannerError: LocalizedError {
    case analysisFailed
    case noResults
    case invalidDictionary

    var errorDescription: String? {
        switch self {
        case .analysisFailed:
            return "Could not analyze the IPA. Make sure the file is valid."
        case .noResults:
            return "Scan completed but no bad word data was produced."
        case .invalidDictionary:
            return "Dictionary file is empty or invalid."
        }
    }
}
