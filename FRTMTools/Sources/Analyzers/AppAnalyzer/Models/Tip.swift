import Foundation

struct Tip: Identifiable {
    enum Kind {
        case general
        case duplicateFiles
        case duplicateImages
    }

    let id = UUID()
    let text: String
    let category: TipCategory
    var subTips: [Tip] = []
    var kind: Kind = .general
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
