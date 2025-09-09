import Foundation
import FRTMCore

protocol PersistenceManager: AnyObject {
    func load<T: Codable>(key: String) -> [T]
    func save<T: Codable>(_ items: [T], key: String)
}


class CorePersistenceManager: PersistenceManager {
    private func fileURL(for key: String) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = directory.appendingPathComponent("FRTMTools")
        if !FileManager.default.fileExists(atPath: appDirectory.path) {
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        return appDirectory.appendingPathComponent("\(key).json")
    }

    func load<T: Codable>(key: String) -> [T] {
        let url = fileURL(for: key)
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([T].self, from: data)
            return items
        } catch {
            if (error as? CocoaError)?.code != .fileReadNoSuchFile {
                 print("Failed to load items for key \(key): \(error)")
            }
            return []
        }
    }

    func save<T: Codable>(_ items: [T], key: String) {
        let url = fileURL(for: key)
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save items for key \(key): \(error)")
        }
    }
}