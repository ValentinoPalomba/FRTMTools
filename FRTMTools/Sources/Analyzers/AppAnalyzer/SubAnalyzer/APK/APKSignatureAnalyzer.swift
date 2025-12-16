import Foundation
import CryptoKit

final class APKSignatureAnalyzer: @unchecked Sendable {
    private let fm = FileManager.default

    func analyzeSignature(in layout: AndroidPackageLayout) -> APKSignatureInfo? {
        // Find certificate files in META-INF
        let metaInfURL = layout.rootURL.appendingPathComponent("META-INF", isDirectory: true)
        guard fm.fileExists(atPath: metaInfURL.path) else {
            return nil
        }

        // Look for .RSA, .DSA, or .EC files
        guard let certFileURL = findCertificateFile(in: metaInfURL) else {
            return nil
        }

        // Extract certificate information
        guard let certInfo = extractCertificateInfo(from: certFileURL) else {
            return nil
        }

        // Detect signature schemes
        let schemes = detectSignatureSchemes(in: layout)

        // Check if it's debug signed
        let isDebug = isDebugCertificate(certInfo)

        return APKSignatureInfo(
            certificates: [certInfo],
            signatureSchemes: schemes,
            isDebugSigned: isDebug
        )
    }

    private func findCertificateFile(in metaInfURL: URL) -> URL? {
        guard let files = try? fm.contentsOfDirectory(at: metaInfURL, includingPropertiesForKeys: nil) else {
            return nil
        }

        let certExtensions = ["RSA", "DSA", "EC", "rsa", "dsa", "ec"]
        for file in files {
            if certExtensions.contains(file.pathExtension) {
                return file
            }
        }

        return nil
    }

    private func extractCertificateInfo(from certFileURL: URL) -> CertificateInfo? {
        // Use openssl to extract certificate information
        // First, convert from PKCS7 to PEM format
        let tempPEMURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cert-\(UUID().uuidString).pem")

        defer {
            try? fm.removeItem(at: tempPEMURL)
        }

        // Extract certificate using openssl pkcs7
        let extractProcess = Process()
        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        extractProcess.arguments = ["pkcs7", "-inform", "DER", "-in", certFileURL.path, "-print_certs", "-out", tempPEMURL.path]

        let extractPipe = Pipe()
        extractProcess.standardError = extractPipe

        do {
            try extractProcess.run()
            extractProcess.waitUntilExit()

            guard extractProcess.terminationStatus == 0,
                  fm.fileExists(atPath: tempPEMURL.path) else {
                return nil
            }

            return parseCertificateFromPEM(at: tempPEMURL)
        } catch {
            print("⚠️ Failed to extract certificate: \(error)")
            return nil
        }
    }

    private func parseCertificateFromPEM(at pemURL: URL) -> CertificateInfo? {
        // Use openssl x509 to get certificate details
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "x509",
            "-in", pemURL.path,
            "-noout",
            "-subject",
            "-issuer",
            "-serial",
            "-dates",
            "-fingerprint",
            "-sha1", "-fingerprint",
            "-sha256", "-fingerprint"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }

            return parseCertificateOutput(output, pemURL: pemURL)
        } catch {
            print("⚠️ Failed to parse certificate: \(error)")
            return nil
        }
    }

    private func parseCertificateOutput(_ output: String, pemURL: URL) -> CertificateInfo? {
        var subject = ""
        var issuer = ""
        var serialNumber = ""
        var validFrom = Date()
        var validUntil = Date()
        var md5Fingerprint = ""
        var sha1Fingerprint = ""
        var sha256Fingerprint = ""

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("subject=") {
                subject = String(trimmed.dropFirst("subject=".count))
            } else if trimmed.hasPrefix("issuer=") {
                issuer = String(trimmed.dropFirst("issuer=".count))
            } else if trimmed.hasPrefix("serial=") {
                serialNumber = String(trimmed.dropFirst("serial=".count))
            } else if trimmed.hasPrefix("notBefore=") {
                let dateStr = String(trimmed.dropFirst("notBefore=".count))
                validFrom = parseOpenSSLDate(dateStr) ?? Date()
            } else if trimmed.hasPrefix("notAfter=") {
                let dateStr = String(trimmed.dropFirst("notAfter=".count))
                validUntil = parseOpenSSLDate(dateStr) ?? Date()
            } else if trimmed.hasPrefix("MD5 Fingerprint=") {
                md5Fingerprint = String(trimmed.dropFirst("MD5 Fingerprint=".count))
            } else if trimmed.hasPrefix("SHA1 Fingerprint=") {
                sha1Fingerprint = String(trimmed.dropFirst("SHA1 Fingerprint=".count))
            } else if trimmed.hasPrefix("SHA256 Fingerprint=") {
                sha256Fingerprint = String(trimmed.dropFirst("SHA256 Fingerprint=".count))
            }
        }

        // Get MD5 fingerprint separately if not found
        if md5Fingerprint.isEmpty {
            md5Fingerprint = calculateFingerprint(pemURL: pemURL, algorithm: "md5")
        }
        if sha1Fingerprint.isEmpty {
            sha1Fingerprint = calculateFingerprint(pemURL: pemURL, algorithm: "sha1")
        }
        if sha256Fingerprint.isEmpty {
            sha256Fingerprint = calculateFingerprint(pemURL: pemURL, algorithm: "sha256")
        }

        // Get algorithm information
        let (publicKeyAlgo, signatureAlgo, version) = getCertificateAlgorithms(pemURL: pemURL)

        return CertificateInfo(
            subject: subject,
            issuer: issuer,
            serialNumber: serialNumber,
            validFrom: validFrom,
            validUntil: validUntil,
            md5Fingerprint: md5Fingerprint,
            sha1Fingerprint: sha1Fingerprint,
            sha256Fingerprint: sha256Fingerprint,
            publicKeyAlgorithm: publicKeyAlgo,
            signatureAlgorithm: signatureAlgo,
            version: version
        )
    }

    private func calculateFingerprint(pemURL: URL, algorithm: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["x509", "-in", pemURL.path, "-noout", "-fingerprint", "-\(algorithm)"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return ""
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return ""
            }

            // Parse "SHA256 Fingerprint=XX:XX:XX..."
            let components = output.components(separatedBy: "=")
            if components.count > 1 {
                return components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return ""
        }

        return ""
    }

    private func getCertificateAlgorithms(pemURL: URL) -> (publicKey: String, signature: String, version: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["x509", "-in", pemURL.path, "-noout", "-text"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return ("Unknown", "Unknown", 3)
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return ("Unknown", "Unknown", 3)
            }

            var publicKeyAlgo = "Unknown"
            var signatureAlgo = "Unknown"
            var version = 3

            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("Version:") {
                    if let versionNum = trimmed.components(separatedBy: " ").last,
                       let versionInt = Int(versionNum) {
                        version = versionInt
                    }
                } else if trimmed.hasPrefix("Public Key Algorithm:") {
                    publicKeyAlgo = trimmed.replacingOccurrences(of: "Public Key Algorithm: ", with: "")
                } else if trimmed.hasPrefix("Signature Algorithm:") {
                    signatureAlgo = trimmed.replacingOccurrences(of: "Signature Algorithm: ", with: "")
                }
            }

            return (publicKeyAlgo, signatureAlgo, version)
        } catch {
            return ("Unknown", "Unknown", 3)
        }
    }

    private func parseOpenSSLDate(_ dateString: String) -> Date? {
        // OpenSSL date format: "Jan 1 00:00:00 2024 GMT"
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    private func detectSignatureSchemes(in layout: AndroidPackageLayout) -> [SignatureScheme] {
        var schemes: [SignatureScheme] = []

        // Check for v1 signature (META-INF directory)
        let metaInfURL = layout.rootURL.appendingPathComponent("META-INF", isDirectory: true)
        if fm.fileExists(atPath: metaInfURL.path) {
            schemes.append(.v1)
        }

        // v2, v3, v4 signatures are in the APK Signing Block which is in the original APK file
        // We can't easily detect these from the extracted contents
        // For now, we'll just indicate v1 if META-INF exists
        // A more complete implementation would need to parse the original APK file's signing block

        return schemes.isEmpty ? [.unknown] : schemes
    }

    private func isDebugCertificate(_ certInfo: CertificateInfo) -> Bool {
        // Android debug certificates typically have:
        // - CN=Android Debug
        // - O=Android
        let subject = certInfo.subject.lowercased()
        return subject.contains("cn=android debug") || subject.contains("o=android")
    }
}
