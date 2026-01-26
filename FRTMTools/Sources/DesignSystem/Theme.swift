import SwiftUI

struct ThemeDescriptor: Identifiable, Equatable {
    let id: String
    let displayName: String
    let light: ThemePalette
    let dark: ThemePalette

    func palette(for colorScheme: ColorScheme) -> ThemePalette {
        switch colorScheme {
        case .dark: return dark
        default: return light
        }
    }
}

enum ThemeCatalog {
    static let all: [ThemeDescriptor] = [
        ThemeDescriptor(
            id: "studio",
            displayName: "Studio",
            light: ThemePalette(
                accent: .hex(0x0A84FF),
                background: .hex(0xF5F6F8),
                surface: .hex(0xFFFFFF),
                elevatedSurface: .hex(0xFFFFFF),
                textPrimary: .hex(0x0B0B0C),
                textSecondary: .hex(0x5C5C64),
                border: .hex(0x1C1C1E, alpha: 0.10),
                shadow: .black,
                success: .hex(0x2AC769),
                warning: .hex(0xFF9F0A),
                danger: .hex(0xFF3B30)
            ),
            dark: ThemePalette(
                accent: .hex(0x0A84FF),
                background: .hex(0x0F1115),
                surface: .hex(0x161A22),
                elevatedSurface: .hex(0x1C2230),
                textPrimary: .hex(0xF2F3F5),
                textSecondary: .hex(0xA8ABB2),
                border: .hex(0xFFFFFF, alpha: 0.10),
                shadow: .black,
                success: .hex(0x2AC769),
                warning: .hex(0xFF9F0A),
                danger: .hex(0xFF453A)
            )
        ),
        ThemeDescriptor(
            id: "nord",
            displayName: "Nord",
            light: ThemePalette(
                accent: .hex(0x5E81AC),
                background: .hex(0xECEFF4),
                surface: .hex(0xFFFFFF),
                elevatedSurface: .hex(0xF8FAFD),
                textPrimary: .hex(0x2E3440),
                textSecondary: .hex(0x4C566A),
                border: .hex(0x2E3440, alpha: 0.10),
                shadow: .black,
                success: .hex(0x2EAC68),
                warning: .hex(0xD08770),
                danger: .hex(0xBF616A)
            ),
            dark: ThemePalette(
                accent: .hex(0x88C0D0),
                background: .hex(0x2E3440),
                surface: .hex(0x3B4252),
                elevatedSurface: .hex(0x434C5E),
                textPrimary: .hex(0xECEFF4),
                textSecondary: .hex(0xD8DEE9),
                border: .hex(0xECEFF4, alpha: 0.10),
                shadow: .black,
                success: .hex(0xA3BE8C),
                warning: .hex(0xEBCB8B),
                danger: .hex(0xBF616A)
            )
        ),
        ThemeDescriptor(
            id: "dracula",
            displayName: "Dracula",
            light: ThemePalette(
                accent: .hex(0xBD93F9),
                background: .hex(0xF6F5FB),
                surface: .hex(0xFFFFFF),
                elevatedSurface: .hex(0xFFFFFF),
                textPrimary: .hex(0x24222B),
                textSecondary: .hex(0x5A556A),
                border: .hex(0x24222B, alpha: 0.10),
                shadow: .black,
                success: .hex(0x50FA7B),
                warning: .hex(0xFFB86C),
                danger: .hex(0xFF5555)
            ),
            dark: ThemePalette(
                accent: .hex(0xBD93F9),
                background: .hex(0x16141D),
                surface: .hex(0x282A36),
                elevatedSurface: .hex(0x303341),
                textPrimary: .hex(0xF8F8F2),
                textSecondary: .hex(0xBDBDB7),
                border: .hex(0xF8F8F2, alpha: 0.10),
                shadow: .black,
                success: .hex(0x50FA7B),
                warning: .hex(0xFFB86C),
                danger: .hex(0xFF5555)
            )
        ),
        ThemeDescriptor(
            id: "solarized",
            displayName: "Solarized",
            light: ThemePalette(
                accent: .hex(0x268BD2),
                background: .hex(0xFDF6E3),
                surface: .hex(0xFFFCF2),
                elevatedSurface: .hex(0xFFFFFF),
                textPrimary: .hex(0x073642),
                textSecondary: .hex(0x586E75),
                border: .hex(0x073642, alpha: 0.12),
                shadow: .black,
                success: .hex(0x859900),
                warning: .hex(0xB58900),
                danger: .hex(0xDC322F)
            ),
            dark: ThemePalette(
                accent: .hex(0x2AA198),
                background: .hex(0x002B36),
                surface: .hex(0x073642),
                elevatedSurface: .hex(0x0B4755),
                textPrimary: .hex(0xEEE8D5),
                textSecondary: .hex(0x93A1A1),
                border: .hex(0xEEE8D5, alpha: 0.12),
                shadow: .black,
                success: .hex(0x859900),
                warning: .hex(0xB58900),
                danger: .hex(0xDC322F)
            )
        ),
    ]

    static var `default`: ThemeDescriptor { all.first(where: { $0.id == "studio" }) ?? all[0] }

    static func descriptor(for id: String) -> ThemeDescriptor? {
        all.first(where: { $0.id == id })
    }
}

enum ThemeAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct ThemePalette: Equatable {
    let accent: Color
    let background: Color
    let surface: Color
    let elevatedSurface: Color
    let textPrimary: Color
    let textSecondary: Color
    let border: Color
    let shadow: Color
    let success: Color
    let warning: Color
    let danger: Color
}

struct Theme: Equatable {
    let descriptor: ThemeDescriptor
    let mode: ThemeAppearanceMode
    let colorScheme: ColorScheme
    let palette: ThemePalette

    static func fallback(colorScheme: ColorScheme = .light) -> Theme {
        let mode: ThemeAppearanceMode = .system
        let descriptor = ThemeCatalog.default
        return Theme(descriptor: descriptor, mode: mode, colorScheme: colorScheme, palette: descriptor.palette(for: colorScheme))
    }
}

extension Color {
    fileprivate static func hex(_ hex: UInt32, alpha: Double = 1) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
