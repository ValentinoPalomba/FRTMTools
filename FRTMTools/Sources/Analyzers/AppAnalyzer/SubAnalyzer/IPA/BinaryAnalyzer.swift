//
//  BinaryAnalyzer.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 01/10/25.
//


import Foundation

class BinaryAnalyzer {
    func isBinaryStripped(at binaryURL: URL) -> Bool {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tempCopy = tempDir.appendingPathComponent(binaryURL.lastPathComponent)

        func run(_ tool: String, _ args: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            try p.run()
            p.waitUntilExit()
            let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (p.terminationStatus, outStr, errStr)
        }

        func sha1(of url: URL) throws -> String {
            // Prefer /usr/bin/shasum (macOS). If unavailable, try sha1sum.
            if fm.isReadableFile(atPath: "/usr/bin/shasum") {
                let result = try run("/usr/bin/shasum", ["-a", "1", url.path])
                guard result.status == 0 else { throw NSError(domain: "sha1", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: result.stderr]) }
                return result.stdout.split(separator: " ").first.map(String.init) ?? ""
            } else if let sha1sum = ["/opt/homebrew/bin/sha1sum", "/usr/local/bin/sha1sum"].first(where: { fm.isReadableFile(atPath: $0) }) {
                let result = try run(sha1sum, [url.path])
                guard result.status == 0 else { throw NSError(domain: "sha1", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: result.stderr]) }
                return result.stdout.split(separator: " ").first.map(String.init) ?? ""
            } else {
                throw NSError(domain: "sha1", code: -1, userInfo: [NSLocalizedDescriptionKey: "No shasum/sha1sum found"])
            }
        }

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try fm.copyItem(at: binaryURL, to: tempCopy)

            // Ensure we clean up even on early returns/errors.
            defer {
                try? fm.removeItem(at: tempDir)
            }

            let pre = try sha1(of: tempCopy)

            // Strip in place: strip -rSTx <copy>
            let stripRes = try run("/usr/bin/strip", ["-rSTx", tempCopy.path])
            // Some binaries may already be fully stripped; strip can still exit 0 or 1 depending on toolchain.
            // Treat non-zero as "no change possible" only if the file still exists.
            if stripRes.status != 0 && !fm.fileExists(atPath: tempCopy.path) {
                // Something went wrong: no file to compare.
                return false
            }

            let post = try sha1(of: tempCopy)
            
            // If hashes are identical, stripping made no byte-level change => already stripped.
            return pre == post
        } catch {
            // On any failure, fall back to "not sure; assume not stripped"
            return false
        }
    }

}

