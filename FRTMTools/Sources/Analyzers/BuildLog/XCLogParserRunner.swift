import Foundation

struct XCLogParserOptions {
    var fileURL: URL?
    var projectName: String?
    var workspaceURL: URL?
    var xcodeprojURL: URL?
    var derivedDataURL: URL?
    var outputURL: URL?
    var rootOutputURL: URL?
    var redacted: Bool = false
    var withoutBuildSpecificInfo: Bool = false
    var strictProjectName: Bool = false
    var machineName: String?
    var omitWarnings: Bool = false
    var omitNotes: Bool = false
    var truncLargeIssues: Bool = false

    init(
        fileURL: URL? = nil,
        projectName: String? = nil,
        workspaceURL: URL? = nil,
        xcodeprojURL: URL? = nil,
        derivedDataURL: URL? = nil,
        outputURL: URL? = nil,
        rootOutputURL: URL? = nil,
        redacted: Bool = false,
        withoutBuildSpecificInfo: Bool = false,
        strictProjectName: Bool = false,
        machineName: String? = nil,
        omitWarnings: Bool = false,
        omitNotes: Bool = false,
        truncLargeIssues: Bool = false
    ) {
        self.fileURL = fileURL
        self.projectName = projectName
        self.workspaceURL = workspaceURL
        self.xcodeprojURL = xcodeprojURL
        self.derivedDataURL = derivedDataURL
        self.outputURL = outputURL
        self.rootOutputURL = rootOutputURL
        self.redacted = redacted
        self.withoutBuildSpecificInfo = withoutBuildSpecificInfo
        self.strictProjectName = strictProjectName
        self.machineName = machineName
        self.omitWarnings = omitWarnings
        self.omitNotes = omitNotes
        self.truncLargeIssues = truncLargeIssues
    }
}

enum XCLogParserStepType: String, Decodable {
    case main
    case target
    case detail

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = XCLogParserStepType(rawValue: rawValue) ?? .detail
    }
}

enum XCLogParserDetailStepType: String, Decodable {
    case cCompilation
    case swiftCompilation
    case scriptExecution
    case createStaticLibrary
    case linker
    case copySwiftLibs
    case compileAssetsCatalog
    case compileStoryboard
    case writeAuxiliaryFile
    case linkStoryboards
    case copyResourceFile
    case mergeSwiftModule
    case XIBCompilation
    case swiftAggregatedCompilation
    case precompileBridgingHeader
    case validate
    case other
    case none

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = XCLogParserDetailStepType(rawValue: rawValue) ?? .other
    }
}

struct XCLogParserSwiftFunctionTime: Decodable {
    let durationMS: Double
    let occurrences: Int
    let startingColumn: Int
    let startingLine: Int
    let file: String
    let signature: String
}

struct XCLogParserSwiftTypeCheckTime: Decodable {
    let durationMS: Double
    let occurrences: Int
    let startingColumn: Int
    let startingLine: Int
    let file: String
}

struct XCLogParserStep: Decodable {
    let detailStepType: XCLogParserDetailStepType?
    let startTimestamp: Double?
    let endTimestamp: Double?
    let schema: String?
    let domain: String?
    let parentIdentifier: String?
    let endDate: String?
    let title: String?
    let identifier: String?
    let signature: String?
    let type: XCLogParserStepType
    let buildStatus: String?
    let subSteps: [XCLogParserStep]
    let startDate: String?
    let buildIdentifier: String?
    let machineName: String?
    let duration: Double?
    let errorCount: Int?
    let warningCount: Int?
    let errors: JSONValue?
    let warnings: JSONValue?
    let notes: JSONValue?
    let fetchedFromCache: Bool?
    let compilationEndTimestamp: Double?
    let compilationDuration: Double?
    let swiftFunctionTimes: [XCLogParserSwiftFunctionTime]?
    let swiftTypeCheckTimes: [XCLogParserSwiftTypeCheckTime]?

    private enum CodingKeys: String, CodingKey {
        case detailStepType
        case startTimestamp
        case endTimestamp
        case schema
        case domain
        case parentIdentifier
        case endDate
        case title
        case identifier
        case signature
        case type
        case buildStatus
        case subSteps
        case startDate
        case buildIdentifier
        case machineName
        case duration
        case errorCount
        case warningCount
        case errors
        case warnings
        case notes
        case fetchedFromCache
        case compilationEndTimestamp
        case compilationDuration
        case swiftFunctionTimes
        case swiftTypeCheckTimes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detailStepType = try container.decodeIfPresent(XCLogParserDetailStepType.self, forKey: .detailStepType)
        startTimestamp = try container.decodeIfPresent(Double.self, forKey: .startTimestamp)
        endTimestamp = try container.decodeIfPresent(Double.self, forKey: .endTimestamp)
        schema = try container.decodeIfPresent(String.self, forKey: .schema)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        parentIdentifier = try container.decodeIfPresent(String.self, forKey: .parentIdentifier)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        signature = try container.decodeIfPresent(String.self, forKey: .signature)
        type = try container.decode(XCLogParserStepType.self, forKey: .type)
        buildStatus = try container.decodeIfPresent(String.self, forKey: .buildStatus)
        subSteps = try container.decodeIfPresent([XCLogParserStep].self, forKey: .subSteps) ?? []
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        buildIdentifier = try container.decodeIfPresent(String.self, forKey: .buildIdentifier)
        machineName = try container.decodeIfPresent(String.self, forKey: .machineName)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        errorCount = try container.decodeIfPresent(Int.self, forKey: .errorCount)
        warningCount = try container.decodeIfPresent(Int.self, forKey: .warningCount)
        errors = try container.decodeIfPresent(JSONValue.self, forKey: .errors)
        warnings = try container.decodeIfPresent(JSONValue.self, forKey: .warnings)
        notes = try container.decodeIfPresent(JSONValue.self, forKey: .notes)
        fetchedFromCache = try container.decodeIfPresent(Bool.self, forKey: .fetchedFromCache)
        compilationEndTimestamp = try container.decodeIfPresent(Double.self, forKey: .compilationEndTimestamp)
        compilationDuration = try container.decodeIfPresent(Double.self, forKey: .compilationDuration)
        swiftFunctionTimes = try container.decodeIfPresent([XCLogParserSwiftFunctionTime].self, forKey: .swiftFunctionTimes)
        swiftTypeCheckTimes = try container.decodeIfPresent([XCLogParserSwiftTypeCheckTime].self, forKey: .swiftTypeCheckTimes)
    }
}

enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}

final class XCLogParserRunner: Sendable {
    struct JSONResult {
        let steps: [XCLogParserStep]
        let outputURL: URL
    }
    enum RunnerError: LocalizedError {
        case executableNotFound
        case invalidInput(String)
        case commandFailed(exitCode: Int32, output: String, error: String)
        case invalidOutput(String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "xclogparser executable not found in the app bundle."
            case .invalidInput(let message):
                return message
            case .commandFailed(let code, let out, let err):
                return "xclogparser failed (code \(code)).\n\nOutput:\n\(out)\n\nError:\n\(err)"
            case .invalidOutput(let message):
                return message
            }
        }
    }

    func parseJSON(options: XCLogParserOptions) async throws -> JSONResult {
        let executableURL = try resolveExecutableURL()
        try validateInput(options)

        let outputURL = try resolveOutputURL(for: options)
        let arguments = buildArguments(options: options, outputURL: outputURL)

        let (_, _) = try await run(executableURL: executableURL, arguments: arguments)
        let steps = try decodeSteps(from: outputURL)
        return JSONResult(steps: steps, outputURL: outputURL)
    }

    // MARK: - Argument building

    private func buildArguments(options: XCLogParserOptions, outputURL: URL) -> [String] {
        var args = ["parse", "--reporter", "json"]

        if let fileURL = options.fileURL {
            args += ["--file", fileURL.path]
        }
        if let projectName = options.projectName, !projectName.isEmpty {
            args += ["--project", projectName]
        }
        if let workspaceURL = options.workspaceURL {
            args += ["--workspace", workspaceURL.path]
        }
        if let xcodeprojURL = options.xcodeprojURL {
            args += ["--xcodeproj", xcodeprojURL.path]
        }
        if let derivedDataURL = options.derivedDataURL {
            args += ["--derived_data", derivedDataURL.path]
        }

        if let rootOutputURL = options.rootOutputURL {
            args += ["--rootOutput", rootOutputURL.path]
        } else {
            args += ["--output", outputURL.path]
        }

        if options.redacted { args.append("--redacted") }
        if options.withoutBuildSpecificInfo { args.append("--without_build_specific_info") }
        if options.strictProjectName { args.append("--strictProjectName") }
        if let machineName = options.machineName, !machineName.isEmpty {
            args += ["--machine_name", machineName]
        }
        if options.omitWarnings { args.append("--omit_warnings") }
        if options.omitNotes { args.append("--omit_notes") }
        if options.truncLargeIssues { args.append("--trunc_large_issues") }

        return args
    }

    private func validateInput(_ options: XCLogParserOptions) throws {
        if options.fileURL == nil,
           options.projectName?.isEmpty ?? true,
           options.workspaceURL == nil,
           options.xcodeprojURL == nil {
            throw RunnerError.invalidInput("Provide at least one of --file, --project, --workspace, or --xcodeproj.")
        }

        if let fileURL = options.fileURL, !FileManager.default.fileExists(atPath: fileURL.path) {
            throw RunnerError.invalidInput("xcactivitylog not found at \(fileURL.path).")
        }
        if let workspaceURL = options.workspaceURL, !FileManager.default.fileExists(atPath: workspaceURL.path) {
            throw RunnerError.invalidInput("xcworkspace not found at \(workspaceURL.path).")
        }
        if let xcodeprojURL = options.xcodeprojURL, !FileManager.default.fileExists(atPath: xcodeprojURL.path) {
            throw RunnerError.invalidInput("xcodeproj not found at \(xcodeprojURL.path).")
        }
        if let derivedDataURL = options.derivedDataURL, !FileManager.default.fileExists(atPath: derivedDataURL.path) {
            throw RunnerError.invalidInput("DerivedData not found at \(derivedDataURL.path).")
        }
        if options.rootOutputURL != nil {
            throw RunnerError.invalidInput("--rootOutput is only valid with the html reporter.")
        }
    }

    private func resolveOutputURL(for options: XCLogParserOptions) throws -> URL {
        if let outputURL = options.outputURL {
            try ensureParentDirectoryExists(for: outputURL)
            return outputURL
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FRTMTools", isDirectory: true)
        try ensureDirectoryExists(at: tempDir)
        return tempDir.appendingPathComponent("xclogparser-\(UUID().uuidString).json")
    }

    private func ensureDirectoryExists(at url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func ensureParentDirectoryExists(for url: URL) throws {
        try ensureDirectoryExists(at: url.deletingLastPathComponent())
    }

    // MARK: - Executable resolution

    private func resolveExecutableURL() throws -> URL {
        let fm = FileManager.default
        let bundle = Bundle.main

        let candidates: [URL] = [
            bundle.url(forResource: "xclogparser", withExtension: nil, subdirectory: "ExternalFrameworks"),
            bundle.url(forResource: "xclogparser", withExtension: nil),
            bundle.resourceURL?.appendingPathComponent("ExternalFrameworks/xclogparser"),
            bundle.resourceURL?.appendingPathComponent("xclogparser"),
            URL(fileURLWithPath: "ExternalFrameworks/xclogparser")
        ].compactMap { $0 }

        for candidate in candidates where fm.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw RunnerError.executableNotFound
    }

    // MARK: - Process

    private func run(executableURL: URL, arguments: [String]) async throws -> (String, String) {
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
            throw RunnerError.commandFailed(exitCode: process.terminationStatus, output: out, error: err)
        }

        return (out, err)
    }

    private func decodeSteps(from url: URL) throws -> [XCLogParserStep] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        if let steps = try? decoder.decode([XCLogParserStep].self, from: data) {
            return steps
        }
        if let step = try? decoder.decode(XCLogParserStep.self, from: data) {
            return [step]
        }
        if let container = try? decoder.decode(XCLogParserStepsContainer.self, from: data) {
            return container.steps
        }
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let steps = decodeSteps(from: json, decoder: decoder) {
                return steps
            }
        }

        throw RunnerError.invalidOutput("Unable to decode xclogparser JSON from \(url.path).")
    }

    private func decodeSteps(from json: Any, decoder: JSONDecoder) -> [XCLogParserStep]? {
        if let array = json as? [Any] {
            if let steps = decodeStepsFromArray(array, decoder: decoder) {
                return steps
            }
            for item in array {
                if let steps = decodeSteps(from: item, decoder: decoder) {
                    return steps
                }
            }
        }

        if let dict = json as? [String: Any] {
            if dict["type"] != nil, let steps = decodeStepsFromDict(dict, decoder: decoder) {
                return steps
            }

            for key in ["steps", "buildSteps", "build", "main", "targets", "result"] {
                if let value = dict[key], let steps = decodeSteps(from: value, decoder: decoder) {
                    return steps
                }
            }

            for value in dict.values {
                if let steps = decodeSteps(from: value, decoder: decoder) {
                    return steps
                }
            }
        }

        return nil
    }

    private func decodeStepsFromArray(_ array: [Any], decoder: JSONDecoder) -> [XCLogParserStep]? {
        if let data = try? JSONSerialization.data(withJSONObject: array, options: []) {
            if let steps = try? decoder.decode([XCLogParserStep].self, from: data) {
                return steps
            }
        }

        let filtered = array.compactMap { $0 as? [String: Any] }.filter { $0["type"] != nil }
        if !filtered.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: filtered, options: []),
           let steps = try? decoder.decode([XCLogParserStep].self, from: data) {
            return steps
        }

        return nil
    }

    private func decodeStepsFromDict(_ dict: [String: Any], decoder: JSONDecoder) -> [XCLogParserStep]? {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let step = try? decoder.decode(XCLogParserStep.self, from: data) {
            return [step]
        }
        return nil
    }
}

private struct XCLogParserStepsContainer: Decodable {
    let steps: [XCLogParserStep]
}
