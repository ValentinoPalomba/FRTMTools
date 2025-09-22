import SwiftUI

struct DeadCodeContentView: View {
    @ObservedObject var viewModel: DeadCodeViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Button(action: {
                viewModel.selectProjectFromFile()
            }) {
                Label("Scan New Project", systemImage: "plus.circle")
            }
            .padding()

            List(selection: $viewModel.selectedAnalysisID) {
                if viewModel.analyses.isEmpty {
                    Text("No scans yet. Run a new scan to begin.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.analyses) { analysis in
                        VStack(alignment: .leading) {
                            Text(analysis.projectName)
                                .font(.headline)
                            Text(
                                analysis.scanTimeDuration.formatted()
                            )
                                .font(.caption)
                            Text("\(analysis.results.count) issues found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(analysis.id)
                    }
                }
            }
            .listStyle(InsetListStyle())
        }
        .navigationTitle("Dead Code Scans")
        .sheet(isPresented: .constant(viewModel.projectToScan != nil && viewModel.isLoadingSchemes)) {
            SchemeSelectionView(viewModel: viewModel)
        }
    }
}

// This helper view is still needed
struct SchemeSelectionView: View {
    @ObservedObject var viewModel: DeadCodeViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("Select Scheme for")
                .font(.title2)
            Text(viewModel.projectToScan?.lastPathComponent ?? "")
                .font(.title2.bold())

            if viewModel.isLoadingSchemes && viewModel.schemes.isEmpty {
                ProgressView("Loading Schemes...")
            } else if !viewModel.schemes.isEmpty {
                Picker("Available Schemes", selection: $viewModel.selectedScheme) {
                    Text("Select a scheme").tag(String?.none)
                    ForEach(viewModel.schemes, id: \.self) { scheme in
                        Text(scheme).tag(scheme as String?)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                Button("Run Scan") {
                    viewModel.runScan()
                }
                .disabled(viewModel.selectedScheme == nil)
                .keyboardShortcut(.defaultAction)
            } else {
                Text("No schemes found for this project.")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 400, height: 250)
        .padding()
    }
}
