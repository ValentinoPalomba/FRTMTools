
import Foundation
import SourceGraph

extension Declaration.Kind {
    var icon: String {
        switch self {
        case .class:
            return "📦"
        case .struct:
            return "🧱"
        case .enum:
            return "📚"
        case .protocol:
            return "📜"
        case .extension:
            return "🧩"
            case .functionFree, .functionOperator, .functionSubscript, .functionDestructor, .functionConstructor, .functionMethodClass, .functionAccessorInit, .functionAccessorRead, .functionMethodStatic:
            return "🔧"
        case .varClass, .varLocal, .varGlobal, .varStatic, .varInstance, .varParameter:
            return "🔩"
        case .typealias:
            return "🖇️"
        case .associatedtype:
            return "🔗"
        case .genericTypeParam:
            return "🧬"
        case .module:
            return "📁"
            default:
                return ""
        }
    }
}
