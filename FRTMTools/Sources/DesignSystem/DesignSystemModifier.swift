import SwiftUI

private struct DesignSystemModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject var themeManager: ThemeManager

    func body(content: Content) -> some View {
        let theme = themeManager.theme(systemColorScheme: systemColorScheme)

        content
            .environment(\.theme, theme)
            .tint(theme.palette.accent)
            .preferredColorScheme(themeManager.appearanceMode.preferredColorScheme)
    }
}

extension View {
    func designSystem(_ themeManager: ThemeManager) -> some View {
        modifier(DesignSystemModifier(themeManager: themeManager))
    }
}

