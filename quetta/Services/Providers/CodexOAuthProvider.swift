//
//  CodexOAuthProvider.swift
//  quetta
//
//  Experimental, isolated personal provider (spec §3.2, §8.2, §18).
//
//  The adapter performs its OWN OAuth login (CodexOAuthService) in the user's
//  browser and stores its tokens ONLY in the macOS Keychain. It never reads or
//  depends on Pi Agent, the Codex CLI, or the ChatGPT app, nor extracts
//  credentials from other apps. Streaming text goes through CodexBackendClient.
//
//  It remains behind `isAvailable` so the whole integration can be disabled with
//  a clear "Unavailable in this version" message if the subscription contract
//  changes (spec §18); the OpenAI API-key provider stays the stable fallback.
//

import Foundation

nonisolated final class CodexOAuthProvider: TranslationProvider, SummaryProvider, @unchecked Sendable {

    /// Master availability flag (spec §18). If the contract breaks, flip to
    /// `false` so configurations report "Unavailable in this version" instead of
    /// failing obscurely.
    static let isAvailable = true

    let id: UUID
    let displayName: String
    private let oauth: CodexOAuthService
    private let client = CodexBackendClient()
    private let model: String

    init(
        id: UUID,
        displayName: String,
        oauth: CodexOAuthService,
        model: String = "gpt-5"
    ) {
        self.id = id
        self.displayName = displayName
        self.oauth = oauth
        self.model = model
    }

    var capabilities: ProviderCapabilities {
        guard Self.isAvailable else { return .none }
        return ProviderCapabilities(
            supportsLiveTranslation: true,
            supportsStreamingTranslation: true,
            supportsSummary: true,
            supportedLanguages: [.portuguese, .english, .spanish],
            recommendedCharacterLimit: 12_000
        )
    }

    // MARK: - AIProvider

    func validateConfiguration() async throws {
        guard Self.isAvailable else { throw ProviderError.unavailableInThisVersion }
        // Ensures tokens exist and can be refreshed; throws .notConfigured or
        // .authentication with actionable messages otherwise.
        _ = try await oauth.validTokens()
    }

    // MARK: - Login / logout (used by the configuration UI)

    var isLoggedIn: Bool { oauth.storedTokens() != nil }

    func login() async throws {
        guard Self.isAvailable else { throw ProviderError.unavailableInThisVersion }
        _ = try await oauth.login()
    }

    func logout() {
        oauth.logout()
    }

    // MARK: - Translation

    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard Self.isAvailable else { throw ProviderError.unavailableInThisVersion }
                    let tokens = try await self.oauth.validTokens()
                    let instructions = OpenAIAPIProvider.translationSystemPrompt(
                        from: request.sourceLanguage,
                        to: request.targetLanguage,
                        context: request.context
                    )
                    var accumulated = ""
                    for try await delta in self.client.streamText(
                        instructions: instructions,
                        userText: request.text,
                        model: self.model,
                        tokens: tokens
                    ) {
                        accumulated += delta
                        continuation.yield(.partial(accumulated))
                    }
                    continuation.yield(.completed(accumulated))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Summary

    func generateSummary(_ request: SummaryRequest) async throws -> MeetingSummaryResult {
        guard Self.isAvailable else { throw ProviderError.unavailableInThisVersion }
        let tokens = try await oauth.validTokens()

        let instructions = OpenAIAPIProvider.summarySystemPrompt(language: request.outputLanguage)
        var user = "Título: \(request.meetingTitle)\n\nTranscrição:\n\(request.transcript)"
        if let translation = request.translation, !translation.isEmpty {
            user += "\n\nTradução (referência):\n\(translation)"
        }

        var markdown = ""
        for try await delta in client.streamText(
            instructions: instructions,
            userText: user,
            model: model,
            tokens: tokens
        ) {
            markdown += delta
        }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.invalidResponse
        }
        return MeetingSummaryResult(markdown: markdown, modelName: model)
    }
}
