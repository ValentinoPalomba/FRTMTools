import Foundation
import Observation
@MainActor
protocol InstalledSizeAnalyzing: AnyObject, Observable {
    associatedtype Analysis: AppAnalysis
    associatedtype SizeAlert: SizeAlertProtocol

    var isSizeLoading: Bool { get }
    var sizeAnalysisProgress: String { get }
    var sizeAnalysisAlert: SizeAlert? { get set }

    func analyzeSize(for analysisID: UUID)
}

protocol SizeAlertProtocol: Identifiable {
    var title: String { get }
    var message: String { get }
}
