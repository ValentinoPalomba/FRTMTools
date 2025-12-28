import SwiftUI

struct BuildLogContentView: View {
    @ObservedObject var viewModel: BuildLogViewModel

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Import Build Input", systemImage: "doc.text") {
                    viewModel.importBuildInput()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()

            List(selection: $viewModel.selectedReportID) {
                ForEach(viewModel.reports) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .font(.headline)
                            .lineLimit(1)

                        Text(dateFormatter.string(from: entry.createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                    .tag(entry.id)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            viewModel.deleteReport(entry)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .errorAlert(error: $viewModel.error)
    }
}
