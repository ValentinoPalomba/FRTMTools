import Foundation

struct BadWordScanRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let fileName: String
    let fileURL: URL
    let scannedAt: Date
    let result: BadWordScanResult
    let duration: TimeInterval?

    init(
        id: UUID = UUID(),
        fileName: String,
        fileURL: URL,
        scannedAt: Date = Date(),
        result: BadWordScanResult,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.scannedAt = scannedAt
        self.result = result
        self.duration = duration
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, fileURL, scannedAt, result, duration
    }
}
