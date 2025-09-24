//
//  IPAAnalyzerView.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//
import Foundation
import SwiftUI

struct IPAAnalyzerContentView: View {
    @ObservedObject var viewModel: IPAViewModel
    
    var body: some View {
        analysesList
        .navigationTitle("IPA Analyses")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.selectFile()
                } label: {
                    Label("Add IPA", systemImage: "plus")
                }
                .help("New Analysis")
                
                if !viewModel.analyses.isEmpty {
                    Button(viewModel.compareMode ? "Done" : "Compare") {
                        withAnimation { viewModel.compareMode.toggle() }
                    }
                }
            }
        }
        .onAppear {
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
                    .resizable().scaledToFit().frame(width: 24, height: 24).cornerRadius(5)
            } else {
                Image(systemName: "app.box.fill")
                    .font(.system(size: 24))
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading) {
                Text(executableName).font(.headline)
                Text("\(viewModel.groupedAnalyses[executableName]?.count ?? 0) builds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(4)
    }
    
    @ViewBuilder
    func analysisRowView(with executableName: String) -> some View {
        if let analysesForExecutable = viewModel.groupedAnalyses[executableName] {
            ForEach(analysesForExecutable) { analysis in
                IPAAnalysisRow(
                    analysis: analysis,
                    role: (
                        viewModel.selectedUUID == analysis.id
                    ) ? .base : nil
                )
                .onTapGesture {
                    viewModel.toggleSelection(analysis.id)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        if let index = viewModel.analyses.firstIndex(where: { $0.id == analysis.id }) {
                            viewModel.deleteAnalysis(at: IndexSet(integer: index))
                        }
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


struct IPAAnalyzerDetailView: View {
    @ObservedObject var viewModel: IPAViewModel

    var body: some View {
        Group {
            if viewModel.compareMode {
                CompareView(analyses: viewModel.analyses)
            } else if let selected = viewModel.analyses.first(where: { $0.id == viewModel.selectedUUID }) ?? viewModel.analyses.first {
                DetailView(analysis: selected, ipaViewModel: viewModel)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Drop or import an .ipa/.app file 📦")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url, ["ipa", "app"].contains(url.pathExtension.lowercased()) {
                        viewModel.analyzeFile(url)
                    }
                }
            }
            return true
        }
    }
}

