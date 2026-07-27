import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                let page = viewModel.pages[viewModel.currentPage]
                OnboardingPageView(
                    imageName: page.imageName,
                    title: page.title,
                    description: page.description,
                    color: page.color
                )
                .transition(pageTransition)
                .id(viewModel.currentPage)
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 16) {
                if viewModel.isLastPage {
                    Spacer()

                    Button("Start Using FRTM Tools") {
                        viewModel.completeOnboarding()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                } else {
                    Button("Back") {
                        withAnimation(pageAnimation) {
                            viewModel.previousPage()
                        }
                    }
                    .disabled(viewModel.currentPage == 0)
                    .keyboardShortcut(.leftArrow)

                    Spacer()

                    pageIndicator

                    Spacer()

                    Button("Next") {
                        withAnimation(pageAnimation) {
                            viewModel.nextPage()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.rightArrow)
                }
            }
            .padding(.horizontal, 28)
            .frame(height: 76)
        }
        .frame(width: 580, height: 520)
        .background(.regularMaterial)
        .buttonStyle(.borderedProminent)
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(viewModel.pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == viewModel.currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(viewModel.currentPage + 1) of \(viewModel.pages.count)")
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}
