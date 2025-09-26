
import SwiftUI

struct SidebarIconView: View {
    let imageName: String
    let color: Color
    let isSelected: Bool
    let isHovering: Bool
    
    private var isColored: Bool {
        isHovering || isSelected
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isColored ? AnyShapeStyle(LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.8), color]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )) : AnyShapeStyle(Color.clear)
                )
            
            Image(systemName: imageName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isColored ? .white : .secondary)
        }
        .frame(width: 28, height: 28)
        .padding(.vertical, 4)
        .shadow(color: isColored ? color.opacity(0.3) : .clear, radius: 4, y: 4)
    }
}
