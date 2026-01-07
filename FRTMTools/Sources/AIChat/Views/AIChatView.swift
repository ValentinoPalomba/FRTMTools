import SwiftUI

struct AIChatView: View {
    @State private var viewModel: AIChatViewModel
    @State private var configurationStore: LocalAIConfigurationStore
    @Environment(\.theme) private var theme

    @State private var inputText = ""
    @State private var showSettings = false
    @FocusState private var isInputFocused: Bool

    private let displayContext: AnalysisContext

    init(context: AnalysisContext) {
        let store = LocalAIConfigurationStore.shared
        _viewModel = State(initialValue: AIChatViewModel(context: context, configurationStore: store))
        _configurationStore = State(initialValue: store)
        self.displayContext = context
    }

    init(
        analysis: any AppAnalysis,
        categories: [CategoryResult],
        tips: [Tip],
        archs: ArchsResult
    ) {
        let context = AnalysisContextBuilder()
            .buildContext(for: analysis, categories: categories, tips: tips, archs: archs)
        self.init(context: context)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversationList
            Divider()
            inputComposer
        }
        .frame(minWidth: 620, minHeight: 540)
        .padding(.bottom)
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("AI Insights")
                        .font(.title3).bold()
                    Text(displayContext.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Label("Model Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }

            if showSettings {
                settingsPanel
            } else {
                Text("Ask questions about this analysis. Responses are generated locally via the configured foundation model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 12)
    }

    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        messageBubble(for: message)
                            .id(message.id)
                    }
                    if viewModel.isSending {
                        ProgressView("Thinking…")
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical)
            }
            .padding(.vertical, 8)
            .dsSurface(.surface, cornerRadius: 16, border: true, shadow: false)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastID = viewModel.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            HStack(spacing: 8) {
                TextField("Ask something about this build…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .disabled(viewModel.isSending)
                Button("Send", systemImage: "paperplane.fill") {
                    sendMessage()
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.white)
                .padding(8)
                .background(
                    Capsule(style: .continuous)
                        .fill(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending ? theme.palette.border.opacity(0.9) : theme.palette.accent)
                )
                .buttonStyle(.plain)
                .disabled(viewModel.isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, 12)
    }

    private func messageBubble(for message: AIChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                bubbleLabel(message.content, tint: theme.palette.accent.opacity(theme.colorScheme == .dark ? 0.22 : 0.15))
                Spacer()
            } else {
                Spacer()
                bubbleLabel(message.content, tint: theme.palette.border.opacity(theme.colorScheme == .dark ? 0.35 : 0.18))
            }
        }
    }

    private func bubbleLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.body)
            .textSelection(.enabled)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(tint)
            )
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            @Bindable var configurationStore = configurationStore
            Text("Local model configuration")
                .font(.headline)

            TextField(
                "Endpoint (Ollama/LM Studio URL)",
                text: Binding(
                    get: { configurationStore.configuration.endpoint.absoluteString },
                    set: { newValue in
                        guard let url = URL(string: newValue), url.scheme != nil else { return }
                        update(\.endpoint, with: url)
                    }
                )
            )

            TextField(
                "Model name",
                text: binding(\.model)
            )

            HStack {
                Stepper(value: binding(\.historyLimit), in: 4...20) {
                    Text("History turns: \(configurationStore.configuration.historyLimit)")
                }
                Stepper(value: binding(\.maxTokens), in: 128...4096, step: 128) {
                    Text("Max tokens: \(configurationStore.configuration.maxTokens)")
                }
            }

            Toggle(isOn: italianLanguageBinding) {
                Text("Risposte in Italiano")
            }
            .toggleStyle(.switch)
            .help("Disable to receive answers in English")

            HStack {
                Slider(value: binding(\.temperature), in: 0...1, step: 0.05)
                Text("Temperature \(configurationStore.configuration.temperature, format: .number.precision(.fractionLength(2)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading) {
                Text("System prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: binding(\.systemPrompt))
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.palette.border)
                    )
            }

            HStack {
                Button("Reset defaults") {
                    configurationStore.reset()
                    viewModel.resetConversation()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(12)
        .dsSurface(.elevated, cornerRadius: 12, border: true, shadow: true)
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Task {
            await viewModel.send(text)
        }
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<LocalAIConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { configurationStore.configuration[keyPath: keyPath] },
            set: { newValue in
                update(keyPath, with: newValue)
            }
        )
    }

    private func update<Value>(
        _ keyPath: WritableKeyPath<LocalAIConfiguration, Value>,
        with newValue: Value
    ) {
        var config = configurationStore.configuration
        config[keyPath: keyPath] = newValue
        configurationStore.configuration = config
    }

    private var italianLanguageBinding: Binding<Bool> {
        Binding(
            get: { configurationStore.configuration.preferredLanguage == .italian },
            set: { useItalian in
                update(\.preferredLanguage, with: useItalian ? .italian : .english)
            }
        )
    }
}
