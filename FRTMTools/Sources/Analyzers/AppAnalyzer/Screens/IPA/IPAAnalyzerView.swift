//
//  IPAAnalyzerView.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//
import Foundation
import SwiftUI

struct IPAAnalyzerContentView: View {
    @Bindable var viewModel: IPAViewModel
    
    var body: some View {
        analysesList
        .navigationTitle("IPA Analyses")
        .task {
            viewModel.loadAnalyses()
        }
    }
    
    
    @ViewBuilder
    var analysesList: some View {
        ScrollView {
            LazyVStack {
                ForEach(viewModel.sortedGroupKeys, id: \.self) { executableName in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { viewModel.expandedExecutables.contains(executableName) },
                            set: { isExpanding in
                                if isExpanding {
                                    viewModel.expandedExecutables.insert(executableName)
                                } else {
                                    viewModel.expandedExecutables.remove(executableName)
                                }
                            }
                        ),
                        content: {
                            analysisRowView(with: executableName)
                        },
                        label: {
                            analysisGroupView(with: executableName)
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
    func analysisGroupView(with executableName: String) -> some View {
        HStack {
            if let firstAnalysis = viewModel.groupedAnalyses[executableName]?.first, let image = firstAnalysis.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(.rect(cornerRadius: 5))
            } else {
                Image(systemName: "app.box.fill")
                    .font(.title3)
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading) {
                Text(executableName).font(.headline)
                Text("\(viewModel.groupedAnalyses[executableName]?.count ?? 0) builds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }
    
    @ViewBuilder
    func analysisRowView(with executableName: String) -> some View {
        if let analysesForExecutable = viewModel.groupedAnalyses[executableName] {
            ForEach(analysesForExecutable) { analysis in
                Button {
                    withAnimation {
                        viewModel.toggleSelection(analysis.id)
                    }
                } label: {
                    AppAnalysisRow(
                        analysis: analysis,
                        role: viewModel.selectedUUID == analysis.id ? .base : nil
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        viewModel.deleteAnalysis(withId: analysis.id)
                    }
                    Button("Show in Finder", systemImage: "folder") {
                        viewModel.revealAnalysesJSONInFinder()
                    }
                }
                .animation(.spring(), value: viewModel.selectedUUID)
            }
        }
    }
}


struct IPAAnalyzerDetailView: View {
    @Bindable var viewModel: IPAViewModel
    @State private var showAIChat = false

    var body: some View {
        VStack {
            if viewModel.compareMode {
                CompareView(analyses: viewModel.analyses)
            } else if let selected = viewModel.selectedAnalysis {
                DetailView(
                    viewModel: IPADetailViewModel(
                        analysis: selected,
                        ipaViewModel: viewModel
                    )
                )
                .id(selected.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                    Text("Drop or import an .ipa/.app file 📦")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.selectFile()
                } label: {
                    Label("Add IPA", systemImage: "plus")
                }
                .help("New Analysis")
                
                Button {
                    viewModel.exportToCSV()
                } label: {
                    Label("Export as CSV", systemImage: "square.and.arrow.up")
                }
                
                if !viewModel.analyses.isEmpty {
                    Button(viewModel.compareMode ? "Done" : "Compare") {
                        withAnimation { viewModel.compareMode.toggle() }
                    }
                }
                if viewModel.selectedAnalysis != nil {
                    Button {
                        showAIChat = true
                    } label: {
                        Label("AI Insights", systemImage: "sparkles")
                    }
                    .help("Chat with a local model about this analysis")
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url, ["ipa", "app"].contains(url.pathExtension.lowercased()) {
                        Task {
                            await viewModel.analyzeFile(url)
                        }
                    }
                }
            }
            return true
        }
        .sheet(isPresented: $showAIChat) {
            if let analysis = viewModel.selectedAnalysis {
                AIChatView(
                    analysis: analysis,
                    categories: viewModel.categories(for: analysis),
                    tips: viewModel.tips(for: analysis),
                    archs: viewModel.archs(for: analysis)
                )
                .frame(minWidth: 640, minHeight: 560)
            } else {
                Text("Select an analysis to start chatting.")
                    .padding()
            }
        }
    }
}
