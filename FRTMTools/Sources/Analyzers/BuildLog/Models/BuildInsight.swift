import Foundation

struct BuildInsight: Identifiable, Hashable {
    enum Severity: String, Hashable {
        case info
        case warning
        case critical
    }

    let id: UUID
    let severity: Severity
    let title: String
    let explanation: String
    let suggestion: String
    let confidence: Double
    let relatedTargets: [String]
    let estimatedImpactSeconds: Double?

    init(
        id: UUID = UUID(),
        severity: Severity,
        title: String,
        explanation: String,
        suggestion: String,
        confidence: Double,
        relatedTargets: [String] = [],
        estimatedImpactSeconds: Double? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.suggestion = suggestion
        self.confidence = confidence
        self.relatedTargets = relatedTargets
        self.estimatedImpactSeconds = estimatedImpactSeconds
    }
}
