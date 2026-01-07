import SwiftUI

struct DeadCodeContentView: View {
    @Bindable var viewModel: DeadCodeViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Button {
                viewModel.selectProjectFromFile()
            } label: {
                Label("Scan New Project", systemImage: "plus.circle")
            }
            .padding()

            List(selection: $viewModel.selectedAnalysisID) {
                if viewModel.analyses.isEmpty {
                    Text("No scans yet. Run a new scan to begin.")
                        .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
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
            }
            .listStyle(InsetListStyle())
        }
        .navigationTitle("Dead Code Scans")
        .sheet(isPresented: .constant(viewModel.projectToScan != nil && viewModel.isLoadingSchemes)) {
            SchemeSelectionView(viewModel: viewModel)
        }
    }
}

struct SchemeSelectionView: View {
    @Bindable var viewModel: DeadCodeViewModel

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
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 400, height: 250)
        .padding()
    }
}


func format(duration: TimeInterval) -> String {
    if duration == 0 { return "0s" }

    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60

    if minutes > 0 {
        return "\(minutes)m \(seconds)s"
    } else {
        if duration < 1 {
            let rounded = (duration * 100).rounded() / 100
            return "\(rounded)s"
        }
        return "\(seconds)s"
    }
}
