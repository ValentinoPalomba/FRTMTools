import SwiftUI

enum DSSurfaceLevel: Hashable {
    case background
    case surface
    case elevated

    fileprivate func color(from theme: Theme) -> Color {
        switch self {
        case .background: return theme.palette.background
        case .surface: return theme.palette.surface
        case .elevated: return theme.palette.elevatedSurface
        }
    }
}

private struct DSSurfaceModifier: ViewModifier {
    @Environment(\.theme) private var theme
    var level: DSSurfaceLevel = .surface
    var cornerRadius: CGFloat = DS.Radius.xl
    var border: Bool = true
    var shadow: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(level.color(from: theme))
            )
            .overlay {
                if border {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.palette.border)
                }
            }
            .shadow(
                color: shadow ? theme.palette.shadow.opacity(theme.colorScheme == .dark ? 0.25 : 0.08) : .clear,
                radius: shadow ? 6 : 0,
                x: 0,
                y: shadow ? 3 : 0
            )
    }
}

extension View {
    func dsSurface(
        _ level: DSSurfaceLevel = .surface,
        cornerRadius: CGFloat = DS.Radius.xl,
        border: Bool = true,
        shadow: Bool = false
    ) -> some View {
        modifier(DSSurfaceModifier(level: level, cornerRadius: cornerRadius, border: border, shadow: shadow))
    }
}

