import SwiftUI

struct InstalledSizeAnalysisView<ViewModel: InstalledSizeAnalyzing, Analysis: AppAnalysis>: View where ViewModel.Analysis == Analysis {
    @Bindable var viewModel: ViewModel
    let analysis: Analysis

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Text("📱 Installed App Size")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if viewModel.isSizeLoading {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                    Text(viewModel.sizeAnalysisProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let size = analysis.installedSize {
                VStack(alignment: .leading, spacing: 10) {
                    // Total installed size
                    Text("\(size.total) MB")
                        .font(.title)
                        .bold()
                        .foregroundStyle(.primary)

                    // Breakdown
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("• App Binaries")
                            Spacer()
                            Text("\(size.binaries) MB")
                        }
                        HStack {
                            Text("• Frameworks")
                            Spacer()
                            Text("\(size.frameworks) MB")
                        }
                        HStack {
                            Text("• Other Resources")
                            Spacer()
                            Text("\(size.resources) MB")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    viewModel.analyzeSize(for: analysis.id)
                } label: {
                    Text("Analyze Size")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
        .alert(
            viewModel.sizeAnalysisAlert?.title ?? "Size Analysis",
            isPresented: sizeAlertPresented,
            presenting: viewModel.sizeAnalysisAlert
        ) { _ in
            Button("OK", role: .cancel) {
                viewModel.sizeAnalysisAlert = nil
            }
        } message: { alert in
            Text(alert.message)
        }
    }

    private var sizeAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.sizeAnalysisAlert != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.sizeAnalysisAlert = nil
                }
            }
        )
    }
}
