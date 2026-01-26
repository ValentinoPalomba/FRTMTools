import SwiftUI

struct BadWordScannerContentView: View {
    @Bindable var viewModel: BadWordScannerViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bad Word Scanner")
                .font(.largeTitle.bold())
            Text("Scan an IPA or .app bundle for profanities across resources and binaries (using `strings`).")
                .foregroundStyle(.secondary)

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
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if let result = viewModel.scanResult {
                summaryView(result: result, duration: viewModel.lastDuration)
            } else {
                Text("Choose an IPA to start scanning.")
                    .foregroundStyle(.secondary)
            }

            BadWordScannerHistorySection(viewModel: viewModel)

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
            .foregroundStyle(.secondary)
        }
    }

}
