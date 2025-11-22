
import SwiftUI

// MARK: - CompareView

struct CompareView<Analysis: AppAnalysis>: View {
    let analyses: [Analysis]
    @State private var baseId: UUID?
    @State private var compareId: UUID?

    var body: some View {
        VStack {
            if baseId == nil || compareId == nil {
                List(analyses) { analysis in
                    let role = getRole(for: analysis.id)
                    AppAnalysisRow(analysis: analysis, role: role)
                        .onTapGesture {
                            toggleSelection(analysis.id)
                        }
                }
                .listStyle(.plain)
                .navigationTitle("Select 2 files to compare")
            } else {
                if let first = analyses.first(where: { $0.id == baseId }),
                   let second = analyses.first(where: { $0.id == compareId }) {
                    ComparisonDetail(first: first, second: second)
                }
            }
        }
    }

    private func getRole(for id: UUID) -> SelectionRole? {
        if id == baseId {
            return .base
        } else if id == compareId {
            return .comparison
        }
        return nil
    }

    private func toggleSelection(_ id: UUID) {
        if id == baseId {
            baseId = nil
        } else if id == compareId {
            compareId = nil
        } else if baseId == nil {
            baseId = id
        } else if compareId == nil {
            compareId = id
        }
    }
}
