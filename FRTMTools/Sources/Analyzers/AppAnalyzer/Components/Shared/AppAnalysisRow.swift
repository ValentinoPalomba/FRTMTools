
import SwiftUI

/// Shared row for IPA/APK analyses.
struct AppAnalysisRow<Analysis: AppAnalysis>: View {
    let analysis: Analysis
    let role: SelectionRole?
    @Environment(\.theme) private var theme

    var body: some View {
        let apkAnalysis = analysis as? APKAnalysis
        let primaryName = {
            if let apkAnalysis {
                return apkAnalysis.packageName ?? apkAnalysis.fileName
            } else {
                return analysis.fileName
            }
        }()
        let secondaryName = apkAnalysis?.appLabel != nil ? analysis.fileName : nil

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let image = analysis.image {
                    HStack {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .cornerRadius(8)
                            .shadow(radius: 2)
                        
                        Text(primaryName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                } else {
                    Text("📦 \(primaryName)")
                        .font(.headline)
                        .lineLimit(1)
                }

                if let secondaryName {
                    Text(secondaryName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let packageName = apkAnalysis?.packageName {
                    Text(packageName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let version = analysis.version {
                    Text("Version: \(version)")
                        .font(.caption)
                }
                if let buildNumber = analysis.buildNumber {
                    Text("Build number: \(buildNumber)")
                        .font(.caption)
                }
                
                Text("Total: \(ByteCountFormatter.string(fromByteCount: analysis.totalSize, countStyle: .file))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let role = role {
                Text(role == .base ? "Base" : "Comparison")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(role == .base ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                    .cornerRadius(8)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(theme.palette.accent)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.palette.surface)
                .shadow(color: role != nil ? theme.palette.accent.opacity(0.25) : theme.palette.shadow.opacity(theme.colorScheme == .dark ? 0.18 : 0.06), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(role != nil ? theme.palette.accent : theme.palette.border, lineWidth: role != nil ? 2 : 1)
        )
    }
}
