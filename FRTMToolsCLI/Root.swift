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
            throw CLIError.invalidArguments("Unknown command '\(commandString)'. Expected 'ipa' or 'apk'.")
        }
        args.removeFirst()

        var outputPath: String?
        var inputPath: String?

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
                if inputPath == nil {
                    inputPath = argument
                } else {
                    throw CLIError.invalidArguments("Unexpected argument: \(argument)")
                }
            }
            index += 1
        }

        guard let resolvedInput = inputPath, !resolvedInput.isEmpty else {
            throw CLIError.invalidArguments("Please provide the path to the package you want to analyze.")
        }

        let fileManager = FileManager.default
        let inputURL = URL(fileURLWithPath: resolvedInput).standardizedFileURL
        guard fileManager.fileExists(atPath: inputURL.path) else {
            throw CLIError.invalidArguments("No file found at \(inputURL.path).")
        }

        let resolvedOutputURL: URL
        if let customOutput = outputPath {
            resolvedOutputURL = URL(fileURLWithPath: customOutput).standardizedFileURL
        } else {
            let suffix = "-\(command.rawValue)-dashboard.html"
            let suggestedName = inputURL.deletingPathExtension().lastPathComponent + suffix
            resolvedOutputURL = inputURL
                .deletingLastPathComponent()
                .appendingPathComponent(suggestedName)
        }

        return Configuration(command: command, inputURL: inputURL, outputURL: resolvedOutputURL)
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

        Options:
          -o, --output <path>   Write the generated HTML dashboard to the provided path.
          -h, --help            Show this message.

        Examples:
          \(commandName) ipa Payload/MyApp.ipa --output /tmp/MyApp-dashboard.html
          \(commandName) apk ~/Downloads/sample.apk
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
        let outputURL: URL
    }

    enum Command: String {
        case ipa
        case apk
    }

    enum CLIError: Error {
        case invalidArguments(String)
        case unsupportedFile(String)
        case helpRequested
    }
}
