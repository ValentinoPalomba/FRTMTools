
import SwiftUI

struct MainView: View {
    @StateObject private var viewModel = IPAViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                List {
                    ForEach(viewModel.analyses) { analysis in
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
                            }
                            .animation(.spring(), value: viewModel.selectedUUID)
                    }
                }
                .listRowSeparator(.hidden)
                .listStyle(.plain)
                
                // Stato di caricamento
                if viewModel.isLoading {
                    ProgressView("Analyzing IPA…")
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                        .padding()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        viewModel.selectIPAFile()
                    } label: {
                        Label("Add IPA", systemImage: "plus")
                    }
                    
                    if !viewModel.analyses.isEmpty {
                        Button(viewModel.compareMode ? "Done" : "Compare") {
                            withAnimation { viewModel.compareMode.toggle() }
                        }
                    }
                }
            }
            
            // Dettaglio / Confronto
            Group {
                if viewModel.compareMode {
                    CompareView(analyses: viewModel.analyses)
                } else if let selected = viewModel.analyses.first(where: { $0.id == viewModel.selectedUUID }) ?? viewModel.analyses.first {
                    DetailView(analysis: selected)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Drop or import an IPA file 📦")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            viewModel.loadAnalyses()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url, url.pathExtension == "ipa" {
                        viewModel.analyzeIPAFile(url)
                    }
                }
            }
            return true
        }
    }
}
