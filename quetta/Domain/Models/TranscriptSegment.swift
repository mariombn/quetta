//
//  TranscriptSegment.swift
//  quetta
//
//  A single stabilized (or marker) unit of transcript text.
//

import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var kindRaw: String
    var text: String
    var isFinal: Bool
    var createdAt: Date

    var session: MeetingSession?

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        kind: SegmentKind = .speech,
        text: String,
        isFinal: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.kindRaw = kind.rawValue
        self.text = text
        self.isFinal = isFinal
        self.createdAt = createdAt
    }

    var kind: SegmentKind {
        get { SegmentKind(rawValue: kindRaw) ?? .speech }
        set { kindRaw = newValue.rawValue }
    }
}
