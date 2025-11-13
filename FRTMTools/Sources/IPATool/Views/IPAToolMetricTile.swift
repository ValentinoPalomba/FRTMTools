import SwiftUI

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let usesLightText: Bool

    var body: some View {
        let primary = usesLightText ? Color.white : Color.primary
        let secondary = usesLightText ? Color.white.opacity(0.85) : Color.secondary
        let iconBackground = usesLightText ? Color.white.opacity(0.18) : Color.black.opacity(0.08)

        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconBackground)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(primary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
        }
    }
}
