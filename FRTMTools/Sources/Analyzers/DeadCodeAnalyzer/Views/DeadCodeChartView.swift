
import SwiftUI
import Charts

struct DeadCodeChartView: View {
    let results: [SerializableDeadCodeResult]

    private var chartData: [ChartData] {
        let counts = results.reduce(into: [:]) { counts, result in
            counts[result.kind, default: 0] += 1
        }
        
        let sortedCounts = counts.sorted { $0.value > $1.value }
        let top5 = sortedCounts.prefix(5)
        let otherCount = sortedCounts.dropFirst(5).reduce(0) { $0 + $1.value }
        
        var data = top5.map { ChartData(name: $0.key, count: $0.value) }
        if otherCount > 0 {
            data.append(ChartData(name: "Other", count: otherCount))
        }
        return data
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dead Code Distribution")
                .font(.title3).bold()
            
            Chart(chartData) { data in
                SectorMark(
                    angle: .value("Count", data.count),
                    innerRadius: .ratio(0.618),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Type", data.name))
                .annotation(position: .overlay) {
                    if data.count > (chartData.map({$0.count}).reduce(0, +) / 10) { // only show count if slice is big enough
                        Text("\(data.count)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .bold()
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .center, spacing: 10)
            .frame(height: 250)
            .padding(.horizontal)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

private struct ChartData: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}
