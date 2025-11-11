import SwiftUI

func makeArtworkURL(from string: String?) -> URL? {
    guard let s = string, let url = URL(string: s) else { return nil }
    return url
}

struct ArtworkImageView: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.1))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "app")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.secondary.opacity(0.6))
            )
    }
}
