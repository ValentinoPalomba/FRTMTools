
import SwiftUI

struct SecurityScannerContentView: View {
    @Bindable var viewModel: SecurityScannerViewModel

    var body: some View {
        VStack {
            if viewModel.analyses.isEmpty {
                ContentUnavailableView {
                    Label("No Security Scans", systemImage: "shield.lefthalf.filled")
                } description: {
                    Text("Scan a project to inspect potential security findings.")
                } actions: {
                    Button("Scan Project", action: viewModel.selectFolderAndScan)
                }
            } else {
                List(selection: $viewModel.selectedAnalysisID) {
                    ForEach(viewModel.analyses) { analysis in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(analysis.projectName, systemImage: "shippingbox")
                                .font(.headline)
                                .lineLimit(1)

                            Text(analysis.projectPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
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
                .listStyle(.inset)
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
            
            ToolbarItem {
                Button {
                    viewModel.exportToCSV()
                } label: {
                    Label("Export as CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.selectedAnalysis == nil || viewModel.selectedAnalysis?.findings.isEmpty == true)
            }
        }
        .task {
            viewModel.loadAnalyses()
        }
        .alert(
            "Analysis Exists",
            isPresented: overwriteConfirmationPresented,
            presenting: viewModel.analysisToOverwrite
        ) { _ in
            Button("Overwrite", role: .destructive, action: viewModel.forceReanalyze)
            Button("Cancel", role: .cancel, action: viewModel.cancelOverwrite)
        } message: { analysis in
            Text("An analysis for \(analysis.projectName) already exists. Do you want to overwrite it?")
        }
    }

    private var overwriteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { viewModel.analysisToOverwrite != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelOverwrite()
                }
            }
        )
    }
}
