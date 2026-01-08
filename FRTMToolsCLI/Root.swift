//
//  Root.swift
//  FRTMToolsCLI
//
//  Created by PALOMBA VALENTINO on 02/12/25.
//

import Foundation
import Dispatch

@main
struct FRTMToolsCLI {
    static func main() async {
        let command = DashboardCommand(arguments: CommandLine.arguments)
        let exitCode = await command.run()
        exit(exitCode)
    }
}

private final class DashboardCommand {
    private let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run() async -> Int32 {
        do {
            let configuration = try parseArguments()
            log("Mode: \(configuration.command.rawValue.uppercased())")
            if let inputURL = configuration.inputURL {
                log("Input: \(inputURL.path)")
            }
            if let secondary = configuration.secondaryInputURL {
                log("Input (compare): \(secondary.path)")
            }
            if let outputURL = configuration.outputURL {
                log("Output: \(outputURL.path)")
            }

            if configuration.command == .serve {
                let config = configuration.serverConfiguration ?? DashboardServer.Configuration(host: "127.0.0.1", port: 8765, openBrowser: true, dataDirectoryOverride: nil)
                let server = DashboardServer(configuration: config)
                let url = try await server.start()
                print("Dashboard server running at \(url.absoluteString)")
                withExtendedLifetime(server) { _ = DispatchSemaphore(value: 0).wait(timeout: .distantFuture) }
                return 0
            }

            let html: String
            switch configuration.command {
            case .ipa:
                guard let inputURL = configuration.inputURL, configuration.outputURL != nil else {
                    throw CLIError.invalidArguments("Missing input or output path.")
                }
                let analyzer = IPAAnalyzer()
                log("Starting IPA analysis…")
                guard let analysis = try await analyzer.analyze(at: inputURL) else {
                    throw CLIError.unsupportedFile("Unable to analyze file at \(inputURL.path). Make sure it is a valid IPA or .app bundle.")
                }
                log("Analysis completed. Building dashboard…")
                html = AppDashboardHTMLBuilder(platform: .ipa(analysis)).build()
            case .apk:
                guard let inputURL = configuration.inputURL, configuration.outputURL != nil else {
                    throw CLIError.invalidArguments("Missing input or output path.")
                }
                let analyzer = APKAnalyzer()
                log("Starting APK analysis…")
                guard let analysis = try await analyzer.analyze(at: inputURL) else {
                    throw CLIError.unsupportedFile("Unable to analyze file at \(inputURL.path). Make sure it is a valid APK or AAB.")
                }
                log("Analysis completed. Building dashboard…")
                html = AppDashboardHTMLBuilder(platform: .apk(analysis)).build()
            case .compare:
                guard let inputURL = configuration.inputURL, configuration.outputURL != nil else {
                    throw CLIError.invalidArguments("Missing input or output path.")
                }
                guard let secondaryURL = configuration.secondaryInputURL else {
                    throw CLIError.invalidArguments("Comparison requires two input packages.")
                }
                let firstPlatform = try detectPlatform(for: inputURL)
                let secondPlatform = try detectPlatform(for: secondaryURL)
                guard firstPlatform == secondPlatform else {
                    throw CLIError.invalidArguments("Both packages must belong to the same platform (IPA vs IPA or APK/AAB).")
                }
                switch firstPlatform {
                case .ipa:
                    log("Analyzing first IPA build…")
                    let firstAnalyzer = IPAAnalyzer()
                    guard let before = try await firstAnalyzer.analyze(at: inputURL) else {
                        throw CLIError.unsupportedFile("Unable to analyze file at \(inputURL.path). Make sure it is a valid IPA or .app bundle.")
                    }
                    log("Analyzing second IPA build…")
                    let secondAnalyzer = IPAAnalyzer()
                    guard let after = try await secondAnalyzer.analyze(at: secondaryURL) else {
                        throw CLIError.unsupportedFile("Unable to analyze file at \(secondaryURL.path). Make sure it is a valid IPA or .app bundle.")
                    }
                    log("Building comparison dashboard…")
                    html = ComparisonDashboardHTMLBuilder(platform: .ipa(before, after)).build()
                case .apk:
                    log("Analyzing first Android build…")
                    let firstAnalyzer = APKAnalyzer()
                    guard let before = try await firstAnalyzer.analyze(at: inputURL) else {
                        throw CLIError.unsupportedFile("Unable to analyze file at \(inputURL.path). Make sure it is a valid APK or AAB.")
                    }
                    log("Analyzing second Android build…")
                    let secondAnalyzer = APKAnalyzer()
                    guard let after = try await secondAnalyzer.analyze(at: secondaryURL) else {
                        throw CLIError.unsupportedFile("Unable to analyze file at \(secondaryURL.path). Make sure it is a valid APK or AAB.")
                    }
                    log("Building comparison dashboard…")
                    html = ComparisonDashboardHTMLBuilder(platform: .apk(before, after)).build()
                }
            case .serve:
                throw CLIError.invalidArguments("Serve is handled separately.")
            }

            guard let outputURL = configuration.outputURL else {
                throw CLIError.invalidArguments("Missing output path.")
            }
            try ensureParentFolderExists(for: outputURL)
            try html.write(to: outputURL, atomically: true, encoding: .utf8)

            print("Dashboard generated at \(outputURL.path)")
            return 0
        } catch CLIError.helpRequested {
            printUsage()
            return 0
        } catch CLIError.invalidArguments(let message) {
            fputs("Error: \(message)\n\n", stderr)
            printUsage()
            return 1
        } catch CLIError.unsupportedFile(let message) {
            fputs("Error: \(message)\n", stderr)
            return 2
        } catch {
            fputs("Unexpected error: \(error.localizedDescription)\n", stderr)
            return 3
        }
    }

    private func parseArguments() throws -> Configuration {
        var args = Array(arguments.dropFirst())
        guard let commandString = args.first else {
            throw CLIError.helpRequested
        }
        guard let command = Command(rawValue: commandString.lowercased()) else {
            throw CLIError.invalidArguments("Unknown command '\(commandString)'. Expected 'ipa', 'apk', 'compare', or 'serve'.")
        }
        args.removeFirst()

        if command == .serve {
            var host = "127.0.0.1"
            var port: UInt16 = 8765
            var openBrowser = true
            var dataDir: String?

            var index = 0
            while index < args.count {
                let argument = args[index]
                switch argument {
                case "-h", "--help":
                    throw CLIError.helpRequested
                case "--host":
                    index += 1
                    guard index < args.count else { throw CLIError.invalidArguments("Missing value for \(argument).") }
                    host = args[index]
                case "--port":
                    index += 1
                    guard index < args.count else { throw CLIError.invalidArguments("Missing value for \(argument).") }
                    guard let intPort = UInt16(args[index]) else {
                        throw CLIError.invalidArguments("Invalid port: \(args[index]).")
                    }
                    port = intPort
                case "--no-open":
                    openBrowser = false
                case "--data-dir":
                    index += 1
                    guard index < args.count else { throw CLIError.invalidArguments("Missing value for \(argument).") }
                    dataDir = args[index]
                default:
                    throw CLIError.invalidArguments("Unknown option '\(argument)' for serve.")
                }
                index += 1
            }

            let dataURL = dataDir.map { URL(fileURLWithPath: $0).standardizedFileURL }
            return Configuration(
                command: command,
                inputURL: nil,
                secondaryInputURL: nil,
                outputURL: nil,
                serverConfiguration: DashboardServer.Configuration(host: host, port: port, openBrowser: openBrowser, dataDirectoryOverride: dataURL)
            )
        }

        var outputPath: String?
        var inputPaths: [String] = []

        var index = 0
        while index < args.count {
            let argument = args[index]
            switch argument {
            case "-h", "--help":
                throw CLIError.helpRequested
            case "-o", "--output":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for \(argument).")
                }
                outputPath = args[index]
            default:
                inputPaths.append(argument)
            }
            index += 1
        }

        switch command {
        case .compare:
            if inputPaths.count != 2 {
                throw CLIError.invalidArguments("Please provide exactly two package paths when using the compare command.")
            }
        case .ipa, .apk:
            if inputPaths.count != 1 {
                throw CLIError.invalidArguments("Please provide the path to the package you want to analyze.")
            }
        case .serve:
            break
        }

        guard let primaryPath = inputPaths.first else {
            throw CLIError.invalidArguments("Missing input path.")
        }

        let fileManager = FileManager.default
        let inputURL = URL(fileURLWithPath: primaryPath).standardizedFileURL
        guard fileManager.fileExists(atPath: inputURL.path) else {
            throw CLIError.invalidArguments("No file found at \(inputURL.path).")
        }

        var secondaryURL: URL?
        if command == .compare {
            let comparePath = inputPaths[1]
            let compareURL = URL(fileURLWithPath: comparePath).standardizedFileURL
            guard fileManager.fileExists(atPath: compareURL.path) else {
                throw CLIError.invalidArguments("No file found at \(compareURL.path).")
            }
            secondaryURL = compareURL
        }

        let resolvedOutputURL: URL
        if let customOutput = outputPath {
            resolvedOutputURL = URL(fileURLWithPath: customOutput).standardizedFileURL
        } else {
            switch command {
            case .ipa, .apk:
                let suffix = "-\(command.rawValue)-dashboard.html"
                let suggestedName = inputURL.deletingPathExtension().lastPathComponent + suffix
                resolvedOutputURL = inputURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(suggestedName)
            case .compare:
                guard let secondaryURL else {
                    throw CLIError.invalidArguments("Comparison requires two inputs.")
                }
                let firstName = inputURL.deletingPathExtension().lastPathComponent
                let secondName = secondaryURL.deletingPathExtension().lastPathComponent
                let suggestedName = "\(firstName)-vs-\(secondName)-compare.html"
                resolvedOutputURL = inputURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(suggestedName)
            case .serve:
                throw CLIError.invalidArguments("Serve does not write an HTML file. Did you mean: \(arguments.first ?? "frtmtools") serve")
            }
        }

        return Configuration(command: command, inputURL: inputURL, secondaryInputURL: secondaryURL, outputURL: resolvedOutputURL, serverConfiguration: nil)
    }

    private func ensureParentFolderExists(for fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func printUsage() {
        let commandName = (arguments.first as NSString?)?.lastPathComponent ?? "FRTMToolsCLI"
        let message = """
        Usage:
          \(commandName) ipa <path-to-ipa-or-app> [--output <path>]
          \(commandName) apk <path-to-apk-or-aab> [--output <path>]
          \(commandName) compare <first-package> <second-package> [--output <path>]
          \(commandName) serve [--port <port>] [--host <host>] [--no-open] [--data-dir <path>]

        Options:
          -o, --output <path>   Write the generated HTML dashboard to the provided path.
          -h, --help            Show this message.
          --port <port>         Port for the local dashboard server (default: 8765).
          --host <host>         Host for the local dashboard server (default: 127.0.0.1).
          --no-open             Do not auto-open the browser.
          --data-dir <path>     Override dashboard persistent storage directory.

        Examples:
          \(commandName) ipa Payload/MyApp.ipa --output /tmp/MyApp-dashboard.html
          \(commandName) apk ~/Downloads/sample.apk
          \(commandName) compare build-old.ipa build-new.ipa --output ~/Desktop/comparison.html
          \(commandName) serve --port 8765
        """
        print(message)
    }

    private func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }
}

private extension DashboardCommand {
    struct Configuration {
        let command: Command
        let inputURL: URL?
        let secondaryInputURL: URL?
        let outputURL: URL?
        let serverConfiguration: DashboardServer.Configuration?
    }

    enum Command: String {
        case ipa
        case apk
        case compare
        case serve
    }

    enum PackagePlatform {
        case ipa
        case apk
    }

    func detectPlatform(for url: URL) throws -> PackagePlatform {
        let ext = url.pathExtension.lowercased()
        if ["ipa", "app"].contains(ext) {
            return .ipa
        }
        if ["apk", "aab", "abb"].contains(ext) {
            return .apk
        }
        throw CLIError.invalidArguments("Unable to detect the package type for \(url.path). For single dashboards use the 'ipa' or 'apk' commands explicitly.")
    }

    enum CLIError: Error {
        case invalidArguments(String)
        case unsupportedFile(String)
        case helpRequested
    }
}
