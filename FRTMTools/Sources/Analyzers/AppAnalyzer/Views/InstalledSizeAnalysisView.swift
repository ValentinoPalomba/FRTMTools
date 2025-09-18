import SwiftUI

struct InstalledSizeAnalysisView: View {
    @ObservedObject var viewModel: IPAViewModel
    let analysis: IPAAnalysis
    

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📱 Installed App Size")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if viewModel.isSizeLoading {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                    Text(viewModel.sizeAnalysisProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else if let size = analysis.installedSize {
                VStack(alignment: .leading, spacing: 10) {
                    // Total installed size
                    Text("\(size.total) MB")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

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
                    .foregroundColor(.secondary)
                }
            } else {
                Button(action: {
                    viewModel.analyzeSize()
                }) {
                    Text("Analyze Size")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .alert(item: $viewModel.sizeAnalysisAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
