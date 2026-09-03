//
//  AIProvider.swift
//  quetta
//
//  UI-independent provider contracts (spec §8.1). Adding a provider must never
//  require changes to session models, transcription UI, or the audio service.
//

import Foundation

/// Declares what an AI provider can do and its language/size limits.
struct ProviderCapabilities: Sendable, Equatable {
    var supportsLiveTranslation: Bool
    var supportsStreamingTranslation: Bool
    var supportsSummary: Bool
    var supportedLanguages: [LanguageCode]
    /// Recommended maximum number of characters per request.
    var recommendedCharacterLimit: Int

    static let none = ProviderCapabilities(
        supportsLiveTranslation: false,
        supportsStreamingTranslation: false,
        supportsSummary: false,
        supportedLanguages: [],
        recommendedCharacterLimit: 0
    )
}

/// Base contract shared by every provider.
protocol AIProvider: AnyObject, Sendable {
    var id: UUID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    /// Validates credentials/reachability. Throws a `ProviderError` on failure.
    func validateConfiguration() async throws
}

// MARK: - Translation

struct TranslationRequest: Sendable {
    var text: String
    var sourceLanguage: LanguageCode
    var targetLanguage: LanguageCode
    /// Monotonic index in the session's translation queue.
    var sessionSegmentIndex: Int
    /// Short rolling context of recently translated segments (when supported).
    var context: [String]
}

/// Progressive translation output. Providers without streaming emit a single `.completed`.
enum TranslationEvent: Sendable {
    case partial(String)
    case completed(String)
}

protocol TranslationProvider: AIProvider {
    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<TranslationEvent, Error>
}

// MARK: - Summary

struct SummaryRequest: Sendable {
    var transcript: String
    /// Optional translation text, provided only for reference.
    var translation: String?
    var outputLanguage: LanguageCode
    /// The session title, used only as light context.
    var meetingTitle: String
}

struct MeetingSummaryResult: Sendable {
    var markdown: String
    var modelName: String?
}

protocol SummaryProvider: AIProvider {
    func generateSummary(_ request: SummaryRequest) async throws -> MeetingSummaryResult
}

// MARK: - Errors

enum ProviderError: LocalizedError, Sendable {
    case notConfigured
    case unavailableInThisVersion
    case authentication
    case rateLimited
    case network
    case invalidResponse
    case cancelled
    case unsupportedLanguage
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "error.provider.notConfigured")
        case .unavailableInThisVersion:
            return String(localized: "error.provider.unavailable")
        case .authentication:
            return String(localized: "error.provider.authentication")
        case .rateLimited:
            return String(localized: "error.provider.rateLimited")
        case .network:
            return String(localized: "error.network")
        case .invalidResponse:
            return String(localized: "error.provider.invalidResponse")
        case .cancelled:
            return String(localized: "error.provider.cancelled")
        case .unsupportedLanguage:
            return String(localized: "error.provider.unsupportedLanguage")
        case .message(let text):
            return text
        }
    }
}
