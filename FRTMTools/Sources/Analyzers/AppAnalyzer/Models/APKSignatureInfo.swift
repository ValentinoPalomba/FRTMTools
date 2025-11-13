import Foundation

struct APKSignatureInfo: Codable, Sendable {
    let certificates: [CertificateInfo]
    let signatureSchemes: [SignatureScheme]
    let isDebugSigned: Bool

    var primaryCertificate: CertificateInfo? {
        certificates.first
    }

    var signatureSchemesDescription: String {
        signatureSchemes.map { $0.rawValue }.joined(separator: ", ")
    }
}

struct CertificateInfo: Codable, Sendable {
    let subject: String
    let issuer: String
    let serialNumber: String
    let validFrom: Date
    let validUntil: Date
    let md5Fingerprint: String
    let sha1Fingerprint: String
    let sha256Fingerprint: String
    let publicKeyAlgorithm: String
    let signatureAlgorithm: String
    let version: Int

    var isValid: Bool {
        let now = Date()
        return now >= validFrom && now <= validUntil
    }

    var isExpiringSoon: Bool {
        guard isValid else { return false }
        let daysUntilExpiration = Calendar.current.dateComponents([.day], from: Date(), to: validUntil).day ?? 0
        return daysUntilExpiration < 90 // Warning if less than 90 days
    }

    var commonName: String? {
        // Extract CN from subject (e.g., "CN=Android Debug, O=Android, C=US")
        let components = subject.components(separatedBy: ", ")
        for component in components {
            if component.hasPrefix("CN=") {
                return String(component.dropFirst(3))
            }
        }
        return nil
    }

    var organizationName: String? {
        // Extract O from subject
        let components = subject.components(separatedBy: ", ")
        for component in components {
            if component.hasPrefix("O=") {
                return String(component.dropFirst(2))
            }
        }
        return nil
    }
}

enum SignatureScheme: String, Codable, Sendable {
    case v1 = "v1 (JAR)"
    case v2 = "v2"
    case v3 = "v3"
    case v4 = "v4"
    case unknown = "Unknown"
}
