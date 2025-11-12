
import SwiftUI

// SummaryCard
struct SummaryCard: View {
    let title: String
    let value: String
    var subtitle: String?
    var icon: String?
    var color: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let icon = icon, let color = color {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.title3)

                    Spacer()
                }
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}
