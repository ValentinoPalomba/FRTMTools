import SwiftUI

struct BadWordScannerDetailView: View {
    @Bindable var viewModel: BadWordScannerViewModel

    var body: some View {
        Group {
            if viewModel.isScanning {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(viewModel.progressMessage ?? "Scanning IPA for bad words…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = viewModel.scanResult {
                resultsView(result: result, duration: viewModel.lastDuration)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Try Again") {
                        if let url = viewModel.selectedIPA {
                            viewModel.scan(ipaURL: url)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select an IPA from the sidebar to run the scan.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            if !viewModel.logMessages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Activity")
                        .font(.caption.bold())
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(viewModel.logMessages.suffix(80).enumerated()), id: \.offset) { _, log in
                                Text(log)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
                .padding()
                .dsSurface(.elevated, cornerRadius: DS.Radius.lg, border: true, shadow: false)
            }
        }
    }

    private func resultsView(result: BadWordScanResult, duration: TimeInterval?) -> some View {
        let grouped = Dictionary(grouping: result.matches, by: \.path)
            .sorted(by: { $0.key < $1.key })

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryBadges(result: result, duration: duration)
                matchesList(grouped: grouped)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func summaryBadges(result: BadWordScanResult, duration: TimeInterval?) -> some View {
        HStack(spacing: 16) {
            badge(title: "Hits", value: "\(result.matches.count)", color: .red)
            badge(title: "Files", value: "\(result.scannedFiles)", color: .blue)
            badge(title: "Dictionary", value: "\(result.dictionarySize)", color: .gray)
            if let duration {
                badge(title: "Time", value: BadWordScannerViewModel.formatDuration(duration), color: .green)
            }
        }
    }

    @ViewBuilder
    private func matchesList(grouped: [(key: String, value: [BadWordMatch])]) -> some View {
        if grouped.isEmpty {
            Text("No bad words found.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(grouped), id: \.0) { path, matches in
                VStack(alignment: .leading, spacing: 8) {
                    Text(path)
                        .font(.headline)
                    ForEach(matches, id: \.self) { match in
                        matchRow(match: match)
                    }
                }
                .dsCard(.surface, cornerRadius: DS.Radius.md, padding: DS.Spacing.lg, shadow: false)
            }
        }
    }

    private func matchRow(match: BadWordMatch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(match.word)
                    .font(.subheadline.bold())
                Text("• \(sourceLabel(for: match))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let context = match.context, !context.isEmpty {
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(8)
        .dsSurface(.elevated, cornerRadius: DS.Radius.sm, border: false, shadow: false)
    }

    private func sourceLabel(for match: BadWordMatch) -> String {
        switch match.source {
        case .binaryStrings: return "Binary"
        case .text: return "Text"
        case .filename: return "Filename"
        }
    }

    private func badge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
    }
}
