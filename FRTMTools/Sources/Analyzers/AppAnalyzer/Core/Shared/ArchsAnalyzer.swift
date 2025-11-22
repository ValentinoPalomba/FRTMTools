//
//  ArchsAnalyzer.swift
//  FRTMTools
//
//  Created by Davide Fiorino on 31/10/25.
//

import Foundation

struct ArchsResult {
    let number: Int
    let types: [String]
    
    static let none = ArchsResult(number: 0, types: [])
}

class ArchsAnalyzer {
    static func generateCategories(from rootFile: FileInfo) -> ArchsResult {
        guard let allFiles = rootFile.subItems else {
            return ArchsResult.none
        }

        var binariesToAnalyze: [FileInfo] = []

        // Find the main application binary
        if let macOSFolder = allFiles.first(where: { $0.name == "MacOS" && $0.type == .directory }) {
            if let binary = macOSFolder.subItems?.first(where: { $0.type == .binary }) {
                binariesToAnalyze.append(binary)
            }
        } else if let binary = allFiles.first(where: { $0.type == .binary }) { // iOS fallback
            binariesToAnalyze.append(binary)
        }

        // Find binaries within each framework
        if let frameworksFolder = allFiles.first(where: { $0.name == "Frameworks" && $0.type == .directory }) {
            let frameworkDirs = frameworksFolder.subItems?.filter { $0.type == .directory && $0.name.hasSuffix(".framework") } ?? []
            for frameworkDir in frameworkDirs {
                let frameworkName = frameworkDir.name.replacingOccurrences(of: ".framework", with: "")
                if let frameworkBinary = frameworkDir.subItems?.first(where: { $0.name == frameworkName && $0.type == .binary }) {
                    binariesToAnalyze.append(frameworkBinary)
                }
            }
        }

        // If no binaries were found, there are no architectures to report.
        if binariesToAnalyze.isEmpty {
            return ArchsResult.none
        }

        var allArchs = Set<String>()

        // Get the architectures for each binary and add them to the `allArchs` set.
        for binaryInfo in binariesToAnalyze {
            guard let path = binaryInfo.fullPath else { continue }
            if let archs = getArchitectures(for: path) {
                allArchs.formUnion(archs)
            }
        }
        
        let sortedArchs = Array(allArchs).sorted()
        
        return ArchsResult(number: sortedArchs.count, types: sortedArchs)
    }

    /// Executes `lipo -archs` on the given binary path to get its architectures.
    private static func getArchitectures(for binaryPath: String) -> Set<String>? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        process.arguments = ["-archs", binaryPath]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if output.isEmpty { return Set() }
                let architectures = output.split(separator: " ").map(String.init)
                return Set(architectures)
            }
        } catch {
            print("Failed to run lipo on \(binaryPath): \(error)")
            return nil
        }
        return nil
    }
}
