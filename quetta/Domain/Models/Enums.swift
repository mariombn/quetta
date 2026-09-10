//
//  Enums.swift
//  quetta
//
//  Domain enumerations shared across models, services and UI.
//

import Foundation

/// Supported transcription / translation languages in the MVP.
enum LanguageCode: String, Codable, CaseIterable, Identifiable, Sendable {
    case portuguese = "pt"
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    /// BCP-47 locale identifier used to build `SFSpeechRecognizer` locales.
    var localeIdentifier: String {
        switch self {
        case .portuguese: return "pt-BR"
        case .english: return "en-US"
        case .spanish: return "es-ES"
        }
    }

    /// Localized display name for the language, resolved in the interface language.
    var displayNameKey: String {
        switch self {
        case .portuguese: return "language.portuguese"
        case .english: return "language.english"
        case .spanish: return "language.spanish"
        }
    }

    /// Best-effort mapping from a system locale to a supported language.
    static func fromSystem() -> LanguageCode {
        let code = Locale.current.language.languageCode?.identifier ?? "pt"
        switch code {
        case "pt": return .portuguese
        case "en": return .english
        case "es": return .spanish
        default: return .portuguese
        }
    }
}

/// The two supported session modes.
enum SessionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case simple
    case translation

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .simple: return "mode.simple"
        case .translation: return "mode.translation"
        }
    }
}

/// Full session lifecycle status (see spec §13).
enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case active
    case paused
    case finalizing
    case generatingSummary
    case completed
    case completedWithoutSummary
    case failed

    var displayNameKey: String {
        switch self {
        case .draft: return "status.draft"
        case .active: return "status.active"
        case .paused: return "status.paused"
        case .finalizing: return "status.finalizing"
        case .generatingSummary: return "status.generatingSummary"
        case .completed: return "status.completed"
        case .completedWithoutSummary: return "status.completedWithoutSummary"
        case .failed: return "status.failed"
        }
    }

    /// Whether the session is in a terminal (no further capture) state.
    var isTerminal: Bool {
        switch self {
        case .completed, .completedWithoutSummary, .failed:
            return true
        default:
            return false
        }
    }
}

/// The nature of a transcript segment.
enum SegmentKind: String, Codable, Sendable {
    case speech
    case pausedMarker
    case resumedMarker
}

/// Translation lifecycle for a single segment.
enum TranslationStatus: String, Codable, Sendable {
    case pending
    case streaming
    case completed
    case failed
}

/// Kinds of AI providers.
enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case codexOAuth
    case anthropic
    case openRouter
    case ollama
    case gemini

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .openAI: return "provider.openai"
        case .codexOAuth: return "provider.codex"
        case .anthropic: return "provider.anthropic"
        case .openRouter: return "provider.openrouter"
        case .ollama: return "provider.ollama"
        case .gemini: return "provider.gemini"
        }
    }

    var isAvailableInMVP: Bool {
        switch self {
        case .openAI, .codexOAuth, .anthropic, .openRouter, .ollama: return true
        case .gemini: return false
        }
    }
}

/// Appearance preference.
enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .system: return "appearance.system"
        case .light: return "appearance.light"
        case .dark: return "appearance.dark"
        }
    }
}

/// Interface language preference.
enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case portuguese = "pt"
    case english = "en"

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .system: return "interfaceLanguage.system"
        case .portuguese: return "language.portuguese"
        case .english: return "language.english"
        }
    }
}
