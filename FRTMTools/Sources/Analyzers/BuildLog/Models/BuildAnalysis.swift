import Foundation

struct BuildAnalysis {
    struct CriticalPathResult: Hashable {
        let duration: Double
        let targets: [String]
    }

    struct SwiftTypeCheckHotspot: Hashable {
        let file: String
        let line: Int
        let durationSeconds: Double
        let occurrences: Int
    }

    struct CacheKiller: Hashable {
        let title: String
        let duration: Double
    }

    let graph: BuildGraph
    let totalStepDuration: Double
    let parallelism: Double
    let cacheHitRate: Double
    let nonCachedDuration: Double
    let criticalPath: CriticalPathResult
    let perTargetParallelism: [String: Double]
    let stepTypeTotals: [String: Double]
    let swiftTypeCheckHotspots: [SwiftTypeCheckHotspot]
    let cacheKillers: [CacheKiller]

    init(graph: BuildGraph) {
        self.graph = graph

        let stepDurations = graph.allSteps.map { max(0, $0.effectiveDuration) }
        let totalStepsDuration = stepDurations.reduce(0, +)
        totalStepDuration = totalStepsDuration

        if graph.wallClockDuration > 0 {
            parallelism = totalStepsDuration / graph.wallClockDuration
        } else {
            parallelism = 0
        }

        let cachedSteps = graph.allSteps.filter { $0.fetchedFromCache }
        if graph.allSteps.isEmpty {
            cacheHitRate = 0
        } else {
            cacheHitRate = Double(cachedSteps.count) / Double(graph.allSteps.count)
        }

        nonCachedDuration = graph.allSteps
            .filter { !$0.fetchedFromCache }
            .map { max(0, $0.effectiveDuration) }
            .reduce(0, +)

        var targetParallelism: [String: Double] = [:]
        for target in graph.targets {
            let totalTargetSteps = target.steps.map { max(0, $0.effectiveDuration) }.reduce(0, +)
            if target.totalDuration > 0 {
                targetParallelism[target.name] = totalTargetSteps / target.totalDuration
            } else {
                targetParallelism[target.name] = 0
            }
        }
        perTargetParallelism = targetParallelism

        var typeTotals: [String: Double] = [:]
        for step in graph.allSteps {
            let label = BuildAnalysis.stepTypeLabel(for: step)
            typeTotals[label, default: 0] += max(0, step.effectiveDuration)
        }
        stepTypeTotals = typeTotals

        swiftTypeCheckHotspots = BuildAnalysis.collectSwiftTypeCheckHotspots(from: graph.allSteps)
        cacheKillers = BuildAnalysis.collectCacheKillers(from: graph.allSteps)
        criticalPath = BuildAnalysis.computeCriticalPath(in: graph)
    }

    static func stepTypeLabel(for step: BuildStepNode) -> String {
        if let detail = step.detailType, detail != .none, detail != .other {
            return detail.rawValue
        }
        if let title = step.title, !title.isEmpty {
            return title
        }
        return step.type.rawValue
    }

    private static func collectSwiftTypeCheckHotspots(from steps: [BuildStepNode]) -> [SwiftTypeCheckHotspot] {
        var aggregated: [String: (file: String, line: Int, durationSeconds: Double, occurrences: Int)] = [:]

        for step in steps {
            for entry in step.swiftTypeCheckTimes {
                let durationSeconds = entry.durationMS / 1000.0
                let key = "\(entry.file):\(entry.startingLine)"
                if var existing = aggregated[key] {
                    existing.durationSeconds += durationSeconds
                    existing.occurrences += entry.occurrences
                    aggregated[key] = existing
                } else {
                    aggregated[key] = (
                        file: entry.file,
                        line: entry.startingLine,
                        durationSeconds: durationSeconds,
                        occurrences: entry.occurrences
                    )
                }
            }
        }

        return aggregated.values
            .map {
                SwiftTypeCheckHotspot(
                    file: $0.file,
                    line: $0.line,
                    durationSeconds: $0.durationSeconds,
                    occurrences: $0.occurrences
                )
            }
            .sorted { $0.durationSeconds > $1.durationSeconds }
    }

    private static func collectCacheKillers(from steps: [BuildStepNode]) -> [CacheKiller] {
        let candidates = steps
            .filter { !$0.fetchedFromCache && $0.effectiveDuration > 0.5 }
            .sorted { $0.effectiveDuration > $1.effectiveDuration }

        return candidates.prefix(5).map { step in
            CacheKiller(
                title: step.title ?? BuildAnalysis.stepTypeLabel(for: step),
                duration: step.effectiveDuration
            )
        }
    }

    private static func computeCriticalPath(in graph: BuildGraph) -> CriticalPathResult {
        let targetsByName = Dictionary(uniqueKeysWithValues: graph.targets.map { ($0.name, $0) })
        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]

        for target in graph.targets {
            inDegree[target.name] = target.dependencies.count
            for dep in target.dependencies {
                dependents[dep, default: []].append(target.name)
            }
        }

        var queue = inDegree.filter { $0.value == 0 }.map { $0.key }
        var ordered: [String] = []

        while let name = queue.first {
            queue.removeFirst()
            ordered.append(name)
            for dependent in dependents[name] ?? [] {
                inDegree[dependent, default: 0] -= 1
                if inDegree[dependent] == 0 {
                    queue.append(dependent)
                }
            }
        }

        if ordered.count != graph.targets.count {
            ordered = graph.targets.sorted { ($0.startTimestamp ?? 0) < ($1.startTimestamp ?? 0) }.map { $0.name }
        }

        var longest: [String: Double] = [:]
        var previous: [String: String] = [:]

        for name in ordered {
            guard let target = targetsByName[name] else { continue }
            var bestDuration: Double = 0
            var bestDep: String?
            for dep in target.dependencies {
                let candidate = longest[dep] ?? 0
                if candidate > bestDuration {
                    bestDuration = candidate
                    bestDep = dep
                }
            }
            longest[name] = bestDuration + max(0, target.totalDuration)
            if let bestDep { previous[name] = bestDep }
        }

        guard let (maxName, maxDuration) = longest.max(by: { $0.value < $1.value }) else {
            return CriticalPathResult(duration: 0, targets: [])
        }

        var path: [String] = []
        var current: String? = maxName
        while let name = current {
            path.append(name)
            current = previous[name]
        }

        return CriticalPathResult(duration: maxDuration, targets: path.reversed())
    }
}
