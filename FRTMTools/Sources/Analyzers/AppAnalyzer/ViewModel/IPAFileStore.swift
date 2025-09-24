import Foundation
import FRTMCore

actor IPAFileStore {
    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    let appDirectory: URL
    let analysesDirectoryURL: URL

    init(appDirectory: URL, analysesDirectoryURL: URL) {
        self.appDirectory = appDirectory
        self.analysesDirectoryURL = analysesDirectoryURL
        IPAFileStore.ensureDirectoryExists(appDirectory)
        IPAFileStore.ensureDirectoryExists(analysesDirectoryURL)
    }

    func loadAnalyses() throws -> [IPAAnalysis] {
        let files = try fm.contentsOfDirectory(at: analysesDirectoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var loaded: [IPAAnalysis] = []
        for file in files where file.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: file)
            let item = try decoder.decode(IPAAnalysis.self, from: data)
            loaded.append(item)
        }
        return loaded
    }

    func saveAnalyses(_ analyses: [IPAAnalysis]) throws {
        for analysis in analyses {
            try saveAnalysis(analysis)
        }
    }

    func saveAnalysis(_ analysis: IPAAnalysis) throws {
        let url = fileURL(for: analysis.id)
        let data = try encoder.encode(analysis)
        try data.write(to: url, options: .atomic)
    }

    func deleteAnalysis(id: UUID) throws {
        let url = fileURL(for: id)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    func fileURL(for id: UUID) -> URL {
        analysesDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    private static func ensureDirectoryExists(_ url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
