import SwiftUI

struct CertificateInfoPopover: View {
    let signatureInfo: APKSignatureInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: signatureInfo.isDebugSigned ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                        .font(.title)
                        .foregroundColor(signatureInfo.isDebugSigned ? .orange : .green)
                    VStack(alignment: .leading) {
                        Text(signatureInfo.isDebugSigned ? "Debug Certificate" : "Release Certificate")
                            .font(.headline)
                        Text("Signature: \(signatureInfo.signatureSchemesDescription)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)

                if let cert = signatureInfo.primaryCertificate {
                    Divider()

                    // Certificate validity
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Certificate Status", systemImage: "calendar")
                            .font(.headline)

                        HStack {
                            Circle()
                                .fill(cert.isValid ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(cert.isValid ? "Valid" : "Expired/Invalid")
                                .font(.subheadline)
                        }

                        if cert.isExpiringSoon {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Expiring soon")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        Text("Valid from: \(cert.validFrom, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Valid until: \(cert.validUntil, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Subject info
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Subject", systemImage: "person.fill")
                            .font(.headline)

                        if let cn = cert.commonName {
                            InfoRow(label: "Common Name", value: cn)
                        }
                        if let org = cert.organizationName {
                            InfoRow(label: "Organization", value: org)
                        }
                        InfoRow(label: "Full", value: cert.subject)
                            .font(.caption2)
                    }

                    Divider()

                    // Issuer info
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Issuer", systemImage: "building.2.fill")
                            .font(.headline)
                        InfoRow(label: "", value: cert.issuer)
                            .font(.caption)
                    }

                    Divider()

                    // Technical details
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Technical Details", systemImage: "gear")
                            .font(.headline)

                        InfoRow(label: "Serial", value: cert.serialNumber)
                        InfoRow(label: "Version", value: "v\(cert.version)")
                        InfoRow(label: "Public Key", value: cert.publicKeyAlgorithm)
                        InfoRow(label: "Signature", value: cert.signatureAlgorithm)
                    }

                    Divider()

                    // Fingerprints
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Fingerprints", systemImage: "hand.point.up.braille.fill")
                            .font(.headline)

                        FingerprintRow(label: "MD5", value: cert.md5Fingerprint)
                        FingerprintRow(label: "SHA-1", value: cert.sha1Fingerprint)
                        FingerprintRow(label: "SHA-256", value: cert.sha256Fingerprint)
                    }
                }
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        if !label.isEmpty {
            HStack(alignment: .top) {
                Text("\(label):")
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                Text(value)
                    .textSelection(.enabled)
                Spacer()
            }
            .font(.caption)
        } else {
            Text(value)
                .textSelection(.enabled)
                .font(.caption)
        }
    }
}

struct FingerprintRow: View {
    let label: String
    let value: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(label):")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .padding(.leading, 8)
        }
    }
}
