import Foundation

struct Tip: Identifiable {
    let id = UUID()
    let text: String
    let category: TipCategory
}

enum TipCategory: String {
    case optimization = "Optimization"
    case warning = "Warning"
    case info = "Info"
}
