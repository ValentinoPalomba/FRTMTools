
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
        self.logger = Logger(verbose: true)
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
        configuration.buildArguments
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

    func scan(projectPath: String, scheme: String) throws -> [ScanResult] {
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
        
        return scan.buildResults()
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

    func buildResults() -> [ScanResult] {
        let resultInterval = logger.beginInterval("result:build")
        let results = ScanResultBuilder.build(for: graph)
        logger.endInterval(resultInterval)
        return results
    }
}
