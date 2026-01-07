import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.theme) private var theme

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Preset", selection: $themeManager.themeId) {
                    ForEach(ThemeCatalog.all) { preset in
                        Text(preset.displayName).tag(preset.id)
                    }
                }

                Picker("Appearance", selection: $themeManager.appearanceMode) {
                    ForEach(ThemeAppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section {
                Button("Reset Theme") { themeManager.reset() }
            }
        }
        .padding(DS.Spacing.xl)
        .frame(width: 420)
        .background(theme.palette.background)
    }
}
