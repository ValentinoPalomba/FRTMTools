import SwiftUI

struct BadWordScannerHistoryRow: View {
    let record: BadWordScanRecord
    let isSelected: Bool
    let isScanning: Bool
    let select: () -> Void
    let reveal: () -> Void
    let delete: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.fileName)
                        .font(.subheadline.bold())
                    Text(record.scannedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(record.result.matches.count)", systemImage: "exclamationmark.bubble")
                    .foregroundStyle(record.result.matches.isEmpty ? Color.secondary : Color.red)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? theme.palette.accent.opacity(theme.colorScheme == .dark ? 0.22 : 0.16) : theme.palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? theme.palette.accent.opacity(0.55) : theme.palette.border)
            )
        }
        .buttonStyle(.plain)
        .disabled(isScanning)
        .contextMenu {
            Button("Open in Finder", action: reveal)
            Button("Delete", role: .destructive, action: delete)
        }
    }
}
