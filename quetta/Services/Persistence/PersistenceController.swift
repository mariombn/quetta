//
//  PersistenceController.swift
//  quetta
//
//  Owns the SwiftData ModelContainer (local, private app storage).
//

import Foundation
import SwiftData

enum PersistenceController {

    static let schema = Schema([
        MeetingSession.self,
        TranscriptSegment.self,
        TranslationSegment.self,
        MeetingSummary.self,
        ProviderConfiguration.self,
    ])

    /// Shared on-disk container used by the app.
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// In-memory container for previews and tests.
    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }
}
