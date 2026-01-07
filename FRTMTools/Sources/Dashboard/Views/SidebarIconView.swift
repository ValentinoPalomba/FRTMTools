
import SwiftUI

struct SidebarIconView: View {
    let imageName: String
    let color: Color
    let isSelected: Bool
    let isHovering: Bool
    
    var body: some View {
        DSIconBadge(
            systemImage: imageName,
            tint: color,
            isEmphasized: isHovering || isSelected
        )
    }
}
