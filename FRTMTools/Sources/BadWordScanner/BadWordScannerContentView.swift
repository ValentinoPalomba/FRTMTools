import SwiftUI

struct BadWordScannerContentView: View {
    @ObservedObject var viewModel: BadWordScannerViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bad Word Scanner")
                .font(.largeTitle.bold())
            Text("Scan an IPA or .app bundle for profanities across resources and binaries (using `strings`).")
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button {
                    viewModel.pickIPA()
                } label: {
                    Label("Select IPA / .app", systemImage: "doc.badge.plus")
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(viewModel.isScanning || viewModel.dictionaryWords.isEmpty)

                Button {
                    viewModel.pickDictionary()
                } label: {
                    Label("Select Dictionary", systemImage: "text.book.closed")
                }
                .disabled(viewModel.isScanning)

                if viewModel.isScanning {
                    Button {
                        viewModel.stopScan()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let dictionaryName = viewModel.dictionaryURL?.lastPathComponent {
                Text("Dictionary: \(dictionaryName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            } else if let result = viewModel.scanResult {
                summaryView(result: result, duration: viewModel.lastDuration)
            } else {
                Text("Choose an IPA to start scanning.")
                    .foregroundColor(.secondary)
            }

            historySection

            Spacer()
        }
        .padding()
    }

    private func summaryView(result: BadWordScanResult, duration: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Scan")
                .font(.headline)
            HStack {
                Label("\(result.matches.count) hits", systemImage: "exclamationmark.bubble")
                Label("\(result.scannedFiles) files", systemImage: "doc.on.doc")
                Label("\(result.dictionarySize) dictionary entries", systemImage: "text.book.closed")
                if let duration {
                    Label(BadWordScannerViewModel.formatDuration(duration), systemImage: "clock")
                }
            }
            .foregroundColor(.secondary)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Previous Scans")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { await viewModel.loadHistory() }
                }
                .buttonStyle(.link)
                .disabled(viewModel.isScanning)
            }

            if viewModel.history.isEmpty {
                Text("No scans yet.")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.history) { record in
                            Button {
                                viewModel.select(record: record)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.fileName)
                                            .font(.subheadline.bold())
                                        Text(record.scannedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Label("\(record.result.matches.count)", systemImage: "exclamationmark.bubble")
                                        .foregroundColor(record.result.matches.isEmpty ? .secondary : .red)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(viewModel.selectedRecordID == record.id ? theme.palette.accent.opacity(theme.colorScheme == .dark ? 0.22 : 0.16) : theme.palette.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(viewModel.selectedRecordID == record.id ? theme.palette.accent.opacity(0.55) : theme.palette.border)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open in Finder") {
                                    viewModel.reveal(record: record)
                                }
                                Button("Delete", role: .destructive) {
                                    Task { await viewModel.delete(record: record) }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
