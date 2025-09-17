//
//  Generator.swift
//  FRTMGpt
//
//  Created by PALOMBA VALENTINO on 21/08/25.
//

import Foundation
import MLX
import MLXLMCommon
import os
import CoreGraphics

// Define the new output item type for the stream
public enum GeneratorOutputItem {
    case chunk(String)
    case toolOutput(
        toolName: String,
        arguments: [String : JSONValue],
        output: String
    ) // Added arguments
}

private class Generator {
    
    private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "FRTMGpt", category: "Generator")
    
    enum Model {
        case container(ModelContainer)
        case context(ModelContext)
    }

    let model: Model
    var messages: [Chat.Message] = []
    let processing: UserInput.Processing
    let generateParameters: GenerateParameters
    var cache: [KVCache]

    init(
        model: Model, instructions: String?, prompt: String, image: UserInput.Image?,
        video: UserInput.Video?, processing: UserInput.Processing,
        generateParameters: GenerateParameters
    ) {
        self.model = model
        self.messages = []
        if let instructions = instructions {
            messages.append(.system(instructions))
        }
        messages.append(
            .user(
                prompt, images: image.flatMap { [$0] } ?? [], videos: video.flatMap { [$0] } ?? []))
        self.processing = processing
        self.generateParameters = generateParameters
        self.cache = []
    }

    init(
        model: Model, instructions: String?, processing: UserInput.Processing,
        generateParameters: GenerateParameters
    ) {
        self.model = model
        if let instructions {
            self.messages = [.system(instructions)]
        } else {
            self.messages = []
        }
        self.processing = processing
        self.generateParameters = generateParameters
        self.cache = []
    }

    func generate() async throws -> String {
        @Sendable func generate(context: ModelContext) async throws -> String {
            // prepare the input -- first the structured messages,
            // next the tokens
            let userInput = UserInput(
                chat: messages,
                processing: processing,
                additionalContext: ["enable_thinking": false]
            )
            let input = try await context.processor.prepare(input: userInput)

            if cache.isEmpty {
                cache = context.model.newCache(parameters: generateParameters)
            }

            // generate the output
            let iterator = try TokenIterator(
                input: input, model: context.model, cache: cache, parameters: generateParameters)
            let result: GenerateResult = MLXLMCommon.generate(
                input: input, context: context, iterator: iterator
            ) { _ in .more }

            Stream.gpu.synchronize()
            let output = result.output
            messages.append(.assistant(output))

            return output
        }

        switch model {
        case .container(let container):
            return try await container.perform { @Sendable context in
                try await generate(context: context)
            }
        case .context(let context):
            return try await generate(context: context)
        }
    }

    func stream() -> AsyncThrowingStream<GeneratorOutputItem, Error> { // Changed return type
        @Sendable func stream(
            context: ModelContext,
            continuation: AsyncThrowingStream<GeneratorOutputItem, Error>.Continuation // Changed continuation type
        ) async {
            do {
                
                MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
                // prepare the input -- first the structured messages,
                // next the tokens
                let userInput = UserInput(
                    chat: messages,
                    processing: processing,
                    additionalContext: ["enable_thinking": false]
                )
                let input = try await context.processor.prepare(input: userInput)

                if cache.isEmpty {
                    cache = context.model.newCache(parameters: generateParameters)
                }
                
                let assistantMessage = Chat.Message(
                    role: .assistant,
                    content: "",
                    images: [],
                    videos: []
                )
                messages.append(assistantMessage)

                // stream the responses back
                for await item in try MLXLMCommon.generate(
                    input: input, cache: cache, parameters: generateParameters, context: context)
                {
                    if let toolCall = item.toolCall {
                        continuation.yield(.chunk("tool call: \(toolCall.function.name)"))
                        
                       
                        
                        // Recursive call to continue generation with new context
                        await stream(context: context, continuation: continuation)
                        return // Crucial to prevent further processing in this stream
                    }
                        
                    if let chunk = item.chunk {
                        // Yield the chunk as a regular item
                        continuation.yield(.chunk(chunk))
                        messages[messages.count - 1].content.append(chunk)
                    }
                }

                Stream.gpu.synchronize()
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return AsyncThrowingStream { @Sendable continuation in
            Task { @Sendable [model, continuation] in
                switch model {
                case .container(let container):
                    await container.perform { @Sendable context in
                        await stream(context: context, continuation: continuation)
                    }
                case .context(let context):
                    await stream(context: context, continuation: continuation)
                }
            }
        }
    }
}

/// Simplified API for loading models and preparing responses to prompts
/// for both LLMs and VLMs.
///
/// For example:
///
/// ```swift
/// let model = try await loadModel(id: "mlx-community/Qwen3-4B-4bit")
/// let session = ChatSession(model)
/// print(try await session.respond(to: "What are two things to see in San Francisco?")
/// print(try await session.respond(to: "How about a great place to eat?")
/// ```
///
/// This manages the chat context (KVCache) and can produce both single string responses or
/// streaming responses.
public class GeneratorSession {

    private let generator: Generator

    /// Initialize the `ChatSession`.
    ///
    /// - Parameters:
    ///   - model: the ``ModelContainer``
    ///   - instructions: optional instructions to the chat session, e.g. describing what type of responses to give
    ///   - generateParameters: parameters that control the generation of output, e.g. token limits and temperature
    ///   - processing: optional media processing instructions
    public init(
        _ model: ModelContainer, instructions: String? = nil,
        generateParameters: GenerateParameters = .init(
            maxTokens: nil,
            maxKVSize: nil,
            kvBits: nil,
            kvGroupSize: 64,
            quantizedKVStart: 0,
            temperature: 0.3,
            topP: 1.0,
            repetitionPenalty: nil,
            repetitionContextSize: 20
        ),
        processing: UserInput.Processing = .init(resize: CGSize(width: 512, height: 512))
    ) {
        self.generator = .init(
            model: .container(model), instructions: instructions, processing: processing,
            generateParameters: generateParameters)
    }

    /// Initialize the `ChatSession`.
    ///
    /// - Parameters:
    ///   - model: the ``ModelContext``
    ///   - instructions: optional instructions to the chat session, e.g. describing what type of responses to give
    ///   - generateParameters: parameters that control the generation of output, e.g. token limits and temperature
    ///   - processing: optional media processing instructions
    public init(
        _ model: ModelContext,
 instructions: String? = nil,
        generateParameters: GenerateParameters = .init(
            maxTokens: nil,
            maxKVSize: nil,
            kvBits: nil,
            kvGroupSize: 64,
            quantizedKVStart: 0,
            temperature: 0.3,
            topP: 1.0,
            repetitionPenalty: nil,
            repetitionContextSize: 20
        ),
        processing: UserInput.Processing = .init(resize: CGSize(width: 512, height: 512))
    ) {
        self.generator = .init(
            model: .context(model), instructions: instructions, processing: processing,
            generateParameters: generateParameters)
    }

    /// Produces a response to a prompt.
    ///
    /// - Parameters:
    ///   - prompt: the prompt
    ///   - image: optional image (for use with VLMs)
    ///   - video: optional video (for use with VLMs)
    /// - Returns: response from the model
    public func respond(
        to prompt: String, image: UserInput.Image? = nil, video: UserInput.Video? = nil
    ) async throws -> String {
        generator.messages.append(
            .user(
                prompt,
                images: image.flatMap { [$0] } ?? [],
                videos: video.flatMap { [$0] } ?? []))
        return try await generator.generate()
    }

    /// Produces a response to a prompt.
    ///
    /// - Parameters:
    ///   - prompt: the prompt
    ///   - image: optional image (for use with VLMs)
    ///   - video: optional video (for use with VLMs)
    /// - Returns: a stream of tokens (as Strings) from the model
    public func streamResponse(
        to prompt: String, image: UserInput.Image? = nil, video: UserInput.Video? = nil
    ) -> AsyncThrowingStream<GeneratorOutputItem, Error> { // Changed return type
        generator.messages.append(
            .user(
                prompt,
                images: image.flatMap { [$0] } ?? [],
                videos: video.flatMap { [$0] } ?? []))
        return generator.stream()
    }
    
    
    public func setPrompt(_ prompt: String) {
        self.generator.messages.removeAll(where: { $0.role == .system })
        self.generator.messages.append(.system(prompt))
    }
}

