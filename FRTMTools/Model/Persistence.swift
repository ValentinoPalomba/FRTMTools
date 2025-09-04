import Foundation

class Persistence {
    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = directory.appendingPathComponent("FRTMTools")
        if !FileManager.default.fileExists(atPath: appDirectory.path) {
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        return appDirectory.appendingPathComponent("analyses.json")
    }

    static func loadAnalyses() -> [IPAAnalysis] {
        do {
            let data = try Data(contentsOf: fileURL)
            let analyses = try JSONDecoder().decode([IPAAnalysis].self, from: data)
            return analyses
        } catch {
            return []
        }
    }

    static func saveAnalyses(_ analyses: [IPAAnalysis]) {
        do {
            let data = try JSONEncoder().encode(analyses)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save analyses: \(error)")
        }
    }
}
