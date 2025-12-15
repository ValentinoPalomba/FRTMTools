import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct ComparisonReportView: View {
    let viewModel: ComparisonReportViewModel
    @Binding var language: ReportLanguage
    @State private var showCopyConfirmation = false

    var body: some View {
        let reportItems = viewModel.reportItems(for: language)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.summaryTitle)
                    .font(.title3).bold()
                Spacer()
                Button {
                    copyReport(items: reportItems)
                    withAnimation {
                        showCopyConfirmation = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showCopyConfirmation = false
                        }
                    }
                } label: {
                    Label(language.copyButtonTitle, systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help(language.copyButtonTitle)
                if showCopyConfirmation {
                    Text(language == .english ? "Copied!" : "Copiato!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                Picker(language.pickerLabel, selection: $language) {
                    ForEach(ReportLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            .padding(.horizontal)

            ReportContentList(items: reportItems)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .padding(.horizontal)
        }
    }

    private func copyReport(items: [String]) {
        let bulletItems = items.map { "• \($0)" }
        let text = bulletItems.joined(separator: "\n")
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

private struct ReportContentList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(item)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
