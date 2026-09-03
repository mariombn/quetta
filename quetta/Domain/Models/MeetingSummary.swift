//
//  MeetingSummary.swift
//  quetta
//
//  Persisted structured Markdown summary for a session.
//

import Foundation
import SwiftData

@Model
final class MeetingSummary {
    @Attribute(.unique) var id: UUID
    var markdown: String
    var generatedAt: Date
    /// Non-secret provenance metadata.
    var providerDisplayName: String?
    var modelName: String?
    var failureMessage: String?

    var session: MeetingSession?

    init(
        id: UUID = UUID(),
        markdown: String,
        generatedAt: Date = Date(),
        providerDisplayName: String? = nil,
        modelName: String? = nil,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.markdown = markdown
        self.generatedAt = generatedAt
        self.providerDisplayName = providerDisplayName
        self.modelName = modelName
        self.failureMessage = failureMessage
    }
}
