import Foundation

actor DashboardStore {
    private let baseDirectory: URL
    private let runsIndexURL: URL
    private let uploadsDirectory: URL
    private let analysesDirectory: URL

    private var cachedRuns: [DashboardRun]?

    init(dataDirectoryOverride: URL? = nil) {
        let root: URL
        if let override = dataDirectoryOverride {
            root = override
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            root = appSupport.appendingPathComponent("FRTMTools/Dashboard", isDirectory: true)
        }
        baseDirectory = root
        runsIndexURL = root.appendingPathComponent("runs.json")
        uploadsDirectory = root.appendingPathComponent("uploads", isDirectory: true)
        analysesDirectory = root.appendingPathComponent("analyses", isDirectory: true)
    }

    func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: analysesDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    func listRuns() throws -> [DashboardRun] {
        let runs = try loadRunsIndex()
        return runs.sorted { $0.createdAt > $1.createdAt }
    }

    func createRun(originalFileName: String, platform: DashboardPlatform, fileExtension: String) throws -> DashboardRun {
        try ensureDirectories()

        let id = UUID()
        let safeExtension = fileExtension.isEmpty ? "bin" : fileExtension.lowercased()
        let uploadedRelative = "uploads/\(id.uuidString).\(safeExtension)"

        var runs = try loadRunsIndex()
        let run = DashboardRun(
            id: id,
            createdAt: Date(),
            platform: platform,
            originalFileName: originalFileName,
            status: .queued,
            errorMessage: nil,
            uploadedFileRelativePath: uploadedRelative,
            analysisRelativePath: nil
        )
        runs.append(run)
        try saveRunsIndex(runs)
        cachedRuns = runs
        return run
    }

    func updateRun(_ id: UUID, mutate: (inout DashboardRun) -> Void) throws -> DashboardRun {
        var runs = try loadRunsIndex()
        guard let index = runs.firstIndex(where: { $0.id == id }) else {
            throw DashboardStoreError.notFound
        }
        var run = runs[index]
        mutate(&run)
        runs[index] = run
        try saveRunsIndex(runs)
        cachedRuns = runs
        return run
    }

    func run(id: UUID) throws -> DashboardRun {
        let runs = try loadRunsIndex()
        guard let run = runs.first(where: { $0.id == id }) else {
            throw DashboardStoreError.notFound
        }
        return run
    }

    func uploadedFileURL(for run: DashboardRun) -> URL {
        baseDirectory.appendingPathComponent(run.uploadedFileRelativePath)
    }

    func analysisURL(for run: DashboardRun) -> URL? {
        guard let relative = run.analysisRelativePath else { return nil }
        return baseDirectory.appendingPathComponent(relative)
    }

    func analysisRelativePath(for id: UUID) -> String {
        "analyses/\(id.uuidString).json"
    }

    func analysisFileURL(for id: UUID) -> URL {
        analysesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    func baseDirectoryURL() -> URL {
        baseDirectory
    }

    func deleteRun(id: UUID) throws {
        var runs = try loadRunsIndex()
        guard let index = runs.firstIndex(where: { $0.id == id }) else {
            throw DashboardStoreError.notFound
        }
        let run = runs.remove(at: index)
        if FileManager.default.fileExists(atPath: uploadedFileURL(for: run).path) {
            try? FileManager.default.removeItem(at: uploadedFileURL(for: run))
        }
        if let analysisURL = analysisURL(for: run), FileManager.default.fileExists(atPath: analysisURL.path) {
            try? FileManager.default.removeItem(at: analysisURL)
        }
        try saveRunsIndex(runs)
        cachedRuns = runs
    }

    private func loadRunsIndex() throws -> [DashboardRun] {
        if let cachedRuns { return cachedRuns }
        do {
            let data = try Data(contentsOf: runsIndexURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let runs = try decoder.decode([DashboardRun].self, from: data)
            cachedRuns = runs
            return runs
        } catch {
            if (error as? CocoaError)?.code == .fileReadNoSuchFile {
                cachedRuns = []
                return []
            }
            throw error
        }
    }

    private func saveRunsIndex(_ runs: [DashboardRun]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(runs)
        try data.write(to: runsIndexURL, options: .atomic)
    }
}

enum DashboardStoreError: Error {
    case notFound
}
