
import SwiftUI

struct SecurityScannerResultView: View {
    @ObservedObject var viewModel: SecurityScannerViewModel

    var body: some View {
        Group {
            if let analysis = viewModel.selectedAnalysis {
                if analysis.findings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text("No Secrets Found")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("The scan of \(analysis.projectName) completed successfully and found no hardcoded secrets.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List(analysis.findings) { finding in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finding.filePath)
                                .font(.headline)
                            Text("Line \(finding.lineNumber): \(finding.content)")
                                .font(.body)
                                .foregroundColor(.secondary)
                            Text("Rule: \(finding.ruleName)")
                                .font(.caption)
                                .foregroundColor(.red)
                                .bold()
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select an analysis or start a new scan.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(viewModel.selectedAnalysis?.projectName ?? "Scan Results")
    }
}
