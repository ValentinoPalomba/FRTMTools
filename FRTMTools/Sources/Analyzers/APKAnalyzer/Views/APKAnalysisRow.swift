//
//  APKAnalysisRow.swift
//  FRTMTools
//
//

import SwiftUI

/// Row view for displaying APK analysis in a list
struct APKAnalysisRow: View {
    let analysis: APKAnalysis

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let image = analysis.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "app.dashed")
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(analysis.packageName ?? "Unknown Package")
                    .font(.headline)

                if let appLabel = analysis.appLabel {
                    Text(appLabel)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    if let version = analysis.versionName {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let versionCode = analysis.versionCode {
                        Text("(\(versionCode))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let abis = analysis.supportedABIs, !abis.isEmpty {
                        Text(abis.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatSize(analysis.totalSize))
                    .font(.headline)

                if let installedSize = analysis.installedSize {
                    Text("\(installedSize.total) MB installed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
