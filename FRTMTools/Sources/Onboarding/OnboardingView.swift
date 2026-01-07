import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack {
            // Page Content
            ZStack {
                let page = viewModel.pages[viewModel.currentPage]
                OnboardingPageView(
                    imageName: page.imageName,
                    title: page.title,
                    description: page.description,
                    color: page.color
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .id(viewModel.currentPage)
            }
            .frame(maxHeight: .infinity)

            // Navigation
            ZStack {
                HStack {
                    // Previous Button
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            viewModel.previousPage()
                        }
                    }
                    .disabled(viewModel.currentPage == 0)
                    .keyboardShortcut(.leftArrow)

                    Spacer()

                    // Next Button
                    Button("Next") {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            viewModel.nextPage()
                        }
                    }
                    .keyboardShortcut(.rightArrow)
                }
                .padding(30)
                .opacity(viewModel.isLastPage ? 0 : 1)

                Button("Start now") {
                    viewModel.completeOnboarding(presentationBinding: $isPresented)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(30)
                .opacity(viewModel.isLastPage ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.4), value: viewModel.isLastPage)
        }
        .frame(width: 550, height: 500)
        .background(.regularMaterial)
        .buttonStyle(.borderedProminent)
    }
}
