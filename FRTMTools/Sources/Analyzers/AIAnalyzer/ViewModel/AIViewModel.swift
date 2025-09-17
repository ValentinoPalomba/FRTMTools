
//
//  AIAlmViewModel.swift
//  AppUtils
//
//  Created by PALOMBA VALENTINO on 01/09/25.
//

import Foundation
import SwiftUI
import CoreImage
import MLXLMCommon
import MLXLLM
import Hub
import Tokenizers

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case tool(String)
        
        // Custom Codable implementation
        enum CodingKeys: String, CodingKey {
            case role, toolName
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
                case .user: try container.encode("user", forKey: .role)
                case .assistant: try container.encode("assistant", forKey: .role)
                case .tool(let toolName):
                    try container.encode("tool", forKey: .role)
                    try container.encode(toolName, forKey: .toolName)
            }
        }
    }
    
    let id: UUID
    let role: Role
    var content: String
    var imageData: Data?
    
}

@Observable
@MainActor
class AIViewModel: ObservableObject {
        
    enum ViewState {
        case loading
        case ready
        case error(Error)
    }
    
    private(set) var chatSession: GeneratorSession?
    private(set) var modelContainer: ModelContainer?
    var modelConfiguration: ModelConfiguration = LLMRegistry.llama3_2_1B_4bit
    private(set) var viewState: ViewState = .loading
    
    // MARK: - Published state for UI
    var messages: [ChatMessage] = []
    
    var lastMessage: ChatMessage? {
        messages.last
    }
    
    func loadModel(progressHandler: @Sendable @escaping (Progress) -> Void) async {
        viewState = .loading
        do {
            let model = try await MLXLMCommon.loadModelContainer(
                configuration: modelConfiguration) { progress in
                    progressHandler(progress)
                }
            self.modelContainer = model
            self.chatSession = GeneratorSession(model)
            viewState = .ready
        } catch {
            viewState = .error(error)
        }
    }
    
    @MainActor
    func respondToUserInput(_ input: String, image: Data? = nil) async {
        guard let chatSession else {
            return
        }
        
        let userMessage = ChatMessage(id: UUID(), role: .user, content: input)
        messages.append(userMessage)
        
        var assistantMessageId = UUID()
        var assistantMessage = ChatMessage(id: assistantMessageId, role: .assistant, content: "")
        messages.append(assistantMessage)
        let stream = chatSession.streamResponse(to: input)
        
        do {
            for try await item in stream {
                switch item {
                    case .chunk(let chunk):
                        if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            messages[index].content.append(chunk)
                        }
                    case .toolOutput(let toolName, let arguments, let output):
                        let formattedContent = """
                    Command: \(arguments)
                    ---
                    Output:
                    \(output)
                    """
                        
                        let toolOutputMessage = ChatMessage(id: UUID(), role: .tool(toolName), content: formattedContent)
                        messages.append(toolOutputMessage)
                        
                        assistantMessageId = UUID()
                        assistantMessage = ChatMessage(id: assistantMessageId, role: .assistant, content: "")
                        messages.append(assistantMessage)
                }
            }
        } catch {
            print("Errore during streaming: \(error)")
            if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                messages[index].content = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    
    func setPrompt(_ prompt: String) {
        chatSession?.setPrompt(prompt)
    }
    
}


enum ConstantsPrompt {
    public static let ipaAnalysisPrompt: String = """
    You are an assistant specialized in IPA file analysis. 
    You will receive a technical summary including categories, sizes, and main files.

    Your task is to produce TWO SECTIONS:

    ### 1. Key Information (bullet points)
    - IPA file name and total size.
    - Size distribution by category (with percentages).
    - Largest files per category (up to 3 per category).
    - Highlight any anomalies (e.g., unusually large categories, unstripped binaries, oversized assets, etc.).

    ### 2. Insightful Summary
    - Provide a brief overview of the app's "health".
    - Highlight strengths and weaknesses.
    - Give practical optimization advice (e.g., reduce image size, remove debug symbols, modularize heavy frameworks).
    - Use a professional yet energetic style, giving immediate actionable insights.

    Always respond in English.
    """

    public static let ipaComparisonPrompt: String = """
    You are an assistant specialized in comparing two IPA files.
    You will receive a detailed comparison summary including overall size changes, category-wise differences, and lists of added, removed, and modified files/frameworks.

    Your task is to produce TWO SECTIONS:

    ### 1. Key Differences (bullet points)
    - Summarize the main differences in total size and category distribution between the two IPAs.
    - Highlight significant changes in file counts or sizes for specific categories.
    - List any newly added or removed frameworks, and their impact on size.

    ### 2. Optimization and Actionable Insights
    - Provide practical optimization advice based on the observed changes (e.g., if a category significantly increased, suggest ways to reduce its size).
    - Suggest actions to take regarding newly added or removed components.
    - Use a professional yet energetic style, giving immediate actionable insights.

    Always respond in English.
    """

}
