import SwiftUI
import Observation

@MainActor
@Observable
final class ThemeManager {
    private enum Keys {
        static let preset = "designSystem.themePreset"
        static let mode = "designSystem.appearanceMode"
    }

    var themeId: String {
        didSet { persist() }
    }

    var appearanceMode: ThemeAppearanceMode {
        didSet { persist() }
    }

    init(userDefaults: UserDefaults = .standard) {
        let presetRaw = userDefaults.string(forKey: Keys.preset)
        let modeRaw = userDefaults.string(forKey: Keys.mode)

        self.themeId = ThemeCatalog.descriptor(for: presetRaw ?? "")?.id ?? ThemeCatalog.default.id
        self.appearanceMode = ThemeAppearanceMode(rawValue: modeRaw ?? "") ?? .system
    }

    func theme(systemColorScheme: ColorScheme) -> Theme {
        let effectiveScheme = appearanceMode.preferredColorScheme ?? systemColorScheme
        let descriptor = ThemeCatalog.descriptor(for: themeId) ?? ThemeCatalog.default
        return Theme(
            descriptor: descriptor,
            mode: appearanceMode,
            colorScheme: effectiveScheme,
            palette: descriptor.palette(for: effectiveScheme)
        )
    }

    func reset() {
        themeId = ThemeCatalog.default.id
        appearanceMode = .system
    }

    func cyclePreset(forward: Bool) {
        let all = ThemeCatalog.all
        guard let currentIndex = all.firstIndex(where: { $0.id == themeId }) else {
            themeId = ThemeCatalog.default.id
            return
        }
        let count = all.count
        let next = forward ? (currentIndex + 1) % count : (currentIndex - 1 + count) % count
        themeId = all[next].id
    }

    private func persist(userDefaults: UserDefaults = .standard) {
        userDefaults.set(themeId, forKey: Keys.preset)
        userDefaults.set(appearanceMode.rawValue, forKey: Keys.mode)
    }
}
