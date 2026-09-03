//
//  TranscriptionEngine.swift
//  quetta
//
//  Local/system transcription contract. Kept separate from `AIProvider` so the
//  LLM layer never couples to audio capture (spec §8.2 — Apple Speech).
//

import Foundation
import AVFoundation

/// A recognition update emitted by a transcription engine.
struct TranscriptionUpdate: Sendable {
    /// The current text for the in-flight utterance.
    var text: String
    /// Whether this text is stable/final and may be persisted.
    var isFinal: Bool
}

protocol TranscriptionEngine: AnyObject {
    /// Whether on-device recognition is available for the given language.
    func supportsOnDevice(for language: LanguageCode) -> Bool

    /// Begins recognition for a language, delivering a stream of updates.
    /// The caller feeds PCM buffers via `append(_:)`.
    func start(language: LanguageCode) throws -> AsyncThrowingStream<TranscriptionUpdate, Error>

    /// Feeds a mono PCM buffer to the recognizer.
    func append(_ buffer: AVAudioPCMBuffer)

    /// Finishes the current recognition request, flushing pending audio.
    func finish()

    /// Immediately stops recognition and discards pending audio.
    func cancel()
}
