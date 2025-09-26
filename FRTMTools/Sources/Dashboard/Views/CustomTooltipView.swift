
import SwiftUI

// This is the view for the tooltip popup itself.
// It's styled to look like a native macOS tooltip.
struct CustomTooltipView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.title3)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
