import SwiftUI

struct InstalledSizeAnalysisView: View {
    @ObservedObject var viewModel: IPAViewModel
    let analysis: IPAAnalysis
    

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Installed App Size")
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
                Text("\(size) MB")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            } else {
                Button(action: {
                    viewModel.analyzeSize()
                }) {
                    Text("Analyze Size")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
