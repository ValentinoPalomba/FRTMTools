import Foundation

struct BuildStepNode: Identifiable {
    let id: String
    let parentID: String?
    let type: XCLogParserStepType
    let detailType: XCLogParserDetailStepType?
    let title: String?
    let signature: String?
    let startTimestamp: Double?
    let endTimestamp: Double?
    let effectiveDuration: Double
    let fetchedFromCache: Bool
    let swiftFunctionTimes: [XCLogParserSwiftFunctionTime]
    let swiftTypeCheckTimes: [XCLogParserSwiftTypeCheckTime]
    let notes: [String]
    let warningCount: Int
    let errorCount: Int
}

struct TargetNode {
    let name: String
    let startTimestamp: Double?
    let endTimestamp: Double?
    let totalDuration: Double
    let dependencies: [String]
    let dependents: [String]
    let steps: [BuildStepNode]
}

struct BuildMachineInfo {
    let machineName: String?
    let buildIdentifier: String?
}

struct BuildGraph {
    let targets: [TargetNode]
    let allSteps: [BuildStepNode]
    let wallClockDuration: Double
    let machineInfo: BuildMachineInfo
}
