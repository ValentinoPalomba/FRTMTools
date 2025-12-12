import Foundation

actor BadWordScanStore {
    private let fm = FileManager.default
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? Self.defaultBaseDirectory()
        self.directory = base
        Self.ensureDirectoryExists(base)
    }

    func loadAll() throws -> [BadWordScanRecord] {
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var records: [BadWordScanRecord] = []
        for file in files where file.pathExtension == "json" {
            let data = try Data(contentsOf: file)
            let record = try decoder.decode(BadWordScanRecord.self, from: data)
            records.append(record)
        }
        return records.sorted { $0.scannedAt > $1.scannedAt }
    }

    func save(_ record: BadWordScanRecord) throws {
        let url = directory.appendingPathComponent("\(record.id.uuidString).json")
        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)
    }

    func delete(recordID: UUID) throws {
        let url = directory.appendingPathComponent("\(recordID.uuidString).json")
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    func persistedFileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Helpers

    private static func defaultBaseDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FRTMTools/BadWordScans", isDirectory: true)
    }

    private static func ensureDirectoryExists(_ url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
