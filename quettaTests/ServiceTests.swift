//
//  ServiceTests.swift
//  quettaTests
//

import Testing
import Foundation
import AVFoundation
import SwiftData
@testable import quetta

@Suite("Keychain abstraction")
struct SecretStoreTests {
    @Test("Fake store round-trips and deletes")
    func roundTrip() throws {
        let store = FakeSecretStore()
        try store.save("secret-123", account: "acct")
        #expect(try store.read(account: "acct") == "secret-123")
        try store.delete(account: "acct")
        #expect(try store.read(account: "acct") == nil)
    }
}

@MainActor
@Suite("Provider selection by capabilities")
struct ProviderSelectionTests {

    @Test("OpenAI config is offered for summary and translation")
    func openAISelected() {
        let registry = AIProviderRegistry(secretStore: FakeSecretStore())
        let openAI = ProviderConfiguration(kind: .openAI, displayName: "OpenAI")
        let configs = [openAI]

        let summary = registry.configurationsSupportingSummary(from: configs)
        #expect(summary.map(\.id) == [openAI.id])

        let translation = registry.configurationsSupportingTranslation(from: configs, source: .portuguese, target: .english)
        #expect(translation.map(\.id) == [openAI.id])
    }

    @Test("Codex config is offered while the provider is available")
    func codexOffered() {
        let registry = AIProviderRegistry(secretStore: FakeSecretStore())
        let codex = ProviderConfiguration(kind: .codexOAuth, displayName: "Codex")
        let configs = [codex]
        let expected = CodexOAuthProvider.isAvailable ? [codex.id] : []
        #expect(registry.configurationsSupportingSummary(from: configs).map(\.id) == expected)
        #expect(registry.configurationsSupportingTranslation(from: configs, source: .portuguese, target: .english).map(\.id) == expected)
    }

    @Test("Disabled providers are excluded")
    func disabledExcluded() {
        let registry = AIProviderRegistry(secretStore: FakeSecretStore())
        let disabled = ProviderConfiguration(kind: .openAI, displayName: "OpenAI", isEnabled: false)
        #expect(registry.configurationsSupportingSummary(from: [disabled]).isEmpty)
    }
}

@MainActor
@Suite("Translation queue")
struct TranslationQueueTests {

    @Test("Preserves order across serial processing")
    func preservesOrder() async {
        let queue = TranslationQueue(provider: FakeTranslationProvider())
        var completed: [TranslationResult] = []

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.onResult = { result in
                if result.status == .completed {
                    completed.append(result)
                    if completed.count == 3 { cont.resume() }
                }
            }
            for i in 0..<3 {
                queue.enqueue(TranslationQueueItem(
                    transcriptSegmentID: UUID(),
                    orderIndex: i,
                    text: "line\(i)",
                    sourceLanguage: .portuguese,
                    targetLanguage: .english
                ))
            }
        }

        #expect(completed.map(\.orderIndex) == [0, 1, 2])
        #expect(completed.map(\.text) == ["T:line0", "T:line1", "T:line2"])
    }

    @Test("A failing item reports failure without blocking others")
    func failureIsolated() async {
        let queue = TranslationQueue(provider: FailingTranslationProvider(), maxRetries: 0)
        var failure: TranslationResult?

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.onResult = { result in
                if result.status == .failed {
                    failure = result
                    cont.resume()
                }
            }
            queue.enqueue(TranslationQueueItem(
                transcriptSegmentID: UUID(),
                orderIndex: 0,
                text: "boom",
                sourceLanguage: .portuguese,
                targetLanguage: .english
            ))
        }

        #expect(failure?.status == .failed)
        #expect(failure?.failureMessage != nil)
    }
}

@Suite("Audio mixer")
struct AudioMixerTests {

    @Test("Converts any input to the canonical mono 16 kHz format")
    func convertsToCanonical() {
        let mixer = AudioMixer()
        let holder = BufferHolder()
        mixer.setSink { buffer in holder.store(buffer) }

        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!
        let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_410)!
        input.frameLength = 4_410

        mixer.process(input, from: .microphone)

        let received = holder.value
        #expect(received != nil)
        #expect(received?.format.sampleRate == 16_000)
        #expect(received?.format.channelCount == 1)
    }
}

/// Captures the last delivered buffer from the mixer's synchronous sink.
final class BufferHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?
    func store(_ b: AVAudioPCMBuffer) { lock.lock(); buffer = b; lock.unlock() }
    var value: AVAudioPCMBuffer? { lock.lock(); defer { lock.unlock() }; return buffer }
}

@MainActor
@Suite("Session persistence and cleanup")
struct PersistenceTests {

    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeInMemoryContainer())
    }

    @Test("Deleting a session cascades to its segments")
    func deleteCascades() throws {
        let context = makeContext()
        let session = MeetingSession(
            title: "S", mode: .simple, transcriptionLanguage: .portuguese,
            summaryLanguage: .portuguese, microphoneEnabled: true, systemAudioEnabled: false
        )
        context.insert(session)
        let seg = TranscriptSegment(orderIndex: 0, text: "hi", isFinal: true)
        seg.session = session
        context.insert(seg)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<MeetingSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TranscriptSegment>()) == 1)

        context.delete(session)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<MeetingSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TranscriptSegment>()) == 0)
    }

    @Test("Clearing all sessions removes every session")
    func clearAll() throws {
        let context = makeContext()
        for i in 0..<3 {
            let s = MeetingSession(
                title: "S\(i)", mode: .simple, transcriptionLanguage: .portuguese,
                summaryLanguage: .portuguese, microphoneEnabled: true, systemAudioEnabled: false
            )
            context.insert(s)
        }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<MeetingSession>()) == 3)

        for s in try context.fetch(FetchDescriptor<MeetingSession>()) { context.delete(s) }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<MeetingSession>()) == 0)
    }
}
