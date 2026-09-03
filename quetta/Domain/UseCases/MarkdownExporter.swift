//
//  MarkdownExporter.swift
//  quetta
//
//  Builds the Markdown export document (spec §11). Never includes tokens, keys,
//  credential ids or audio.
//

import Foundation

/// A value snapshot used for export, decoupled from SwiftData for testability.
struct MarkdownExportData: Equatable {
    struct TranscriptLine: Equatable {
        var kind: SegmentKind
        var text: String
    }
    struct TranslationPair: Equatable {
        var original: String
        var translated: String
    }

    var title: String
    var date: Date
    var duration: TimeInterval
    var mode: SessionMode
    var transcriptionLanguage: LanguageCode
    var transcript: [TranscriptLine]
    var translationPairs: [TranslationPair]
    var summaryMarkdown: String?
}

enum MarkdownExporter {

    static func makeExportData(from session: MeetingSession) -> MarkdownExportData {
        let transcript = session.orderedTranscriptSegments
            .filter { $0.isFinal }
            .map { MarkdownExportData.TranscriptLine(kind: $0.kind, text: $0.text) }

        // Pair each translation segment with its source transcript text.
        let transcriptByID = Dictionary(
            uniqueKeysWithValues: session.transcriptSegments.map { ($0.id, $0.text) }
        )
        let pairs: [MarkdownExportData.TranslationPair] = session.orderedTranslationSegments.map {
            MarkdownExportData.TranslationPair(
                original: transcriptByID[$0.transcriptSegmentID] ?? "",
                translated: $0.translatedText
            )
        }

        return MarkdownExportData(
            title: session.title,
            date: session.startedAt ?? session.createdAt,
            duration: session.duration,
            mode: session.mode,
            transcriptionLanguage: session.transcriptionLanguage,
            transcript: transcript,
            translationPairs: pairs,
            summaryMarkdown: session.summary?.markdown
        )
    }

    static func makeMarkdown(from data: MarkdownExportData, locale: Locale = .current) -> String {
        var out = "# \(data.title)\n\n"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        let dateLabel = Localization.string("export.date", locale: locale)
        let durationLabel = Localization.string("export.duration", locale: locale)
        let modeLabel = Localization.string("export.mode", locale: locale)
        let languageLabel = Localization.string("export.transcriptionLanguage", locale: locale)

        out += "- \(dateLabel): \(dateFormatter.string(from: data.date))\n"
        out += "- \(durationLabel): \(formatDuration(data.duration))\n"
        out += "- \(modeLabel): \(Localization.string(data.mode.displayNameKey, locale: locale))\n"
        out += "- \(languageLabel): \(Localization.string(data.transcriptionLanguage.displayNameKey, locale: locale))\n"
        out += "\n"

        out += "## \(Localization.string("export.section.transcript", locale: locale))\n\n"
        if data.transcript.isEmpty {
            out += "_\(Localization.string("export.empty", locale: locale))_\n\n"
        } else {
            for line in data.transcript {
                switch line.kind {
                case .speech:
                    out += "\(line.text)\n\n"
                case .pausedMarker:
                    out += "_\(Localization.string("session.pausedMarker", locale: locale))_\n\n"
                case .resumedMarker:
                    out += "_\(Localization.string("session.resumedMarker", locale: locale))_\n\n"
                }
            }
        }

        if data.mode == .translation {
            out += "## \(Localization.string("export.section.translation", locale: locale))\n\n"
            if data.translationPairs.isEmpty {
                out += "_\(Localization.string("export.empty", locale: locale))_\n\n"
            } else {
                for pair in data.translationPairs {
                    out += "**\(pair.original)**\n\n"
                    out += "\(pair.translated)\n\n"
                }
            }
        }

        out += "## \(Localization.string("export.section.summary", locale: locale))\n\n"
        if let summary = data.summaryMarkdown, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "\(summary)\n"
        } else {
            out += "_\(Localization.string("export.summaryUnavailable", locale: locale))_\n"
        }

        return out
    }

    /// A filesystem-safe file name derived from the session title.
    static func suggestedFileName(for title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = title
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "quetta" : cleaned
        return "\(base).md"
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
