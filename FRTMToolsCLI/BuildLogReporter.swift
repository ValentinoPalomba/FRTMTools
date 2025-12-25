import Foundation

final class BuildLogReporter {
    func generateReport(from inputURL: URL, outputURL: URL) throws -> URL {
        let xclogparserURL = try locateXcLogParser(near: inputURL)
        let input = try resolveInputArgument(for: inputURL)
        let resolvedOutputURL = try resolveOutputURL(outputURL)
        try prepareOutputLocation(resolvedOutputURL)
        let jsonOutputURL = resolvedOutputURL.deletingLastPathComponent().appendingPathComponent("buildlog.json")

        let arguments = [
            "parse",
            "--reporter", "json",
            input.flag, input.url.path,
            "--output", jsonOutputURL.path
        ]

        _ = try run(executableURL: xclogparserURL, arguments: arguments)
        let data = try Data(contentsOf: jsonOutputURL)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        let report = BuildLogReportParser().parse(json: jsonObject)
        let builder = BuildLogDashboardHTMLBuilder(
            report: report,
            sourceName: inputURL.deletingPathExtension().lastPathComponent,
            sourcePath: inputURL.path
        )
        let html = builder.build()
        try html.write(to: resolvedOutputURL, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: jsonOutputURL)
        return resolvedOutputURL
    }

    private func locateXcLogParser(near inputURL: URL) throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let overridePath = ProcessInfo.processInfo.environment["FRTMTOOLS_XCLOGPARSER_PATH"] {
            candidates.append(URL(fileURLWithPath: overridePath))
        }

        if let bundledURL = Bundle.main.url(forResource: "xclogparser", withExtension: nil) {
            candidates.append(bundledURL)
        }

        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("xclogparser") {
            candidates.append(resourceURL)
        }

        candidates.append(Bundle.main.bundleURL.appendingPathComponent("xclogparser"))
        if let executablePath = ProcessInfo.processInfo.arguments.first {
            let executableURL = URL(fileURLWithPath: executablePath).standardizedFileURL
            let executableDir = executableURL.deletingLastPathComponent()
            candidates.append(executableDir.appendingPathComponent("xclogparser"))
            candidates.append(executableDir.appendingPathComponent("Resources/xclogparser"))
            candidates.append(contentsOf: bundledCandidates(near: executableDir))
        }
        candidates.append(inputURL.deletingLastPathComponent().appendingPathComponent("FRTMTools/Resources/xclogparser"))
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("FRTMTools/Resources/xclogparser"))

        for candidate in candidates {
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw CLIError.toolUnavailable(
            "xclogparser executable not found. Place it in the app bundle resources, next to the frtmtools binary, or set FRTMTOOLS_XCLOGPARSER_PATH."
        )
    }

    private func bundledCandidates(near directoryURL: URL) -> [URL] {
        let fileManager = FileManager.default
        var results: [URL] = []

        if let entries = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries where entry.pathExtension == "bundle" {
                if let bundle = Bundle(url: entry),
                   let bundledURL = bundle.url(forResource: "xclogparser", withExtension: nil) {
                    results.append(bundledURL)
                }
                let directCandidate = entry.appendingPathComponent("Contents/Resources/xclogparser")
                if fileManager.isExecutableFile(atPath: directCandidate.path) {
                    results.append(directCandidate)
                }
            }
        }

        return results
    }

    private func resolveInputArgument(for inputURL: URL) throws -> (flag: String, url: URL) {
        let fileManager = FileManager.default
        let ext = inputURL.pathExtension.lowercased()
        if ext == "xcactivitylog" {
            return (flag: "--file", url: inputURL)
        }
        if ext == "xcworkspace" {
            return (flag: "--workspace", url: inputURL)
        }
        if ext == "xcodeproj" {
            return (flag: "--xcodeproj", url: inputURL)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw CLIError.invalidArguments("No file found at \(inputURL.path).")
        }

        if isDirectory.boolValue {
            return (flag: "--project", url: inputURL)
        }

        throw CLIError.invalidArguments("Unsupported build log input at \(inputURL.path). Please provide a .xcactivitylog, .xcworkspace, or .xcodeproj.")
    }

    private func prepareOutputLocation(_ outputURL: URL) throws {
        let fileManager = FileManager.default
        let parent = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
    }

    private func resolveOutputURL(_ outputURL: URL) throws -> URL {
        let fileManager = FileManager.default
        if outputURL.pathExtension.lowercased() == "html" {
            return outputURL
        }
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return outputURL.appendingPathComponent("build-report.html")
        }
        return outputURL.appendingPathExtension("html")
    }


    private func run(executableURL: URL, arguments: [String]) throws -> (String, String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let message = err.isEmpty ? out : err
            throw CLIError.toolFailed("xclogparser failed with exit code \(process.terminationStatus). \(message)")
        }

        return (out, err)
    }
}
