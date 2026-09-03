//
//  TitleGenerator.swift
//  quetta
//
//  Generates the automatic session title, e.g. "Reunião — 03 set. 2026, 10:30".
//

import Foundation

enum TitleGenerator {

    /// Builds the default title in the interface language.
    /// - Parameters:
    ///   - date: The session creation date.
    ///   - locale: The interface locale (used for month abbreviation and format).
    static func automaticTitle(for date: Date, locale: Locale) -> String {
        let prefix = Localization.string("session.autoTitlePrefix", locale: locale)

        let formatter = DateFormatter()
        formatter.locale = locale
        // Localized medium date + short time, e.g. "3 de set. de 2026, 10:30".
        formatter.setLocalizedDateFormatFromTemplate("dd MMM yyyy, HH:mm")
        let stamp = formatter.string(from: date)

        return "\(prefix) — \(stamp)"
    }
}
