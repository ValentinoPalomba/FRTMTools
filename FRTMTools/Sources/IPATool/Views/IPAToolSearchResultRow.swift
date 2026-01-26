import SwiftUI
import AppKit

struct SearchResultRow: View {
    let app: IPAToolStoreApp
    let isSelected: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ArtworkImageView(url: makeArtworkURL(from: app.artworkUrl100), size: 44, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.trackName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(app.bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if let price = app.formattedPrice ?? app.priceString {
                Text(price)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? theme.palette.accent.opacity(theme.colorScheme == .dark ? 0.18 : 0.12) : theme.palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? theme.palette.accent.opacity(0.55) : theme.palette.border)
        )
    }
}
