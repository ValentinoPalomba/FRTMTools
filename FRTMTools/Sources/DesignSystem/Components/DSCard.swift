import SwiftUI

private struct DSCardModifier: ViewModifier {
    var level: DSSurfaceLevel = .surface
    var cornerRadius: CGFloat = DS.Radius.xl
    var padding: CGFloat = DS.Spacing.xl
    var shadow: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(level, cornerRadius: cornerRadius, border: true, shadow: shadow)
    }
}

extension View {
    func dsCard(
        _ level: DSSurfaceLevel = .surface,
        cornerRadius: CGFloat = DS.Radius.xl,
        padding: CGFloat = DS.Spacing.xl,
        shadow: Bool = true
    ) -> some View {
        modifier(DSCardModifier(level: level, cornerRadius: cornerRadius, padding: padding, shadow: shadow))
    }
}

