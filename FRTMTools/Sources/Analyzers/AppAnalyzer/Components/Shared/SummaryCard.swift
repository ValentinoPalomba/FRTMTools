
import SwiftUI

// SummaryCard
struct SummaryCard: View {
    let title: String
    let value: String
    var subtitle: String?
    var icon: String?
    var color: Color?
    var backgroundColor: Color?
    @Environment(\.theme) private var theme

    var body: some View {
        let fill = backgroundColor ?? theme.palette.surface

        VStack(alignment: .leading, spacing: 8) {
            if let icon = icon, let color = color {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.title3)

                    Spacer()
                }
            }
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2)
                .bold()
                .foregroundStyle(.primary)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(DS.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.palette.border)
        )
        .shadow(color: theme.palette.shadow.opacity(theme.colorScheme == .dark ? 0.25 : 0.08), radius: 5, x: 0, y: 2)
    }
}
