//
//  TestSupport.swift
//  quettaTests
//
//  Fakes used across the test suite.
//

import Foundation
@testable import quetta

/// In-memory `SecretStore` for tests — never touches the Keychain.
final class FakeSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func save(_ value: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = value
    }

    func read(account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[account]
    }

    func delete(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = nil
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }
}

/// Deterministic translation provider that prefixes the input text.
nonisolated final class FakeTranslationProvider: TranslationProvider, @unchecked Sendable {
    let id = UUID()
    let displayName = "Fake"
    var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsLiveTranslation: true,
            supportsStreamingTranslation: true,
            supportsSummary: false,
            supportedLanguages: [.portuguese, .english, .spanish],
            recommendedCharacterLimit: 1000
        )
    }

    func validateConfiguration() async throws {}

    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.completed("T:\(request.text)"))
            continuation.finish()
        }
    }
}

/// Translation provider that always fails, to test per-item error handling.
nonisolated final class FailingTranslationProvider: TranslationProvider, @unchecked Sendable {
    let id = UUID()
    let displayName = "Failing"
    var capabilities: ProviderCapabilities { .none }
    func validateConfiguration() async throws {}
    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: ProviderError.network) }
    }
}
