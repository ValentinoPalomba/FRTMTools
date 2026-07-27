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
            .controlSize(.large)
            .padding([.horizontal, .top])

            List(selection: $viewModel.selectedAnalysisID) {
                if viewModel.analyses.isEmpty {
                    ContentUnavailableView(
                        "No Scans Yet",
                        systemImage: "text.magnifyingglass",
                        description: Text("Run a scan to inspect unused declarations.")
                    )
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
            .listStyle(.inset)
        }
        .navigationTitle("Dead Code Scans")
        .sheet(isPresented: schemeSelectionPresented, onDismiss: viewModel.cancelSchemeSelection) {
            SchemeSelectionView(viewModel: viewModel)
        }
    }

    private var schemeSelectionPresented: Binding<Bool> {
        Binding(
            get: { viewModel.projectToScan != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelSchemeSelection()
                }
            }
        )
    }
}

struct SchemeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: DeadCodeViewModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Project") {
                        Text(viewModel.projectToScan?.lastPathComponent ?? "Unknown")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Section("Scheme") {
                    if viewModel.isLoadingSchemes {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading schemes…")
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.schemes.isEmpty {
                        ContentUnavailableView(
                            "No Schemes Found",
                            systemImage: "xcode",
                            description: Text("The selected project has no shared schemes.")
                        )
                    } else {
                        Picker("Available Scheme", selection: $viewModel.selectedScheme) {
                            Text("Choose a scheme").tag(String?.none)
                            ForEach(viewModel.schemes, id: \.self) { scheme in
                                Text(scheme).tag(scheme as String?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    viewModel.cancelSchemeSelection()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Run Scan") {
                    viewModel.runScan()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedScheme == nil || viewModel.isLoadingSchemes)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 300)
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
