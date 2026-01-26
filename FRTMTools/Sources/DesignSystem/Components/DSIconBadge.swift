import SwiftUI

struct DSIconBadge: View {
    let systemImage: String
    let tint: Color
    let isEmphasized: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(
                isEmphasized
                ? LinearGradient(
                    colors: [tint.opacity(0.85), tint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : .init(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                Image(systemName: systemImage)
                    .font(.callout.bold())
                    .foregroundStyle(isEmphasized ? .white : .secondary)
            }
            .frame(width: 28, height: 28)
            .shadow(color: isEmphasized ? tint.opacity(0.25) : .clear, radius: 4, x: 0, y: 4)
            .padding(.vertical, DS.Spacing.xs)
    }
}

