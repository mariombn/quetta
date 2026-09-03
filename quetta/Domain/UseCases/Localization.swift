//
//  Localization.swift
//  quetta
//
//  Looks up strings in a SPECIFIC language bundle. `String(localized:locale:)`
//  uses the process's preferred languages to choose the localization; its `locale`
//  argument only affects formatting. For text whose language must follow the
//  chosen interface locale (titles, Markdown export), we resolve the matching
//  `.lproj` bundle explicitly.
//

import Foundation

enum Localization {

    /// Returns the bundle for the given locale's language, falling back to main.
    static func bundle(for locale: Locale) -> Bundle {
        let language = locale.language.languageCode?.identifier ?? "en"
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        // Try the base language of region-qualified codes (e.g. "pt-BR" -> "pt").
        if let path = Bundle.main.path(forResource: String(language.prefix(2)), ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    /// Localized string for `key` in the language of `locale`.
    static func string(_ key: String, locale: Locale) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle(for: locale), value: key, comment: "")
    }
}
