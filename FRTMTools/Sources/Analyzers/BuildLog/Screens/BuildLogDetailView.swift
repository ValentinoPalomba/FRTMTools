import SwiftUI

struct BuildLogDetailView: View {
    @ObservedObject var viewModel: BuildLogViewModel

    var body: some View {
        if let entry = viewModel.selectedReport {
            BuildLogReportView(
                report: entry.report
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "hammer")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Build Log Analyzer")
                    .font(.title)
                Text("Import an xcactivitylog, xcodeproj, xcworkspace, or a folder.")
                    .foregroundColor(.secondary)
                Button("Import Build Input", systemImage: "doc.text") {
                    viewModel.importBuildInput()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
