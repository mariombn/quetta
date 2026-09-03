//
//  MeetingSession.swift
//  quetta
//
//  Root SwiftData entity for a meeting session. Stores only text — never audio.
//

import Foundation
import SwiftData

@Model
final class MeetingSession {
    @Attribute(.unique) var id: UUID
    var title: String

    var createdAt: Date
    var startedAt: Date?
    var endedAt: Date?

    /// Stored as raw values so SwiftData can persist the enums directly.
    var modeRaw: String
    var statusRaw: String
    var transcriptionLanguageRaw: String
    var sourceLanguageRaw: String?
    var targetLanguageRaw: String?
    var summaryLanguageRaw: String

    var microphoneEnabled: Bool
    var systemAudioEnabled: Bool

    /// Non-secret provider identifiers (references to `ProviderConfiguration.id`).
    var translationProviderID: UUID?
    var summaryProviderID: UUID?

    var failureMessage: String?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.session)
    var transcriptSegments: [TranscriptSegment]

    @Relationship(deleteRule: .cascade, inverse: \TranslationSegment.session)
    var translationSegments: [TranslationSegment]

    @Relationship(deleteRule: .cascade, inverse: \MeetingSummary.session)
    var summary: MeetingSummary?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        mode: SessionMode,
        status: SessionStatus = .draft,
        transcriptionLanguage: LanguageCode,
        sourceLanguage: LanguageCode? = nil,
        targetLanguage: LanguageCode? = nil,
        summaryLanguage: LanguageCode,
        microphoneEnabled: Bool,
        systemAudioEnabled: Bool,
        translationProviderID: UUID? = nil,
        summaryProviderID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.startedAt = nil
        self.endedAt = nil
        self.modeRaw = mode.rawValue
        self.statusRaw = status.rawValue
        self.transcriptionLanguageRaw = transcriptionLanguage.rawValue
        self.sourceLanguageRaw = sourceLanguage?.rawValue
        self.targetLanguageRaw = targetLanguage?.rawValue
        self.summaryLanguageRaw = summaryLanguage.rawValue
        self.microphoneEnabled = microphoneEnabled
        self.systemAudioEnabled = systemAudioEnabled
        self.translationProviderID = translationProviderID
        self.summaryProviderID = summaryProviderID
        self.failureMessage = nil
        self.transcriptSegments = []
        self.translationSegments = []
        self.summary = nil
    }

    // MARK: - Typed accessors

    var mode: SessionMode {
        get { SessionMode(rawValue: modeRaw) ?? .simple }
        set { modeRaw = newValue.rawValue }
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var transcriptionLanguage: LanguageCode {
        get { LanguageCode(rawValue: transcriptionLanguageRaw) ?? .portuguese }
        set { transcriptionLanguageRaw = newValue.rawValue }
    }

    var sourceLanguage: LanguageCode? {
        get { sourceLanguageRaw.flatMap(LanguageCode.init(rawValue:)) }
        set { sourceLanguageRaw = newValue?.rawValue }
    }

    var targetLanguage: LanguageCode? {
        get { targetLanguageRaw.flatMap(LanguageCode.init(rawValue:)) }
        set { targetLanguageRaw = newValue?.rawValue }
    }

    var summaryLanguage: LanguageCode {
        get { LanguageCode(rawValue: summaryLanguageRaw) ?? .portuguese }
        set { summaryLanguageRaw = newValue.rawValue }
    }

    /// Elapsed duration between start and end (or now while active).
    var duration: TimeInterval {
        guard let startedAt else { return 0 }
        let end = endedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt))
    }

    /// Transcript segments sorted by their persisted order.
    var orderedTranscriptSegments: [TranscriptSegment] {
        transcriptSegments.sorted { $0.orderIndex < $1.orderIndex }
    }

    var orderedTranslationSegments: [TranslationSegment] {
        translationSegments.sorted { $0.orderIndex < $1.orderIndex }
    }
}
