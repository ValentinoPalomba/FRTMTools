import SwiftUI
import AppKit

private struct SectionCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .dsCard(.surface, cornerRadius: DS.Radius.xl, padding: DS.Spacing.xl, shadow: true)
    }
}

extension View {
    func sectionCard() -> some View {
        modifier(SectionCard())
    }
}
