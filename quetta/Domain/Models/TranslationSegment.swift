//
//  TranslationSegment.swift
//  quetta
//
//  The translation counterpart of a transcript segment (translation mode only).
//

import Foundation
import SwiftData

@Model
final class TranslationSegment {
    @Attribute(.unique) var id: UUID
    /// Reference to the originating `TranscriptSegment.id`.
    var transcriptSegmentID: UUID
    var orderIndex: Int
    var translatedText: String
    var statusRaw: String
    var failureMessage: String?
    var createdAt: Date

    var session: MeetingSession?

    init(
        id: UUID = UUID(),
        transcriptSegmentID: UUID,
        orderIndex: Int,
        translatedText: String = "",
        status: TranslationStatus = .pending,
        failureMessage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.transcriptSegmentID = transcriptSegmentID
        self.orderIndex = orderIndex
        self.translatedText = translatedText
        self.statusRaw = status.rawValue
        self.failureMessage = failureMessage
        self.createdAt = createdAt
    }

    var status: TranslationStatus {
        get { TranslationStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}
