import SwiftUI

struct ChipView: View {
    enum Style { case light, dark }
    let title: String
    let systemImage: String
    let style: Style

    var body: some View {
        let foreground = style == .light ? Color.white : Color.primary
        let background = style == .light ? Color.white.opacity(0.18) : Color.black.opacity(0.08)

        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
            .foregroundStyle(foreground)
    }
}
