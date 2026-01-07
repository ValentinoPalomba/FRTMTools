import SwiftUI

struct OnboardingPageView: View {
    let imageName: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.8), color]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 120, height: 120)
                    .shadow(color: color.opacity(0.3), radius: 10, y: 10)

                Image(systemName: imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(.largeTitle)
                    .bold()
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .lineSpacing(5)
            }
        }
        .padding(40)
    }
}
