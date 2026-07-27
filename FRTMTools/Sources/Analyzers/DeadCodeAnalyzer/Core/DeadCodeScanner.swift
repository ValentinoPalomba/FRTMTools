
import Foundation
import PeripheryKit
import XcodeSupport
import Shared
import Configuration
import Indexer
import SourceGraph
import ProjectDrivers
import Logger

class DeadCodeScanner {
    private let configuration: Configuration
    private let logger: Logger
    private let shell: Shell

    init() {
        self.configuration = Configuration()
        self.logger = Logger(verbose: false)
        self.shell = Shell(logger: self.logger)
        configuration.excludeTests = true
        configuration.retainPublic = false
        configuration.indexExclude = ["**/Pods/**"]
        configuration.excludeTargets = ["Pods"]
        configuration.reportExclude = ["**/Pods/**"]
        configuration.apply(\.$excludeTests, true)
        configuration.apply(\.$excludeTargets, ["Pods"])
        configuration.apply(\.$indexExclude, ["**/Pods/**"])
        configuration.apply(\.$reportExclude, ["**/Pods/**"])
        configuration.buildFilenameMatchers()
    }
    
    func listSchemes(for projectPath: URL) throws -> [String] {
        if projectPath.pathExtension == "xcodeproj" {
            let project = try XcodeProject(
                path: .makeAbsolute(projectPath.path()),
                loadedProjectPaths: [.makeAbsolute(projectPath.path())],
                xcodebuild: .init(
                    shell: shell,
                    logger: logger
                ),
                shell: shell,
                logger: logger
            )
            let schemes = try project.schemes(additionalArguments: [])
            return Array(schemes)
        } else if projectPath.pathExtension == "xcworkspace" {
            let project = try XcodeWorkspace(
                path: .makeAbsolute(projectPath.path()),
                xcodebuild: .init(
                    shell: shell,
                    logger: logger
                ),
                configuration: configuration,
                logger: logger, shell: shell
            )
            
            let schemes = try project.schemes(additionalArguments: [])
            return Array(schemes).sorted()
        }
        
        throw NSError(domain: "NO SCHEMES", code: 001)
    }

    func scan(projectPath: String, scheme: String) throws -> [SerializableDeadCodeResult] {
        configuration.skipBuild = false
        configuration.schemes = [scheme]
        
        let driver = try XcodeProjectDriver(
            projectPath: .makeAbsolute(projectPath),
            configuration: configuration,
            shell: shell,
            logger: logger
        )
        
        let scan = Scan(
            configuration: configuration,
            logger: logger,
            swiftVersion: .init(shell: shell)
        )
        
        try scan.build(driver)
        try scan.index(driver)
        try scan.analyze()
        
        return scan.buildResults(projectPath: projectPath)
    }
}

final class Scan {
    private let configuration: Configuration
    private let logger: Logger
    private let graph: SourceGraph
    private let swiftVersion: SwiftVersion

    required init(configuration: Configuration, logger: Logger, swiftVersion: SwiftVersion) {
        self.configuration = configuration
        self.logger = logger
        self.swiftVersion = swiftVersion
        graph = SourceGraph(configuration: configuration, logger: logger)
    }

    // MARK: - Privat
    func build(_ driver: ProjectDriver) throws {
        let driverBuildInterval = logger.beginInterval("driver:build")
        try driver.build()
        logger.endInterval(driverBuildInterval)
    }

    func index(_ driver: ProjectDriver) throws {
        let indexInterval = logger.beginInterval("index")

        if configuration.outputFormat.supportsAuxiliaryOutput {
            let asterisk = Logger.colorize("*", .boldGreen)
            logger.info("\(asterisk) Indexing...")
        }

        let indexLogger = logger.contextualized(with: "index")
        let plan = try driver.plan(logger: indexLogger)
        let syncSourceGraph = SynchronizedSourceGraph(graph: graph)
        let pipeline = IndexPipeline(plan: plan, graph: syncSourceGraph, logger: indexLogger, configuration: configuration)
        try pipeline.perform()
        logger.endInterval(indexInterval)
    }

    func analyze() throws {
        let analyzeInterval = logger.beginInterval("analyze")

        if configuration.outputFormat.supportsAuxiliaryOutput {
            let asterisk = Logger.colorize("*", .boldGreen)
            logger.info("\(asterisk) Analyzing...")
        }

        try SourceGraphMutatorRunner(
            graph: graph,
            logger: logger,
            configuration: configuration,
            swiftVersion: swiftVersion
        ).perform()
        logger.endInterval(analyzeInterval)
    }

    func buildResults(projectPath: String) -> [SerializableDeadCodeResult] {
        let resultInterval = logger.beginInterval("result:build")
        let results = ScanResultBuilder.build(for: graph)
        let serializedResults = DeadCodeGraphSnapshotBuilder.build(
            results: results,
            graph: graph,
            projectPath: projectPath
        )
        logger.endInterval(resultInterval)
        return serializedResults
    }
}

private enum DeadCodeGraphSnapshotBuilder {
    static func build(
        results: [ScanResult],
        graph: SourceGraph,
        projectPath: String
    ) -> [SerializableDeadCodeResult] {
        var seenDeclarations = Set<ObjectIdentifier>()
        let uniqueResults = results.filter {
            seenDeclarations.insert(ObjectIdentifier($0.declaration)).inserted
        }
        let declarations = uniqueResults.map(\.declaration)
        var graphIDOccurrences: [String: Int] = [:]
        let resultGraphIDs = declarations.map { declaration in
            let baseGraphID = graphID(for: declaration)
            let occurrence = graphIDOccurrences[baseGraphID, default: 0]
            graphIDOccurrences[baseGraphID] = occurrence + 1
            return occurrence == 0 ? baseGraphID : "\(baseGraphID)#occurrence-\(occurrence + 1)"
        }
        let graphIDByDeclaration = Dictionary(
            uniqueKeysWithValues: zip(declarations, resultGraphIDs).map {
                (ObjectIdentifier($0.0), $0.1)
            }
        )
        let resultDeclarationIDs = Set(graphIDByDeclaration.keys)
        let dependencySnapshot = dependencySnapshot(
            declarations: declarations,
            graphIDByDeclaration: graphIDByDeclaration,
            graph: graph
        )
        let safeFilePaths = safeWholeFilePaths(
            results: uniqueResults,
            graph: graph,
            projectPath: projectPath
        )

        return uniqueResults.enumerated().map { index, result in
            let declaration = result.declaration
            let graphID = resultGraphIDs[index]
            let parentGraphID = nearestResultParent(
                of: declaration,
                resultDeclarationIDs: resultDeclarationIDs,
                graphIDByDeclaration: graphIDByDeclaration
            )

            return SerializableDeadCodeResult(
                id: UUID(),
                kind: declaration.kind.displayName,
                accessibility: declaration.accessibility.value.rawValue,
                name: declaration.name,
                location: declaration.location.description,
                filePath: declaration.location.file.path.string,
                icon: declaration.kind.icon,
                annotationDescription: annotationDescription(for: result),
                graphID: graphID,
                usrs: declaration.usrs.sorted(),
                parentGraphID: parentGraphID,
                linkedGraphIDs: dependencySnapshot.linkedGraphIDs[graphID, default: []].sorted(),
                externalReferenceLocations:
                    dependencySnapshot.externalReferenceLocations[graphID, default: []].sorted(),
                remediation: remediation(for: result.annotation),
                fileRemovalSafety: safeFilePaths.contains(declaration.location.file.path.string)
                    ? .safeWholeFile
                    : .reviewRequired
            )
        }
    }

    private static func graphID(for declaration: Declaration) -> String {
        let usrComponent = declaration.usrs.sorted().joined(separator: "|")
        let locationComponent = declaration.location.description
        return usrComponent.isEmpty
            ? locationComponent
            : "\(usrComponent)@\(locationComponent)"
    }

    private static func nearestResultParent(
        of declaration: Declaration,
        resultDeclarationIDs: Set<ObjectIdentifier>,
        graphIDByDeclaration: [ObjectIdentifier: String]
    ) -> String? {
        var parent = declaration.parent

        while let candidate = parent {
            let candidateID = ObjectIdentifier(candidate)
            if resultDeclarationIDs.contains(candidateID) {
                return graphIDByDeclaration[candidateID]
            }
            parent = candidate.parent
        }

        return nil
    }

    private struct DependencySnapshot {
        var linkedGraphIDs: [String: Set<String>] = [:]
        var externalReferenceLocations: [String: Set<String>] = [:]
    }

    private static func dependencySnapshot(
        declarations: [Declaration],
        graphIDByDeclaration: [ObjectIdentifier: String],
        graph: SourceGraph
    ) -> DependencySnapshot {
        var snapshot = DependencySnapshot()
        let extendedDeclarationByExtension = Dictionary(
            uniqueKeysWithValues: graph.extensions.flatMap { extendedDeclaration, extensions in
                extensions.map {
                    (ObjectIdentifier($0), extendedDeclaration)
                }
            }
        )

        func nearestResultGraphID(from declaration: Declaration?) -> String? {
            var current = declaration
            while let candidate = current {
                if let graphID = graphIDByDeclaration[ObjectIdentifier(candidate)] {
                    return graphID
                }
                current = candidate.parent
            }
            return nil
        }

        for target in declarations {
            guard let targetGraphID = graphIDByDeclaration[ObjectIdentifier(target)] else {
                continue
            }

            if target.kind.isExtensionKind {
                if let extendedDeclaration =
                    extendedDeclarationByExtension[ObjectIdentifier(target)] {
                    if let extendedGraphID = nearestResultGraphID(
                        from: extendedDeclaration
                    ) {
                        snapshot.linkedGraphIDs[targetGraphID, default: []]
                            .insert(extendedGraphID)
                        snapshot.linkedGraphIDs[extendedGraphID, default: []]
                            .insert(targetGraphID)
                    } else {
                        snapshot.externalReferenceLocations[targetGraphID, default: []]
                            .insert(extendedDeclaration.location.description)
                    }
                } else {
                    snapshot.externalReferenceLocations[targetGraphID, default: []]
                        .insert(target.location.description)
                }
            }

            let removedDeclarations = target.descendentDeclarations.union([target])
            let removedDeclarationIDs = Set(removedDeclarations.map(ObjectIdentifier.init))

            for removedDeclaration in removedDeclarations {
                for reference in graph.references(to: removedDeclaration) {
                    if let owner = reference.parent,
                       removedDeclarationIDs.contains(ObjectIdentifier(owner)) {
                        continue
                    }

                    if let ownerGraphID = nearestResultGraphID(from: reference.parent) {
                        guard ownerGraphID != targetGraphID else { continue }
                        snapshot.linkedGraphIDs[targetGraphID, default: []].insert(ownerGraphID)
                        snapshot.linkedGraphIDs[ownerGraphID, default: []].insert(targetGraphID)
                    } else {
                        snapshot.externalReferenceLocations[targetGraphID, default: []]
                            .insert(reference.location.description)
                    }
                }
            }
        }

        return snapshot
    }

    private static func safeWholeFilePaths(
        results: [ScanResult],
        graph: SourceGraph,
        projectPath: String
    ) -> Set<String> {
        let projectRoot = URL(fileURLWithPath: projectPath)
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let unusedDeclarationIDs = Set(
            results.compactMap { result in
                if case .unused = result.annotation {
                    return ObjectIdentifier(result.declaration)
                }
                return nil
            }
        )
        let resultFilesWithNonDeletionRemediation = Set(
            results.compactMap { result -> String? in
                if case .unused = result.annotation {
                    return nil
                }
                return result.declaration.location.file.path.string
            }
        )
        let foldedExtensionDeclarations = graph.extensions.values.reduce(into: Set<Declaration>()) {
            $0.formUnion($1)
        }
        let structuralDeclarations = graph.allDeclarations.union(foldedExtensionDeclarations)
        let rootDeclarationsByFile = Dictionary(
            grouping: structuralDeclarations.filter {
                $0.parent == nil &&
                    !$0.isImplicit &&
                    $0.kind != .module &&
                    !$0.kind.isAccessorKind &&
                    $0.location.file.path.string.hasSuffix(".swift")
            },
            by: { $0.location.file.path.string }
        )

        return Set(
            rootDeclarationsByFile.compactMap { filePath, declarations in
                let fileURL = URL(fileURLWithPath: filePath).resolvingSymlinksInPath()
                guard fileURL.isDescendant(of: projectRoot),
                      !declarations.isEmpty,
                      !resultFilesWithNonDeletionRemediation.contains(filePath),
                      declarations.allSatisfy({
                          unusedDeclarationIDs.contains(ObjectIdentifier($0))
                      }) else {
                    return nil
                }

                return filePath
            }
        )
    }

    private static func annotationDescription(for result: ScanResult) -> String {
        switch result.annotation {
        case .unused:
            "Unused"
        case .assignOnlyProperty:
            "Assigned but never used"
        case .redundantPublicAccessibility(let modules):
            modules.isEmpty
                ? "Redundant public accessibility"
                : "Redundant public accessibility outside \(modules.sorted().joined(separator: ", "))"
        case .redundantProtocol(let references, let inherited):
            if inherited.isEmpty {
                "Redundant protocol conformance (\(references.count) reference(s))"
            } else {
                "Redundant protocol conformance (\(references.count) reference(s), replace with \(inherited.sorted().joined(separator: ", ")))"
            }
        }
    }

    private static func remediation(
        for annotation: ScanResult.Annotation
    ) -> SerializableDeadCodeResult.Remediation {
        switch annotation {
        case .unused:
            .deleteDeclaration
        case .assignOnlyProperty:
            .removeAssignments
        case .redundantProtocol:
            .removeConformance
        case .redundantPublicAccessibility:
            .reduceAccessibility
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
