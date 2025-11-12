import Foundation

struct Tip: Identifiable {
    let id = UUID()
    let text: String
    let category: TipCategory
    var subTips: [Tip] = []
}

enum TipCategory: String {
    case optimization = "Optimization"
    case warning = "Warning"
    case info = "Info"
    case size = "Size Optimization"
    case performance = "Performance"
    case security = "Security"
    case compatibility = "Compatibility"
}
