
import SwiftUI

// Modern IPA Row
struct IPAAnalysisRow: View {
    let analysis: IPAAnalysis
    let role: SelectionRole?

    var body: some View {
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
                        
                        Text("\(analysis.fileName)")
                            .font(.headline)
                            .lineLimit(1)
                    }
                } else {
                    Text("📦 \(analysis.fileName)")
                        .font(.headline)
                        .lineLimit(1)
                }
                
                if let buildNumber = analysis.buildNumber {
                    Text("Build number: \(buildNumber)")
                        .font(.caption)
                }
                if let version = analysis.version {
                    Text("Version: \(version)")
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
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: role != nil ? .accentColor.opacity(0.3) : .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(role != nil ? Color.accentColor : .clear, lineWidth: 2)
        )
        .animation(.spring(), value: role != nil)
    }
}
