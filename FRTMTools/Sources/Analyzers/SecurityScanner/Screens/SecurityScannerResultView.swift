
import SwiftUI

struct SecurityScannerResultView: View {
    @Bindable var viewModel: SecurityScannerViewModel

    var body: some View {
        Group {
            if let analysis = viewModel.selectedAnalysis {
                if analysis.findings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundStyle(.green)
                        Text("No Secrets Found")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("The scan of \(analysis.projectName) completed successfully and found no hardcoded secrets.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                            Text("Rule: \(finding.ruleName)")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .bold()
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                    Text("Select an analysis or start a new scan.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(viewModel.selectedAnalysis?.projectName ?? "Scan Results")
    }
}
