import Foundation

enum DeadCodeRemovalStage: Sendable, Equatable {
    case applyingChanges
    case rebuilding
    case restoringSources
}

typealias DeadCodeRemovalProgressHandler = @Sendable (DeadCodeRemovalStage) -> Void

protocol DeadCodeRemoving: Sendable {
    func remove(
        _ request: DeadCodeRemovalRequest,
        progress: @escaping DeadCodeRemovalProgressHandler
    ) async throws -> DeadCodeRemovalOutcome
    func apply(
        _ request: DeadCodeDeclarationRemovalRequest,
        progress: @escaping DeadCodeRemovalProgressHandler
    ) async throws -> DeadCodeDeclarationRemovalOutcome
    func applyCluster(
        _ request: DeadCodeClusterRemovalRequest,
        progress: @escaping DeadCodeRemovalProgressHandler
    ) async throws -> DeadCodeClusterRemovalOutcome
}

struct DeadCodeRemovalRequest: Sendable {
    let fileURLs: [URL]
    let projectPath: String
    let scheme: String
    let validatesBuild: Bool
}

struct DeadCodeRemovalOutcome: Sendable {
    let removedFileURLs: [URL]
    let buildOutput: String
}

struct DeadCodeDeclarationRemovalRequest: Sendable {
    let fileURL: URL
    let originalSource: String
    let updatedSource: String
    let projectPath: String
    let scheme: String
    let validatesBuild: Bool
}

struct DeadCodeDeclarationRemovalOutcome: Sendable {
    let editedFileURL: URL
    let buildOutput: String
}

struct DeadCodeClusterRemovalRequest: Sendable {
    let removedFileURLs: [URL]
    let sourceEdits: [DeadCodeSourceEdit]
    let projectPath: String
    let scheme: String
    let validatesBuild: Bool
}

struct DeadCodeClusterRemovalOutcome: Sendable {
    let affectedFileURLs: [URL]
    let buildOutput: String
}

struct DeadCodeRemovalService: DeadCodeRemoving {
    func remove(
        _ request: DeadCodeRemovalRequest,
        progress: @escaping DeadCodeRemovalProgressHandler
    ) async throws -> DeadCodeRemovalOutcome {
        try await Task.detached(priority: .userInitiated) {
            try Self.removeSynchronously(request, progress: progress)
        }.value
    }

    func apply(
        _ request: DeadCodeDeclarationRemovalRequest,
        progress: @escaping DeadCodeRemovalProgressHandler
    ) async throws -> DeadCodeDeclarationRemovalOutcome {
        try await Task.detached(priority: .userInitiated) {
            try Self.applySynchronously(request, progress: progress)
        }.value
    }

    func applyCluster(
        _ request: DeadCodeClusterRemovalRequest,
        progress: @escaping DeadCodeRemovalProgressHandler
    ) async throws -> DeadCodeClusterRemovalOutcome {
        try await Task.detached(priority: .userInitiated) {
            try Self.applyClusterSynchronously(request, progress: progress)
        }.value
    }

    private static func removeSynchronously(
        _ request: DeadCodeRemovalRequest,
        progress: DeadCodeRemovalProgressHandler
    ) throws -> DeadCodeRemovalOutcome {
        let fileManager = FileManager.default
        let projectURL = resolvedBuildContainer(
            from: URL(fileURLWithPath: request.projectPath).standardizedFileURL
        )
        let projectRoot = projectURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let fileURLs = Array(Set(request.fileURLs.map { $0.standardizedFileURL }))

        guard !fileURLs.isEmpty else {
            throw DeadCodeRemovalError.noFiles
        }

        for fileURL in fileURLs {
            guard fileURL.pathExtension.lowercased() == "swift",
                  fileURL.resolvingSymlinksInPath().isDescendant(of: projectRoot) else {
                throw DeadCodeRemovalError.outsideProject(fileURL)
            }

            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw DeadCodeRemovalError.fileMissing(fileURL)
            }
        }

        let metadataEdits = try DeadCodeProjectReferenceEditor.makeEdits(
            removing: fileURLs,
            projectRoot: projectRoot
        )
        try validateMetadataEdits(metadataEdits)
        let affectedURLs = fileURLs + metadataEdits.map(\.fileURL)
        let backupDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FRTMTools-DeadCode-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )

        let backups = try affectedURLs.enumerated().map { index, fileURL in
            let backupURL = backupDirectory
                .appendingPathComponent("\(index)-\(fileURL.lastPathComponent)")
            try fileManager.copyItem(at: fileURL, to: backupURL)
            return (original: fileURL, backup: backupURL)
        }

        do {
            progress(.applyingChanges)
            try applyMetadataEdits(metadataEdits)
            for fileURL in fileURLs {
                try fileManager.trashItem(at: fileURL, resultingItemURL: nil)
            }

            let buildOutput: String
            if request.validatesBuild {
                progress(.rebuilding)
                buildOutput = try build(
                    projectURL: projectURL,
                    scheme: request.scheme
                )
            } else {
                buildOutput = ""
            }
            try? fileManager.removeItem(at: backupDirectory)

            return DeadCodeRemovalOutcome(
                removedFileURLs: fileURLs,
                buildOutput: buildOutput
            )
        } catch {
            progress(.restoringSources)
            var rollbackFailures: [URL] = []

            for backup in backups {
                do {
                    if fileManager.fileExists(atPath: backup.original.path) {
                        try fileManager.removeItem(at: backup.original)
                    }
                    try fileManager.copyItem(at: backup.backup, to: backup.original)
                } catch {
                    rollbackFailures.append(backup.original)
                }
            }

            try? fileManager.removeItem(at: backupDirectory)

            guard rollbackFailures.isEmpty else {
                throw DeadCodeRemovalError.rollbackFailed(
                    files: rollbackFailures,
                    underlyingDescription: error.localizedDescription
                )
            }

            if let removalError = error as? DeadCodeRemovalError {
                throw removalError
            }
            throw DeadCodeRemovalError.buildFailed(error.localizedDescription)
        }
    }

    private static func applySynchronously(
        _ request: DeadCodeDeclarationRemovalRequest,
        progress: DeadCodeRemovalProgressHandler
    ) throws -> DeadCodeDeclarationRemovalOutcome {
        let fileURL = request.fileURL.standardizedFileURL
        let projectURL = resolvedBuildContainer(
            from: URL(fileURLWithPath: request.projectPath).standardizedFileURL
        )
        let projectRoot = projectURL.deletingLastPathComponent().resolvingSymlinksInPath()

        guard fileURL.pathExtension.lowercased() == "swift",
              fileURL.resolvingSymlinksInPath().isDescendant(of: projectRoot) else {
            throw DeadCodeRemovalError.outsideProject(fileURL)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DeadCodeRemovalError.fileMissing(fileURL)
        }

        let currentSource: String
        do {
            currentSource = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw DeadCodeRemovalError.unreadableSource(fileURL)
        }

        guard currentSource == request.originalSource else {
            throw DeadCodeRemovalError.staleSource(fileURL)
        }

        do {
            progress(.applyingChanges)
            try request.updatedSource.write(to: fileURL, atomically: true, encoding: .utf8)
            let buildOutput: String
            if request.validatesBuild {
                progress(.rebuilding)
                buildOutput = try build(projectURL: projectURL, scheme: request.scheme)
            } else {
                buildOutput = ""
            }
            return DeadCodeDeclarationRemovalOutcome(
                editedFileURL: fileURL,
                buildOutput: buildOutput
            )
        } catch {
            progress(.restoringSources)
            do {
                try request.originalSource.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                throw DeadCodeRemovalError.rollbackFailed(
                    files: [fileURL],
                    underlyingDescription: error.localizedDescription
                )
            }

            if let removalError = error as? DeadCodeRemovalError {
                throw removalError
            }
            throw DeadCodeRemovalError.buildFailed(error.localizedDescription)
        }
    }

    private static func applyClusterSynchronously(
        _ request: DeadCodeClusterRemovalRequest,
        progress: DeadCodeRemovalProgressHandler
    ) throws -> DeadCodeClusterRemovalOutcome {
        let fileManager = FileManager.default
        let projectURL = resolvedBuildContainer(
            from: URL(fileURLWithPath: request.projectPath).standardizedFileURL
        )
        let projectRoot = projectURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let removedFileURLs = Array(Set(request.removedFileURLs.map(\.standardizedFileURL)))
        let sourceEdits = Dictionary(
            request.sourceEdits.map { ($0.fileURL.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values.sorted { $0.fileURL.path < $1.fileURL.path }
        let editedPaths = Set(sourceEdits.map { $0.fileURL.standardizedFileURL.path })

        guard Set(removedFileURLs.map(\.path)).isDisjoint(with: editedPaths) else {
            throw DeadCodeRemovalError.conflictingEdits
        }

        let allFileURLs = removedFileURLs + sourceEdits.map(\.fileURL)
        guard !allFileURLs.isEmpty else {
            throw DeadCodeRemovalError.noFiles
        }

        for fileURL in allFileURLs {
            guard fileURL.pathExtension.lowercased() == "swift",
                  fileURL.resolvingSymlinksInPath().isDescendant(of: projectRoot) else {
                throw DeadCodeRemovalError.outsideProject(fileURL)
            }
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw DeadCodeRemovalError.fileMissing(fileURL)
            }
        }

        for edit in sourceEdits {
            let currentSource: String
            do {
                currentSource = try String(contentsOf: edit.fileURL, encoding: .utf8)
            } catch {
                throw DeadCodeRemovalError.unreadableSource(edit.fileURL)
            }
            guard currentSource == edit.originalSource else {
                throw DeadCodeRemovalError.staleSource(edit.fileURL)
            }
        }

        let metadataEdits = try DeadCodeProjectReferenceEditor.makeEdits(
            removing: removedFileURLs,
            projectRoot: projectRoot
        )
        try validateMetadataEdits(metadataEdits)
        let affectedURLs = allFileURLs + metadataEdits.map(\.fileURL)
        let backupDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FRTMTools-DeadCluster-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backups = try affectedURLs.enumerated().map { index, fileURL in
            let backupURL = backupDirectory.appendingPathComponent("\(index)-\(fileURL.lastPathComponent)")
            try fileManager.copyItem(at: fileURL, to: backupURL)
            return (original: fileURL, backup: backupURL)
        }

        do {
            progress(.applyingChanges)
            try applyMetadataEdits(metadataEdits)
            for edit in sourceEdits {
                try edit.updatedSource.write(to: edit.fileURL, atomically: true, encoding: .utf8)
            }
            for fileURL in removedFileURLs {
                try fileManager.trashItem(at: fileURL, resultingItemURL: nil)
            }

            let buildOutput: String
            if request.validatesBuild {
                progress(.rebuilding)
                buildOutput = try build(projectURL: projectURL, scheme: request.scheme)
            } else {
                buildOutput = ""
            }
            try? fileManager.removeItem(at: backupDirectory)
            return DeadCodeClusterRemovalOutcome(
                affectedFileURLs: allFileURLs,
                buildOutput: buildOutput
            )
        } catch {
            progress(.restoringSources)
            var rollbackFailures: [URL] = []
            for backup in backups {
                do {
                    if fileManager.fileExists(atPath: backup.original.path) {
                        try fileManager.removeItem(at: backup.original)
                    }
                    try fileManager.copyItem(at: backup.backup, to: backup.original)
                } catch {
                    rollbackFailures.append(backup.original)
                }
            }
            try? fileManager.removeItem(at: backupDirectory)

            guard rollbackFailures.isEmpty else {
                throw DeadCodeRemovalError.rollbackFailed(
                    files: rollbackFailures,
                    underlyingDescription: error.localizedDescription
                )
            }
            if let removalError = error as? DeadCodeRemovalError {
                throw removalError
            }
            throw DeadCodeRemovalError.buildFailed(error.localizedDescription)
        }
    }

    private static func validateMetadataEdits(
        _ edits: [DeadCodeProjectMetadataEdit]
    ) throws {
        for edit in edits {
            let currentContents: String
            do {
                currentContents = try String(
                    contentsOf: edit.fileURL,
                    encoding: .utf8
                )
            } catch {
                throw DeadCodeRemovalError.projectReferenceUpdateFailed(
                    "\(edit.fileURL.path) could not be read."
                )
            }
            guard currentContents == edit.originalContents else {
                throw DeadCodeRemovalError.projectReferenceUpdateFailed(
                    "\(edit.fileURL.lastPathComponent) changed while preparing the removal."
                )
            }
        }
    }

    private static func applyMetadataEdits(
        _ edits: [DeadCodeProjectMetadataEdit]
    ) throws {
        for edit in edits {
            do {
                try edit.updatedContents.write(
                    to: edit.fileURL,
                    atomically: true,
                    encoding: .utf8
                )
            } catch {
                throw DeadCodeRemovalError.projectReferenceUpdateFailed(
                    "\(edit.fileURL.path) could not be updated: \(error.localizedDescription)"
                )
            }
        }
    }

    private static func build(projectURL: URL, scheme: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.currentDirectoryURL = projectURL.deletingLastPathComponent()
        let containerFlag: String

        switch projectURL.pathExtension.lowercased() {
        case "xcworkspace":
            containerFlag = "-workspace"
        case "xcodeproj":
            containerFlag = "-project"
        default:
            throw DeadCodeRemovalError.unsupportedProject(projectURL)
        }

        process.arguments = [
            "xcodebuild",
            containerFlag,
            projectURL.path,
            "-scheme",
            scheme,
            "-parallelizeTargets",
            "CODE_SIGNING_ALLOWED=NO",
            "ENABLE_BITCODE=NO",
            "DEBUG_INFORMATION_FORMAT=dwarf",
            "build",
        ]
        var environment = ProcessInfo.processInfo.environment
        [
            "BUILT_PRODUCTS_DIR",
            "CONFIGURATION",
            "PODS_ROOT",
            "PROJECT_DIR",
            "SRCROOT",
            "TARGET_BUILD_DIR",
        ].forEach { environment.removeValue(forKey: $0) }
        process.environment = environment

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FRTMTools-DeadCode-Build-\(UUID().uuidString)")
            .appendingPathExtension("log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle: FileHandle
        do {
            logHandle = try FileHandle(forWritingTo: logURL)
        } catch {
            throw DeadCodeRemovalError.buildFailed(
                "The build log could not be created: \(error.localizedDescription)"
            )
        }
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
        } catch {
            try? logHandle.close()
            try? FileManager.default.removeItem(at: logURL)
            throw DeadCodeRemovalError.buildFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        try? logHandle.close()

        guard process.terminationStatus == 0 else {
            let summary = buildFailureSummary(fromLogAt: logURL)
            throw DeadCodeRemovalError.buildFailed(
                "Container: \(projectURL.path)\nScheme: \(scheme)\nAction: build\n\n" +
                    "\(summary)\n\nFull build log: \(logURL.path)"
            )
        }

        try? FileManager.default.removeItem(at: logURL)
        return ""
    }

    private static func buildFailureSummary(fromLogAt logURL: URL) -> String {
        guard let stream = InputStream(url: logURL) else {
            return "The build failed, but its log could not be opened."
        }
        stream.open()
        defer { stream.close() }

        var diagnostics: [String] = []
        var tail: [String] = []
        var previousLine: String?
        var followingDiagnosticLines = 0
        var carry = Data()
        var bytes = [UInt8](repeating: 0, count: 64 * 1_024)

        func consume(_ line: String) {
            tail.append(line)
            if tail.count > 24 {
                tail.removeFirst(tail.count - 24)
            }

            if isBuildDiagnostic(line) {
                if let previousLine, diagnostics.last != previousLine {
                    diagnostics.append(previousLine)
                }
                diagnostics.append(line)
                followingDiagnosticLines = 2
            } else if followingDiagnosticLines > 0 {
                diagnostics.append(line)
                followingDiagnosticLines -= 1
            }
            if diagnostics.count > 120 {
                diagnostics.removeFirst(diagnostics.count - 120)
            }
            previousLine = line
        }

        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            carry.append(bytes, count: count)
            let parts = carry.split(separator: 0x0A, omittingEmptySubsequences: false)
            guard parts.count > 1 else { continue }
            for part in parts.dropLast() {
                consume(String(decoding: part, as: UTF8.self))
            }
            carry = Data(parts.last ?? Data.SubSequence())
        }
        if !carry.isEmpty {
            consume(String(decoding: carry, as: UTF8.self))
        }

        let diagnosticText = diagnostics.isEmpty
            ? tail.joined(separator: "\n")
            : diagnostics.joined(separator: "\n")
        return diagnosticText.count > 12_000
            ? String(diagnosticText.suffix(12_000))
            : diagnosticText
    }

    private static func isBuildDiagnostic(_ line: String) -> Bool {
        let normalized = line.lowercased()
        return normalized.hasPrefix("error:") ||
            normalized.contains(": error:") ||
            normalized.hasPrefix("fatal error:") ||
            normalized.contains(": fatal error:") ||
            normalized.contains("failed with a nonzero exit code") ||
            normalized.contains("the following build commands failed:") ||
            normalized.contains("no such module") ||
            normalized.contains("undefined symbol") ||
            normalized.contains("could not build") ||
            normalized.contains("unable to load contents") ||
            normalized.contains("no such file or directory")
    }

    private static func resolvedBuildContainer(from selectedURL: URL) -> URL {
        guard selectedURL.pathExtension.lowercased() == "xcodeproj" else {
            return selectedURL
        }

        let directoryURL = selectedURL.deletingLastPathComponent()
        let preferredWorkspaceURL = directoryURL
            .appendingPathComponent(selectedURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("xcworkspace")
        if FileManager.default.fileExists(atPath: preferredWorkspaceURL.path) {
            return preferredWorkspaceURL.standardizedFileURL
        }

        let workspaceURLs = (
            try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        )?.filter { $0.pathExtension.lowercased() == "xcworkspace" } ?? []

        return workspaceURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }.first?.standardizedFileURL
            ?? selectedURL
    }
}

enum DeadCodeRemovalError: LocalizedError {
    case noFiles
    case fileMissing(URL)
    case unreadableSource(URL)
    case staleSource(URL)
    case conflictingEdits
    case outsideProject(URL)
    case unsupportedProject(URL)
    case projectReferenceUpdateFailed(String)
    case buildFailed(String)
    case rollbackFailed(files: [URL], underlyingDescription: String)

    var errorDescription: String? {
        switch self {
        case .noFiles:
            return "No source files were selected for removal."
        case .fileMissing(let fileURL):
            return "\(fileURL.lastPathComponent) no longer exists."
        case .unreadableSource(let fileURL):
            return "\(fileURL.lastPathComponent) could not be read as UTF-8 Swift source."
        case .staleSource(let fileURL):
            return "\(fileURL.lastPathComponent) changed after the preview. No source was edited; refresh the scan and try again."
        case .conflictingEdits:
            return "The cluster plan contains conflicting edits for the same source file. No source was changed."
        case .outsideProject(let fileURL):
            return "\(fileURL.lastPathComponent) is outside the selected project and was not removed."
        case .unsupportedProject(let projectURL):
            return "\(projectURL.lastPathComponent) is not an Xcode project or workspace."
        case .projectReferenceUpdateFailed(let reason):
            return "Xcode project references could not be updated safely. No source was removed. \(reason)"
        case .buildFailed(let output):
            return "The project did not build after removal. Sources and Xcode project references were restored.\n\n\(output)"
        case .rollbackFailed(let files, let underlyingDescription):
            let names = files.map(\.lastPathComponent).joined(separator: ", ")
            return "Automatic rollback failed for \(names). Recover source files from Trash and project metadata from version control. Original error: \(underlyingDescription)"
        }
    }
}

private extension URL {
    func isDescendant(of directoryURL: URL) -> Bool {
        let directoryPath = directoryURL.standardizedFileURL.path
        let candidatePath = standardizedFileURL.path
        return candidatePath == directoryPath ||
            candidatePath.hasPrefix(directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/")
    }
}
