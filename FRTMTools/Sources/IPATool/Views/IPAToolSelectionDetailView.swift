import SwiftUI
import AppKit

struct IPAToolSelectionDetailView: View {
    @ObservedObject var viewModel: IPAToolViewModel

    var body: some View {
        Group {
            if let selected = viewModel.selectedApp {
                ScrollView {
                    IPAToolDetailView(viewModel: viewModel, selectedApp: selected)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bag.badge.plus")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    Text("Select an app from the list to inspect versions.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
