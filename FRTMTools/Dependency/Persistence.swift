import Foundation
import FRTMCore
protocol PersistenceManager: AnyObject {
    func loadAnalyses() -> [IPAAnalysis]
    func saveAnalyses(_ analyses: [IPAAnalysis])
}


class CorePersistenceManager: PersistenceManager {
    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = directory.appendingPathComponent("FRTMTools")
        if !FileManager.default.fileExists(atPath: appDirectory.path) {
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        return appDirectory.appendingPathComponent("analyses.json")
    }

    func loadAnalyses() -> [IPAAnalysis] {
        do {
            let data = try Data(contentsOf: CorePersistenceManager.fileURL)
            let analyses = try JSONDecoder().decode([IPAAnalysis].self, from: data)
            return analyses
        } catch {
            return []
        }
    }

    func saveAnalyses(_ analyses: [IPAAnalysis]) {
        do {
            let data = try JSONEncoder().encode(analyses)
            try data.write(to: CorePersistenceManager.fileURL, options: .atomic)
        } catch {
            print("Failed to save analyses: \(error)")
        }
    }
}
