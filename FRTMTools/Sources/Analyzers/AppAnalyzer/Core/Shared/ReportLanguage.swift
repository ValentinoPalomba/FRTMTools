import Foundation

enum ReportLanguage: String, CaseIterable, Identifiable {
    case english
    case italian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .italian: return "Italiano"
        }
    }

    var summaryTitle: String {
        switch self {
        case .english: return "📋 Summary Report"
        case .italian: return "📋 Report Riassuntivo"
        }
    }

    var pickerLabel: String {
        switch self {
        case .english: return "Language"
        case .italian: return "Lingua"
        }
    }

    var copyButtonTitle: String {
        switch self {
        case .english: return "Copy"
        case .italian: return "Copia"
        }
    }
}
