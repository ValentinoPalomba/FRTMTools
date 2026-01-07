import SwiftUI
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    var currentPage = 0

    let pages: [OnboardingPage] = [
        .init(
            imageName: "doc.text.magnifyingglass",
            title: "Analyze Your Apps",
            description: "Dissect .ipa files to see what they contain, analyze the space they take up, and get tips to optimize their size.",
            color: .blue
        ),
        .init(
            imageName: "cross.circle",
            title: "Find Unused Code",
            description: "Scan your project to identify classes, functions, and assets that are no longer in use and can be removed.",
            color: .orange
        ),
        .init(
            imageName: "shield.lefthalf.filled",
            title: "Discover Vulnerabilities",
            description: "Run a security scan to find potential weak points and unsafe practices within your application.",
            color: .red
        )
    ]

    var isLastPage: Bool {
        currentPage == pages.count - 1
    }

    func nextPage() {
        guard !isLastPage else { return }
        currentPage += 1
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
    }

    func completeOnboarding(presentationBinding: Binding<Bool>) {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        presentationBinding.wrappedValue = false
    }
}
