//
//  AppPreferences.swift
//  quetta
//
//  User preferences persisted in UserDefaults (never secrets).
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AppPreferences {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        static let interfaceLanguage = "pref.interfaceLanguage"
        static let appearance = "pref.appearance"
        static let transcriptionLanguage = "pref.transcriptionLanguage"
        static let summaryLanguage = "pref.summaryLanguage"
        static let sendTextToProvider = "pref.sendTextToProvider"
        static let hasCompletedOnboarding = "pref.hasCompletedOnboarding"
        static let defaultSummaryProviderID = "pref.defaultSummaryProviderID"
        static let defaultTranslationProviderID = "pref.defaultTranslationProviderID"
        static let micGain = "pref.micGain"
    }

    var interfaceLanguage: InterfaceLanguage {
        get { InterfaceLanguage(rawValue: defaults.string(forKey: Keys.interfaceLanguage) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Keys.interfaceLanguage) }
    }

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Keys.appearance) }
    }

    var transcriptionLanguage: LanguageCode {
        get { LanguageCode(rawValue: defaults.string(forKey: Keys.transcriptionLanguage) ?? "") ?? LanguageCode.fromSystem() }
        set { defaults.set(newValue.rawValue, forKey: Keys.transcriptionLanguage) }
    }

    var summaryLanguage: LanguageCode {
        get { LanguageCode(rawValue: defaults.string(forKey: Keys.summaryLanguage) ?? "") ?? resolvedInterfaceLanguageCode }
        set { defaults.set(newValue.rawValue, forKey: Keys.summaryLanguage) }
    }

    /// Whether transcription text may be sent to an external provider. On by
    /// default only AFTER explicit onboarding explanation (spec §6.4.1).
    var sendTextToProvider: Bool {
        get { defaults.object(forKey: Keys.sendTextToProvider) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.sendTextToProvider) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    var defaultSummaryProviderID: UUID? {
        get { defaults.string(forKey: Keys.defaultSummaryProviderID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Keys.defaultSummaryProviderID) }
    }

    var defaultTranslationProviderID: UUID? {
        get { defaults.string(forKey: Keys.defaultTranslationProviderID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Keys.defaultTranslationProviderID) }
    }

    /// Amplification factor for microphone input (1.0 = no boost, range 1.0–4.0).
    var micGain: Float {
        get {
            let stored = defaults.float(forKey: Keys.micGain)
            return stored == 0 ? 2.0 : stored
        }
        set { defaults.set(newValue, forKey: Keys.micGain) }
    }

    // MARK: - Derived

    /// The concrete language the interface should use.
    var resolvedInterfaceLanguageCode: LanguageCode {
        switch interfaceLanguage {
        case .system: return LanguageCode.fromSystem() == .spanish ? .english : LanguageCode.fromSystem()
        case .portuguese: return .portuguese
        case .english: return .english
        }
    }

    /// Locale used for title generation and formatting.
    var interfaceLocale: Locale {
        switch interfaceLanguage {
        case .system: return .current
        case .portuguese: return Locale(identifier: "pt_BR")
        case .english: return Locale(identifier: "en_US")
        }
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Locale override list for SwiftUI `.environment(\.locale, ...)`.
    var localeIdentifierForUI: String? {
        switch interfaceLanguage {
        case .system: return nil
        case .portuguese: return "pt-BR"
        case .english: return "en-US"
        }
    }
}
