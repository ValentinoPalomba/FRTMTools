import Foundation

enum DashboardPlatform: String, Codable, Sendable {
    case ipa
    case apk
}

enum DashboardRunStatus: String, Codable, Sendable {
    case queued
    case running
    case complete
    case failed
}

struct DashboardRun: Identifiable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let platform: DashboardPlatform
    let originalFileName: String

    var status: DashboardRunStatus
    var errorMessage: String?

    let uploadedFileRelativePath: String
    var analysisRelativePath: String?

    var displayTitle: String {
        let platformLabel = platform == .ipa ? "iOS" : "Android"
        return "\(platformLabel) • \(originalFileName)"
    }
}

