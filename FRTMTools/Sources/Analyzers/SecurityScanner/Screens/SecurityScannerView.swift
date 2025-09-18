
import SwiftUI

struct SecurityScannerContentView: View {
    @ObservedObject var viewModel: SecurityScannerViewModel

    var body: some View {
        VStack {
            if viewModel.analyses.isEmpty {
                Text("No scans performed yet.")
                    .foregroundColor(.secondary)
            } else {
                List(selection: $viewModel.selectedAnalysisID) {
                    ForEach(viewModel.analyses) {
                        analysis in
                        NavigationLink(value: analysis.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("📦 \(analysis.projectName)")
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                Text(analysis.projectPath)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding()
                        }
                        .tag(analysis.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteAnalysis(analysis)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Security Scans")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.selectFolderAndScan()
                } label: {
                    Label("Scan Project", systemImage: "folder.badge.plus")
                }
                .help("Scan new project")
            }
        }
        .onAppear {
            viewModel.loadAnalyses()
        }
        .alert(item: $viewModel.analysisToOverwrite) {
 analysis in
            Alert(
                title: Text("Analysis Exists"),
                message: Text("An analysis for \(analysis.projectName) already exists. Do you want to overwrite it?"),
                primaryButton: .destructive(Text("Overwrite")) { viewModel.forceReanalyze() },
                secondaryButton: .cancel() { viewModel.cancelOverwrite() }
            )
        }
    }
}
