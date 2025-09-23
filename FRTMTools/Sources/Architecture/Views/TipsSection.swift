import SwiftUI

struct TipsSection: View {
    let tips: [Tip]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💡 Tips & Suggestions")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            ForEach(tips) { tip in
                HStack(alignment: .top) {
                    Text(emoji(for: tip.category))
                        .font(.title3)
                    VStack(alignment: .leading) {
                        Text(tip.category.rawValue)
                            .font(.headline)
                        Text(tip.text)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                .padding(.horizontal)
            }
        }
    }
    
    private func emoji(for category: TipCategory) -> String {
        switch category {
        case .optimization: return "🚀"
        case .warning: return "⚠️"
        case .info: return "ℹ️"
        }
    }
}
