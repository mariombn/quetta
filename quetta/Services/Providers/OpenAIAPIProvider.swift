//
//  OpenAIAPIProvider.swift
//  quetta
//
//  OpenAI Chat Completions provider (API key). Used for summary and/or live
//  translation. The key is passed in from the Keychain and never logged.
//

import Foundation

nonisolated final class OpenAIAPIProvider: TranslationProvider, SummaryProvider, @unchecked Sendable {

    let id: UUID
    let displayName: String
    private let apiKey: String
    private let model: String
    private let baseURL: URL

    init(
        id: UUID,
        displayName: String,
        apiKey: String,
        model: String = "gpt-4o-mini",
        baseURL: URL = URL(string: "https://api.openai.com/v1")!
    ) {
        self.id = id
        self.displayName = displayName
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsLiveTranslation: true,
            supportsStreamingTranslation: true,
            supportsSummary: true,
            supportedLanguages: [.portuguese, .english, .spanish],
            recommendedCharacterLimit: 12_000
        )
    }

    // MARK: - Validation

    func validateConfiguration() async throws {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured }

        let system = Self.summarySystemPrompt(language: request.outputLanguage)
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
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                    guard !self.apiKey.isEmpty else { throw ProviderError.notConfigured }

                    let system = Self.translationSystemPrompt(
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
                    urlRequest.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
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

    static func summarySystemPrompt(language: LanguageCode) -> String {
        let langName: String
        switch language {
        case .portuguese: langName = "português"
        case .english: langName = "English"
        case .spanish: langName = "español"
        }
        return """
        You are an assistant that writes structured meeting summaries in \(langName).
        Return ONLY valid Markdown with EXACTLY these sections, in this order:

        # Resumo da reunião

        ## Resumo executivo

        ## Pauta discutida

        ## Decisões

        ## Pendências e responsáveis

        ## Perguntas em aberto

        ## Próximos passos

        Rules:
        - Do NOT invent owners, decisions, or dates. When information is not explicit, use language of uncertainty or omit the item.
        - Base everything strictly on the provided transcript.
        - Write the content in \(langName), but keep the section headers exactly as given above.
        """
    }

    static func translationSystemPrompt(from source: LanguageCode, to target: LanguageCode, context: [String]) -> String {
        var prompt = """
        You are a professional simultaneous translator. Translate the user's text from \
        \(source.rawValue) to \(target.rawValue). Output ONLY the translation, with no \
        quotes, notes, or explanations. Preserve meaning and tone.
        """
        if !context.isEmpty {
            prompt += "\n\nRecent context (already translated, for consistency):\n" + context.joined(separator: "\n")
        }
        return prompt
    }
}

// MARK: - Wire types

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
