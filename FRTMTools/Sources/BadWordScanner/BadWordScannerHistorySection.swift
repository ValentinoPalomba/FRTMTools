import SwiftUI

struct BadWordScannerHistorySection: View {
    @Bindable var viewModel: BadWordScannerViewModel

    var body: some View {
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
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.history) { record in
                            BadWordScannerHistoryRow(
                                record: record,
                                isSelected: viewModel.selectedRecordID == record.id,
                                isScanning: viewModel.isScanning,
                                select: { viewModel.select(record: record) },
                                reveal: { viewModel.reveal(record: record) },
                                delete: { Task { await viewModel.delete(record: record) } }
                            )
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
