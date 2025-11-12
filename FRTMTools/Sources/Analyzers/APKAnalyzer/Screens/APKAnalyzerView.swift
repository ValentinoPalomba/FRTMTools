//
//  APKAnalyzerView.swift
//  FRTMTools
//
//

import SwiftUI

/// Main view for APK analysis
struct APKAnalyzerView: View {
    @StateObject private var viewModel = APKViewModel()

    var body: some View {
        NavigationSplitView {
            APKAnalyzerContentView(viewModel: viewModel)
        } detail: {
            APKAnalyzerDetailView(viewModel: viewModel)
        }
    }
}

/// Content view showing list of analyses
struct APKAnalyzerContentView: View {
    @ObservedObject var viewModel: APKViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.analyses.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else {
                analysisList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.selectAPK()
                } label: {
                    Label("Analyze APK", systemImage: "plus")
                }
                .disabled(viewModel.isLoading)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.compareMode.toggle()
                } label: {
                    Label("Compare", systemImage: "arrow.left.arrow.right")
                }
                .disabled(viewModel.analyses.count < 2)
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Toggle(isOn: $viewModel.useAaptForParsing) {
                        Label("Use aapt (if available)", systemImage: "terminal.fill")
                    }

                    Text("When disabled, uses Python script fallback")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .navigationTitle("APK Analyzer")
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 64))
                .foregroundColor(.gray)

            Text("No APK Analyses")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Click the + button to analyze an APK file")
                .font(.body)
                .foregroundColor(.secondary)

            Button {
                viewModel.selectAPK()
            } label: {
                Label("Analyze APK", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var analysisList: some View {
        List(selection: $viewModel.selectedUUID) {
            if viewModel.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing APK...")
                        .foregroundColor(.secondary)
                }
            }

            ForEach(viewModel.groupedAnalyses, id: \.key) { packageName, analyses in
                Section(header: Text(packageName)) {
                    ForEach(analyses) { analysis in
                        APKAnalysisRow(analysis: analysis)
                            .tag(analysis.id)
                            .contextMenu {
                                Button {
                                    if let url = try? viewModel.exportToCSV(analysis) {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                } label: {
                                    Label("Export to CSV", systemImage: "square.and.arrow.up")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteAnalysis(analysis)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// Detail view showing analysis or comparison
struct APKAnalyzerDetailView: View {
    @ObservedObject var viewModel: APKViewModel

    var body: some View {
        if viewModel.compareMode {
            comparisonView
        } else if let analysis = viewModel.selectedAnalysis {
            APKDetailView(analysis: analysis)
                .id(analysis.id)
        } else {
            emptyDetailView
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 64))
                .foregroundColor(.gray)

            Text("Select an APK analysis")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose an analysis from the sidebar to view details")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var comparisonView: some View {
        VStack {
            Text("APK Comparison")
                .font(.title)

            Text("Select two analyses from the same package to compare")
                .foregroundColor(.secondary)

            // TODO: Implement comparison picker and view
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
