import Foundation
import SwiftUI

struct APKAnalyzerContentView: View {
    @ObservedObject var viewModel: APKViewModel

    var body: some View {
        analysesList
            .navigationTitle("APK/ABB Analyses")
            .onAppear {
                viewModel.loadAnalyses()
            }
    }

    @ViewBuilder
    var analysesList: some View {
        ScrollView {
            LazyVStack {
                ForEach(viewModel.sortedGroupKeys, id: \.self) { identifier in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { viewModel.expandedExecutables.contains(identifier) },
                            set: { isExpanding in
                                if isExpanding {
                                    viewModel.expandedExecutables.insert(identifier)
                                } else {
                                    viewModel.expandedExecutables.remove(identifier)
                                }
                            }
                        ),
                        content: {
                            analysisRowView(with: identifier)
                        },
                        label: {
                            analysisGroupView(with: identifier)
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listStyle(.inset)
                }
            }
        }
        .padding()
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    func analysisGroupView(with identifier: String) -> some View {
        let displayIdentifier = identifier.isEmpty ? "Unknown Identifier" : identifier
        let builds = viewModel.groupedAnalyses[identifier] ?? []
        let latest = builds.first
        let primaryTitle = latest?.packageName ?? displayIdentifier
        let packageSubtitle = latest?.appLabel != nil ? displayIdentifier : nil

        HStack {
            if let image = latest?.image {
                Image(nsImage: image)
                    .resizable().scaledToFit().frame(width: 24, height: 24).cornerRadius(5)
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 24))
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading) {
                Text(primaryTitle).font(.headline)
                if let packageSubtitle {
                    Text(packageSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(builds.count) builds")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(4)
    }

    @ViewBuilder
    func analysisRowView(with identifier: String) -> some View {
        if let analysesForIdentifier = viewModel.groupedAnalyses[identifier] {
            ForEach(analysesForIdentifier) { analysis in
                AppAnalysisRow(
                    analysis: analysis,
                    role: (
                        viewModel.selectedUUID == analysis.id
                    ) ? .base : nil
                )

                .onTapGesture {
                    withAnimation {
                        viewModel.toggleSelection(analysis.id)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        viewModel.deleteAnalysis(withId: analysis.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        viewModel.revealAnalysesJSONInFinder()
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }
                .animation(.spring(), value: viewModel.selectedUUID)
            }
        }
    }
}

struct APKAnalyzerDetailView: View {
    @ObservedObject var viewModel: APKViewModel

    var body: some View {
        VStack {
            if viewModel.compareMode {
                CompareView(analyses: viewModel.analyses)
            } else if let selected = viewModel.selectedAnalysis {
                DetailView(
                    viewModel: APKDetailViewModel(
                        analysis: selected,
                        apkViewModel: viewModel
                    )
                )
                .id(selected.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Drop or import an .apk/.aab file 🤖")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.selectFile()
                } label: {
                    Label("Add APK/ABB", systemImage: "plus")
                }
                .help("New Analysis")

                Button(action: { viewModel.exportToCSV() }) {
                    Label("Export as CSV", systemImage: "square.and.arrow.up")
                }

                if !viewModel.analyses.isEmpty {
                    Button(viewModel.compareMode ? "Done" : "Compare") {
                        withAnimation { viewModel.compareMode.toggle() }
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url, ["apk", "aab", "abb"].contains(url.pathExtension.lowercased()) {
                        Task {
                            await viewModel.analyzeFile(url)
                        }
                    }
                }
            }
            return true
        }
    }
}
