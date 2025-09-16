import SwiftUI

struct TipsSection: View {
    let tips: [Tip]
    @State private var expandedTips: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💡 Tips & Suggestions")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            ForEach(tips) { tip in
                VStack(spacing: 0) {
                    Button(action: {
                        if !tip.subTips.isEmpty {
                            toggle(tip: tip)
                        }
                    }) {
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
                            
                            Spacer()
                            
                            if !tip.subTips.isEmpty {
                                Image(systemName: expandedTips.contains(tip.id) ? "chevron.up" : "chevron.down")
                            }
                        }
                        .padding()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if expandedTips.contains(tip.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(tip.subTips) { subTip in
                                HStack(alignment: .top) {
                                    Text(emoji(for: subTip.category))
                                        .font(.body)
                                    Text(subTip.text)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.leading, 28)
                            }
                        }
                        .padding(.bottom)
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                .padding(.horizontal)
            }
        }
    }
    
    private func toggle(tip: Tip) {
        if expandedTips.contains(tip.id) {
            expandedTips.remove(tip.id)
        } else {
            expandedTips.insert(tip.id)
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
