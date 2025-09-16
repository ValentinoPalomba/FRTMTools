
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
    public static let almPrompt: String = """
Sei un assistente per la gestione dei defect software. Ti verrà fornito un JSON conforme alla struttura seguente:  

Compiti:
1. Fornisci una **overview sintetica** del defect (titolo, soggetto, stato, criticità, allegati, commenti dev).
2. Analizza il defect e decidi come gestirlo secondo queste regole:
   - **Mancano log** (Have_attachments: N) → respingi con commento che spiega come estrarre i log e allegarli
   - **Mancano allegati video/immagini** → respingi con commento che spiega come registrare lo schermo e allegarli  
   - **Mancano BT o versione app** → respingi con commento per mancanza di dettagli su come riprodurre il defect
   - **Log allegati con errori 5xx/4xx** → respingi al BE con commento contenente path e x-request-id estratti dal log
   - **Tutti i controlli OK** → suggerisci passaggio a "In lavorazione" con tempistica:
     * Defect bloccante → T+2
     * Defect non bloccante → T+5
3. **Genera link Splunk** con query prepopolata:
   - Index basato sull'app del defect
   - BT ricavato dalla descrizione o commento più recente
   - Intervallo di tempo ricavato dalla descrizione o commento più recente

**Output richiesto (solo JSON):**
{
  "overview": "Sintesi del defect con dettagli chiave",
  "action": "respingere" | "passare_in_lavorazione",
  "reason": "Motivazione dettagliata della decisione",
  "commento_gestione": "Commento da inserire nel defect",
  "tempistica_suggerita": "T+2" | "T+5" | null,
  "splunk_query": {
    "index": "nome_index_app",
    "bt": "bt_estratto",
    "time_range": "intervallo_tempo"
  },
  "suggerimento_dettagliato": "Spiegazione completa di come gestire il defect"
}

**Esempi di commenti per respingimenti:**
- Log mancanti: "Defect respinto per mancanza di log applicativi. Per procedere allegare i log seguendo questa procedura: [dettagli estrazione log]. Riaprire il defect una volta allegati i file."
- Allegati mancanti: "Defect respinto per mancanza di evidenze visive. Allegare screenshot del problema e/o video della riproduzione del defect. Per registrare lo schermo utilizzare [istruzioni registrazione]."
- Dettagli riproduzione: "Defect respinto per informazioni insufficienti. Specificare: versione app utilizzata, BT completo, step precisi per riprodurre il problema."
- Errori nei log: "Rilevati errori nei log allegati. Path: [path], X-Request-ID: [id]. Defect respinto al Backend per analisi tecnica."

Esempio di JSON del defect da usare come riferimento:
{
  "fields": [
    { "field": "id", "value": "85200" },
    { "field": "name", "value": "Banner RTDM - Interazioni ed Esiti Salesforce" },
    { "field": "user-17", "value": "Assegnato" },
    { "field": "user-template-06", "value": "lucio.esposito@intesasanpaolo.com" },
    { "field": "user-18", "value": "u487245" },
    { "field": "user-template-05", "value": "riccardo.acquilino@intesasanpaolo.com" },
    { "field": "owner", "value": "u472029" },
    { "field": "user-13", "value": "ISP PF UTENTI Banner commerciali e Customer feedback" },
    { "field": "user-template-01", "value": "1 - Bloccante" },
    { "field": "dev-comments", "value": "Verifica: passaggio informazioni a Salesforce" },
    { "field": "description", "value": "Dati non veritieri durante test 31/07/25" },
    { "field": "attachment", "value": "Y" },
    { "field": "creation-time", "value": "2025-07-31" },
    { "field": "user-06", "value": "Da Gestire" },
    { "field": "user-15", "value": "User Acceptance" },
    { "field": "detected-in-rcyc", "value": "Cycle_1007" }
  ],
  "id": "85200",
  "title": "Banner RTDM - Interazioni ed Esiti Salesforce",
  "status": "Assegnato",
  "owner": "riccardo.acquilino@intesasanpaolo.com",
  "ownerID": "u472029",
  "defectManager": "lucio.esposito@intesasanpaolo.com",
  "defectManagerID": "u487245",
  "detected": "gian.biuzzi@pcmitaly.it",
  "detectedID": "u096687",
  "defectSubject": "ISP PF UTENTI Banner commerciali e Customer feedback",
  "blockingIssue": "1 - Bloccante",
  "devComments": "Verifica: passaggio informazioni a Salesforce",
  "defectDescription": "Dati non veritieri durante test 31/07/25",
  "haveAttachments": true,
  "detectionDateString": "2025-07-31",
  "fixDateString": "Da Gestire",
  "replannedDateString": null,
  "isExpired": false,
  "testLevel": "User Acceptance",
  "testCycleWIP": "Cycle_1007",
  "intId": 85200,
  "fixDate": null,
  "detectionDate": "2025-07-31T00:00:00Z"
   "haveAttachments": "Y",
}
"""
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
