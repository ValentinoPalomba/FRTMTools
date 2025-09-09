
//
//  AIMagicView.swift
//  AppUtils
//
//  Created by PALOMBA VALENTINO on 01/09/25.
//

import Foundation
import SwiftUI

struct AIMagicView: View {
    var input: String
    var systemPrompt: String
    @StateObject var viewModel: AIViewModel = .init()
    @State private var observableProgress: ObservableProgress?
    
    var body: some View {
        VStack(spacing: 16) {
            
            // MARK: Header
            VStack(alignment: .leading, spacing: 8) {
                Text("📝 AI Analysis Summary")
                    .font(.title2)
                    .bold()
                
                Text("Input: \(input)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .padding(.horizontal)
            
            Divider()
            
            // MARK: Output
            ZStack {
                switch viewModel.viewState {
                case .loading:
                    VStack(spacing: 12) {
                        if let observableProgress {
                            FoundationProgressView(observableProgress: observableProgress)
                                .progressViewStyle(.linear)
                                .frame(height: 8)
                                .padding(.horizontal)
                        } else {
                            ProgressView("Generating summary...")
                                .progressViewStyle(.circular)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                case .ready:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let lastMessage = viewModel.messages.last(where: { $0.role == .assistant }) {
                                renderFormattedText(lastMessage.content)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                                    )
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    
                case .error(let error):
                    VStack(spacing: 12) {
                        Text("❌ Error")
                            .font(.title2)
                            .bold()
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
        .task {
            await viewModel.loadModel { progress in
                self.observableProgress = .init(progress: progress)
            }
            viewModel.setPrompt(systemPrompt)
            await viewModel.respondToUserInput(input)
        }
    }
    
    // MARK: - Simple Markdown parser (bold, lists, arrows)
    func renderFormattedText(_ text: String) -> Text {
        // Dividiamo il testo su "**" per gestire il bold
        let boldParts = text.components(separatedBy: "**")
        
        let combinedText = boldParts.enumerated().map { index, part -> Text in
            var t = Text(part)
            
            // Applica bold agli elementi dispari
            if index % 2 == 1 {
                t = t.bold()
            }
            
            // Evidenzia bullet points
            if part.starts(with: "- ") {
                t = Text("• \(part.dropFirst(2))") // trasforma "- " in "• "
                    .foregroundColor(.accentColor)
            }
            
            // Evidenzia simboli come ➕ o ➖
            if part.contains("➕") {
                t = t.foregroundColor(.green)
            } else if part.contains("➖") {
                t = t.foregroundColor(.red)
            }
            
            return t
        }
        .reduce(Text(""), +) // Combina tutti i Text in uno solo
        
        return combinedText
    }

}

#Preview {
    AIMagicView(input: "Tell me a joke", systemPrompt: ConstantsPrompt.ipaAnalysisPrompt)
}


// Wrapper ObservableObject per Progress
class ObservableProgress: ObservableObject {
    @Published var fractionCompleted: Double = 0.0
    
    private var progress: Progress
    
    private var observation: NSKeyValueObservation?
    
    init(progress: Progress) {
        self.progress = progress
        self.fractionCompleted = progress.fractionCompleted
        
        // Osserva la proprietà fractionCompleted di Progress
        observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] prog, change in
            DispatchQueue.main.async {
                self?.fractionCompleted = prog.fractionCompleted
                print("progress \(prog)")
            }
        }
    }
    
    deinit {
        observation?.invalidate()
    }
}

// SwiftUI ProgressView
struct FoundationProgressView: View {
    @ObservedObject var observableProgress: ObservableProgress
    
    var body: some View {
        VStack {
            ProgressView(value: observableProgress.fractionCompleted)
                .progressViewStyle(LinearProgressViewStyle())
                .padding()
            Text("\(Int(observableProgress.fractionCompleted * 100))%")
                .font(.caption)
        }
    }
}
