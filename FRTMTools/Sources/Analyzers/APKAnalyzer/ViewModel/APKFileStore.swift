//
//  APKFileStore.swift
//  FRTMTools
//
//

import Foundation

/// Actor responsible for persisting and loading APK analyses
actor APKFileStore {
    static let shared = APKFileStore()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("FRTMTools/apk_analyses", isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    /// Saves an array of APK analyses to disk
    /// - Parameter analyses: Array of APKAnalysis objects to save
    func saveAnalyses(_ analyses: [APKAnalysis]) async throws {
        // Save each analysis as a separate JSON file
        for analysis in analyses {
            let fileURL = storageDirectory.appendingPathComponent("\(analysis.id.uuidString).json")
            let data = try encoder.encode(analysis)
            try data.write(to: fileURL)
        }
    }

    /// Loads all APK analyses from disk
    /// - Returns: Array of APKAnalysis objects
    func loadAnalyses() async throws -> [APKAnalysis] {
        guard fileManager.fileExists(atPath: storageDirectory.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var analyses: [APKAnalysis] = []

        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let analysis = try decoder.decode(APKAnalysis.self, from: data)
                analyses.append(analysis)
            } catch {
                print("Failed to load analysis from \(file.lastPathComponent): \(error)")
            }
        }

        return analyses
    }

    /// Deletes an analysis from disk
    /// - Parameter id: UUID of the analysis to delete
    func deleteAnalysis(id: UUID) async throws {
        let fileURL = storageDirectory.appendingPathComponent("\(id.uuidString).json")

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    /// Deletes all analyses from disk
    func deleteAllAnalyses() async throws {
        let files = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)

        for file in files {
            try fileManager.removeItem(at: file)
        }
    }
}
