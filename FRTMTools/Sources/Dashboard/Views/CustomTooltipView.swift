
import SwiftUI

// This is the view for the tooltip popup itself.
// It's styled to look like a native macOS tooltip.
struct CustomTooltipView: View {
    let text: String
    @Environment(\.theme) private var theme
    
    var body: some View {
        Text(text)
            .font(.title3)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.palette.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.palette.border, lineWidth: 0.5)
            )
            .shadow(color: theme.palette.shadow.opacity(theme.colorScheme == .dark ? 0.35 : 0.12), radius: 5, x: 0, y: 2)
    }
}
