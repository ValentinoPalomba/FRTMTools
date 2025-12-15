//
//  Root.swift
//  FRTMToolsCLI
//
//  Created by PALOMBA VALENTINO on 02/12/25.
//

import Foundation

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
            log("Input: \(configuration.inputURL.path)")
            if let secondary = configuration.secondaryInputURL {
                log("Input (compare): \(secondary.path)")
            }
            log("Output: \(configuration.outputURL.path)")

            let html: String
            switch configuration.command {
            case .ipa:
                let analyzer = IPAAnalyzer()
                log("Starting IPA analysis…")
                guard let analysis = try await analyzer.analyze(at: configuration.inputURL) else {
                    throw CLIError.unsupportedFile("Unable to analyze file at \(configuration.inputURL.path). Make sure it is a valid IPA or .app bundle.")
                }
                log("Analysis completed. Building dashboard…")
                html = AppDashboardHTMLBuilder(platform: .ipa(analysis)).build()
            case .apk:
                let analyzer = APKAnalyzer()
                log("Starting APK analysis…")
                guard let analysis = try await analyzer.analyze(at: configuration.inputURL) else {
                    throw CLIError.unsupportedFile("Unable to analyze file at \(configuration.inputURL.path). Make sure it is a valid APK or AAB.")
                }
                log("Analysis completed. Building dashboard…")
                html = AppDashboardHTMLBuilder(platform: .apk(analysis)).build()
            case .compare:
                guard let secondaryURL = configuration.secondaryInputURL else {
                    throw CLIError.invalidArguments("Comparison requires two input packages.")
                }
                let firstPlatform = try detectPlatform(for: configuration.inputURL)
                let secondPlatform = try detectPlatform(for: secondaryURL)
                guard firstPlatform == secondPlatform else {
                    throw CLIError.invalidArguments("Both packages must belong to the same platform (IPA vs IPA or APK/AAB).")
                }
                switch firstPlatform {
                case .ipa:
                    log("Analyzing first IPA build…")
                    let firstAnalyzer = IPAAnalyzer()
                    guard let before = try await firstAnalyzer.analyze(at: configuration.inputURL) else {
                        throw CLIError.unsupportedFile("Unable to analyze file at \(configuration.inputURL.path). Make sure it is a valid IPA or .app bundle.")
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
                    guard let before = try await firstAnalyzer.analyze(at: configuration.inputURL) else {
                        throw CLIError.unsupportedFile("Unable to analyze file at \(configuration.inputURL.path). Make sure it is a valid APK or AAB.")
                    }
                    log("Analyzing second Android build…")
                    let secondAnalyzer = APKAnalyzer()
                    guard let after = try await secondAnalyzer.analyze(at: secondaryURL) else {
                        throw CLIError.unsupportedFile("Unable to analyze file at \(secondaryURL.path). Make sure it is a valid APK or AAB.")
                    }
                    log("Building comparison dashboard…")
                    html = ComparisonDashboardHTMLBuilder(platform: .apk(before, after)).build()
                }
            }

            try ensureParentFolderExists(for: configuration.outputURL)
            try html.write(to: configuration.outputURL, atomically: true, encoding: .utf8)

            print("Dashboard generated at \(configuration.outputURL.path)")
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
            throw CLIError.invalidArguments("Unknown command '\(commandString)'. Expected 'ipa', 'apk', or 'compare'.")
        }
        args.removeFirst()

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
            }
        }

        return Configuration(command: command, inputURL: inputURL, secondaryInputURL: secondaryURL, outputURL: resolvedOutputURL)
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

        Options:
          -o, --output <path>   Write the generated HTML dashboard to the provided path.
          -h, --help            Show this message.

        Examples:
          \(commandName) ipa Payload/MyApp.ipa --output /tmp/MyApp-dashboard.html
          \(commandName) apk ~/Downloads/sample.apk
          \(commandName) compare build-old.ipa build-new.ipa --output ~/Desktop/comparison.html
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
        let inputURL: URL
        let secondaryInputURL: URL?
        let outputURL: URL
    }

    enum Command: String {
        case ipa
        case apk
        case compare
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
