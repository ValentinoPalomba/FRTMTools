import SwiftUI
import AppKit

private struct SectionCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.05))
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
    }
}

extension View {
    func sectionCard() -> some View {
        modifier(SectionCard())
    }
}
