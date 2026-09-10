//
//  OllamaProvider.swift
//  quetta
//
//  Ollama local provider. Uses the OpenAI-compatible /v1/chat/completions
//  endpoint running on a local Ollama server. No API key required.
//

import Foundation

nonisolated final class OllamaProvider: TranslationProvider, SummaryProvider, @unchecked Sendable {

    let id: UUID
    let displayName: String
    private let model: String
    private let baseURL: URL

    static let defaultBaseURL = URL(string: "http://localhost:11434/v1")!

    init(
        id: UUID,
        displayName: String,
        model: String = "llama3.2",
        baseURL: URL = URL(string: "http://localhost:11434/v1")!
    ) {
        self.id = id
        self.displayName = displayName
        self.model = model
        self.baseURL = baseURL
    }

    var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsLiveTranslation: true,
            supportsStreamingTranslation: true,
            supportsSummary: true,
            supportedLanguages: [.portuguese, .english, .spanish],
            recommendedCharacterLimit: 8_000
        )
    }

    // MARK: - Validation

    func validateConfiguration() async throws {
        guard !model.isEmpty else { throw ProviderError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try Self.checkStatus(response)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network
        }
    }

    // MARK: - Summary

    func generateSummary(_ request: SummaryRequest) async throws -> MeetingSummaryResult {
        guard !model.isEmpty else { throw ProviderError.notConfigured }

        let system = OpenAIAPIProvider.summarySystemPrompt(language: request.outputLanguage)
        var user = "Título: \(request.meetingTitle)\n\nTranscrição:\n\(request.transcript)"
        if let translation = request.translation, !translation.isEmpty {
            user += "\n\nTradução (referência):\n\(translation)"
        }

        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user),
            ],
            stream: false,
            temperature: 0.2
        )

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            try Self.checkStatus(response)
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message?.content else {
                throw ProviderError.invalidResponse
            }
            return MeetingSummaryResult(markdown: content, modelName: model)
        } catch let error as ProviderError {
            throw error
        } catch is DecodingError {
            throw ProviderError.invalidResponse
        } catch {
            throw ProviderError.network
        }
    }

    // MARK: - Translation

    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !self.model.isEmpty else { throw ProviderError.notConfigured }

                    let system = OpenAIAPIProvider.translationSystemPrompt(
                        from: request.sourceLanguage,
                        to: request.targetLanguage,
                        context: request.context
                    )
                    let body = ChatRequest(
                        model: self.model,
                        messages: [
                            .init(role: "system", content: system),
                            .init(role: "user", content: request.text),
                        ],
                        stream: true,
                        temperature: 0.2
                    )

                    var urlRequest = URLRequest(url: self.baseURL.appendingPathComponent("chat/completions"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    try Self.checkStatus(response)

                    var accumulated = ""
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data),
                           let delta = chunk.choices.first?.delta?.content, !delta.isEmpty {
                            accumulated += delta
                            continuation.yield(.partial(accumulated))
                        }
                    }
                    continuation.yield(.completed(accumulated))
                    continuation.finish()
                } catch let error as ProviderError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: ProviderError.cancelled)
                } catch {
                    continuation.finish(throwing: ProviderError.network)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ProviderError.network }
        switch http.statusCode {
        case 200...299: return
        case 401, 403: throw ProviderError.authentication
        case 429: throw ProviderError.rateLimited
        default: throw ProviderError.message("HTTP \(http.statusCode)")
        }
    }
}

// MARK: - Wire types (OpenAI-compatible)

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message?
    }
    let choices: [Choice]
}

private struct ChatStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta?
    }
    let choices: [Choice]
}
