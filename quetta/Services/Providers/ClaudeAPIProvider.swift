//
//  ClaudeAPIProvider.swift
//  quetta
//
//  Anthropic Claude Messages API provider (API key). Supports streaming
//  translation and non-streaming summary. Key is read from the Keychain.
//

import Foundation

nonisolated final class ClaudeAPIProvider: TranslationProvider, SummaryProvider, @unchecked Sendable {

    let id: UUID
    let displayName: String
    private let apiKey: String
    private let model: String
    private let baseURL: URL

    static let defaultBaseURL = URL(string: "https://api.anthropic.com/v1")!
    private static let anthropicVersion = "2023-06-01"

    init(
        id: UUID,
        displayName: String,
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!
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
        addHeaders(to: &request)
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

        let system = OpenAIAPIProvider.summarySystemPrompt(language: request.outputLanguage)
        var user = "Título: \(request.meetingTitle)\n\nTranscrição:\n\(request.transcript)"
        if let translation = request.translation, !translation.isEmpty {
            user += "\n\nTradução (referência):\n\(translation)"
        }

        let body = MessagesRequest(
            model: model,
            maxTokens: 4096,
            system: system,
            messages: [.init(role: "user", content: user)],
            stream: false
        )

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("messages"))
        urlRequest.httpMethod = "POST"
        addHeaders(to: &urlRequest, contentType: true)
        urlRequest.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            try Self.checkStatus(response)
            let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
            guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
                throw ProviderError.invalidResponse
            }
            return MeetingSummaryResult(markdown: text, modelName: model)
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

                    let system = OpenAIAPIProvider.translationSystemPrompt(
                        from: request.sourceLanguage,
                        to: request.targetLanguage,
                        context: request.context
                    )
                    let body = MessagesRequest(
                        model: self.model,
                        maxTokens: 1024,
                        system: system,
                        messages: [.init(role: "user", content: request.text)],
                        stream: true
                    )

                    var urlRequest = URLRequest(url: self.baseURL.appendingPathComponent("messages"))
                    urlRequest.httpMethod = "POST"
                    self.addHeaders(to: &urlRequest, contentType: true)
                    urlRequest.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    try Self.checkStatus(response)

                    var accumulated = ""
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let event = try? JSONDecoder().decode(StreamDelta.self, from: data) {
                            if event.type == "message_stop" { break }
                            if event.type == "content_block_delta",
                               event.delta?.type == "text_delta",
                               let text = event.delta?.text, !text.isEmpty {
                                accumulated += text
                                continuation.yield(.partial(accumulated))
                            }
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

    private func addHeaders(to request: inout URLRequest, contentType: Bool = false) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if contentType {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
    }

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

// MARK: - Wire types

private struct MessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, system, messages, stream
        case maxTokens = "max_tokens"
    }
}

private struct MessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
}

private struct StreamDelta: Decodable {
    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
    let type: String
    let delta: Delta?
}
