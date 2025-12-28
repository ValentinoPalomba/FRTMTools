import Foundation

final class BuildModelBuilder {
    func buildGraph(from steps: [XCLogParserStep]) -> BuildGraph {
        var allStepNodes: [BuildStepNode] = []
        var targetDrafts: [TargetDraft] = []

        for step in steps {
            let nodes = buildStepNodes(from: step, parentID: nil, targetDrafts: &targetDrafts)
            allStepNodes.append(contentsOf: nodes)
        }

        let dependencyMap = inferDependencies(for: targetDrafts)
        var dependentsMap: [String: [String]] = [:]
        for (target, dependencies) in dependencyMap {
            for dependency in dependencies {
                dependentsMap[dependency, default: []].append(target)
            }
        }

        let targets: [TargetNode] = targetDrafts.map { draft in
            let dependencies = dependencyMap[draft.name] ?? []
            let dependents = dependentsMap[draft.name] ?? []
            return TargetNode(
                name: draft.name,
                startTimestamp: draft.startTimestamp,
                endTimestamp: draft.endTimestamp,
                totalDuration: draft.totalDuration,
                dependencies: dependencies,
                dependents: dependents,
                steps: draft.steps
            )
        }

        let wallClockDuration = calculateWallClockDuration(from: allStepNodes)
        let machineInfo = BuildMachineInfo(
            machineName: firstMachineName(in: steps),
            buildIdentifier: firstBuildIdentifier(in: steps)
        )

        return BuildGraph(
            targets: targets,
            allSteps: allStepNodes,
            wallClockDuration: wallClockDuration,
            machineInfo: machineInfo
        )
    }

    private struct TargetDraft {
        let name: String
        let startTimestamp: Double?
        let endTimestamp: Double?
        let totalDuration: Double
        let steps: [BuildStepNode]
    }

    private func buildStepNodes(
        from step: XCLogParserStep,
        parentID: String?,
        targetDrafts: inout [TargetDraft]
    ) -> [BuildStepNode] {
        let id = step.identifier ?? UUID().uuidString
        let timestamps = normalizedTimestamps(for: step)
        let duration = effectiveDuration(for: step, start: timestamps.start, end: timestamps.end)

        let node = BuildStepNode(
            id: id,
            parentID: parentID,
            type: step.type,
            detailType: step.detailStepType,
            title: step.title,
            signature: step.signature,
            startTimestamp: timestamps.start,
            endTimestamp: timestamps.end,
            effectiveDuration: duration,
            fetchedFromCache: step.fetchedFromCache ?? false,
            swiftFunctionTimes: step.swiftFunctionTimes ?? [],
            swiftTypeCheckTimes: step.swiftTypeCheckTimes ?? [],
            notes: extractNotes(from: step.notes),
            warningCount: step.warningCount ?? 0,
            errorCount: step.errorCount ?? 0
        )

        var nodes = [node]

        if step.type == .target {
            let targetName = inferTargetName(from: step.title)
            let detailSteps = step.subSteps.flatMap { buildStepNodes(from: $0, parentID: id, targetDrafts: &targetDrafts) }
            let targetDraft = TargetDraft(
                name: targetName,
                startTimestamp: timestamps.start,
                endTimestamp: timestamps.end,
                totalDuration: duration,
                steps: detailSteps
            )
            targetDrafts.append(targetDraft)
            nodes.append(contentsOf: detailSteps)
        } else {
            for subStep in step.subSteps {
                nodes.append(contentsOf: buildStepNodes(from: subStep, parentID: id, targetDrafts: &targetDrafts))
            }
        }

        return nodes
    }

    private func inferTargetName(from title: String?) -> String {
        guard let title, !title.isEmpty else {
            return "Unnamed Target"
        }
        let prefix = "Build target "
        if title.hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count))
        }
        return title
    }

    private func normalizedTimestamps(for step: XCLogParserStep) -> (start: Double?, end: Double?) {
        var start = step.startTimestamp
        var end = step.endTimestamp

        if (start == nil || end == nil), let compilationEnd = step.compilationEndTimestamp, let compilationDuration = step.compilationDuration {
            if end == nil {
                end = compilationEnd
            }
            if start == nil {
                start = compilationEnd - compilationDuration
            }
        }

        if let start, let end, end < start {
            return (start, start)
        }

        return (start, end)
    }

    private func effectiveDuration(for step: XCLogParserStep, start: Double?, end: Double?) -> Double {
        if let duration = step.duration {
            return max(0, duration)
        }
        if let start, let end {
            return max(0, end - start)
        }
        if let compilationDuration = step.compilationDuration {
            return max(0, compilationDuration)
        }
        return 0
    }

    private func extractNotes(from value: JSONValue?) -> [String] {
        guard let value else { return [] }
        return flattenJSONStrings(value)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func flattenJSONStrings(_ value: JSONValue) -> [String] {
        switch value {
        case .null:
            return []
        case .bool(let bool):
            return [bool ? "true" : "false"]
        case .number(let number):
            return [String(number)]
        case .string(let string):
            return [string]
        case .array(let values):
            return values.flatMap { flattenJSONStrings($0) }
        case .object(let dict):
            return dict.values.flatMap { flattenJSONStrings($0) }
        }
    }

    private func calculateWallClockDuration(from steps: [BuildStepNode]) -> Double {
        let start = steps.compactMap { $0.startTimestamp }.min()
        let end = steps.compactMap { $0.endTimestamp }.max()
        if let start, let end {
            return max(0, end - start)
        }
        return 0
    }

    private func inferDependencies(for drafts: [TargetDraft]) -> [String: [String]] {
        let sorted = drafts.sorted { ($0.startTimestamp ?? 0) < ($1.startTimestamp ?? 0) }
        var dependencyMap: [String: [String]] = [:]
        let epsilon = 0.01

        for (index, target) in sorted.enumerated() {
            guard let targetStart = target.startTimestamp else {
                dependencyMap[target.name] = []
                continue
            }

            let candidates = sorted.prefix(index).compactMap { candidate -> (name: String, end: Double)? in
                guard let end = candidate.endTimestamp, end <= targetStart else { return nil }
                return (candidate.name, end)
            }

            guard let maxEnd = candidates.map({ $0.end }).max() else {
                dependencyMap[target.name] = []
                continue
            }

            let dependencies = candidates
                .filter { abs($0.end - maxEnd) <= epsilon }
                .map { $0.name }

            dependencyMap[target.name] = Array(Set(dependencies))
        }

        return dependencyMap
    }

    private func firstMachineName(in steps: [XCLogParserStep]) -> String? {
        for step in steps {
            if let machineName = step.machineName {
                return machineName
            }
            if let nested = firstMachineName(in: step.subSteps) {
                return nested
            }
        }
        return nil
    }

    private func firstBuildIdentifier(in steps: [XCLogParserStep]) -> String? {
        for step in steps {
            if let identifier = step.buildIdentifier {
                return identifier
            }
            if let nested = firstBuildIdentifier(in: step.subSteps) {
                return nested
            }
        }
        return nil
    }
}
