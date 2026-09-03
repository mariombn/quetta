//
//  AIProviderRegistry.swift
//  quetta
//
//  Resolves active provider configurations into concrete providers without ever
//  exposing secrets to the UI (spec §8.1). Secrets are read from the Keychain
//  only at the moment a provider instance is built.
//

import Foundation

@MainActor
@Observable
final class AIProviderRegistry {

    @ObservationIgnored let secretStore: SecretStore

    init(secretStore: SecretStore) {
        self.secretStore = secretStore
    }

    // MARK: - Secret management (plaintext only crosses here, never stored elsewhere)

    func saveAPIKey(_ key: String, for config: ProviderConfiguration) throws {
        try secretStore.save(key, account: config.keychainAccount)
    }

    func hasSecret(for config: ProviderConfiguration) -> Bool {
        switch config.kind {
        case .openAI:
            return ((try? secretStore.read(account: config.keychainAccount)) ?? nil) != nil
        case .codexOAuth:
            return makeOAuthService(for: config).storedTokens() != nil
        default:
            return false
        }
    }

    /// Builds the isolated OAuth service for a Codex configuration.
    func makeOAuthService(for config: ProviderConfiguration) -> CodexOAuthService {
        CodexOAuthService(secretStore: secretStore, account: config.keychainAccount)
    }

    func deleteSecret(for config: ProviderConfiguration) throws {
        try secretStore.delete(account: config.keychainAccount)
    }

    // MARK: - Provider resolution

    func makeProvider(for config: ProviderConfiguration) -> (any AIProvider)? {
        switch config.kind {
        case .openAI:
            let key = ((try? secretStore.read(account: config.keychainAccount)) ?? nil) ?? ""
            return OpenAIAPIProvider(
                id: config.id,
                displayName: config.displayName,
                apiKey: key,
                model: config.modelName ?? "gpt-4o-mini"
            )
        case .codexOAuth:
            return CodexOAuthProvider(
                id: config.id,
                displayName: config.displayName,
                oauth: makeOAuthService(for: config),
                model: config.modelName ?? "gpt-5.6-luna"
            )
        case .gemini, .ollama:
            return nil
        }
    }

    func summaryProvider(for config: ProviderConfiguration) -> (any SummaryProvider)? {
        makeProvider(for: config) as? any SummaryProvider
    }

    func translationProvider(for config: ProviderConfiguration) -> (any TranslationProvider)? {
        makeProvider(for: config) as? any TranslationProvider
    }

    func capabilities(for config: ProviderConfiguration) -> ProviderCapabilities {
        makeProvider(for: config)?.capabilities ?? .none
    }

    // MARK: - Capability-based selection (spec §8.1: only list compatible providers)

    func configurationsSupportingSummary(from configs: [ProviderConfiguration]) -> [ProviderConfiguration] {
        configs.filter { $0.isEnabled && capabilities(for: $0).supportsSummary }
    }

    func configurationsSupportingTranslation(
        from configs: [ProviderConfiguration],
        source: LanguageCode,
        target: LanguageCode
    ) -> [ProviderConfiguration] {
        configs.filter { config in
            guard config.isEnabled else { return false }
            let caps = capabilities(for: config)
            return caps.supportsLiveTranslation
                && caps.supportedLanguages.contains(source)
                && caps.supportedLanguages.contains(target)
        }
    }
}
