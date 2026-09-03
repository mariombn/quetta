//
//  SpeechTranscriptionService.swift
//  quetta
//
//  Apple Speech (SFSpeechRecognizer) transcription engine (spec §7.2).
//
//  Segmentation is deterministic and does NOT depend on the recognizer's final
//  results (which are unreliable when requests are rotated): partial results are
//  watched, and when the text stops changing for `stabilityWindow` seconds the
//  settled partial IS the utterance — the service emits it as a final update
//  itself, discards the old request and starts a fresh one. `finish()` likewise
//  emits any pending partial as final immediately. Callbacks from rotated-out
//  requests are ignored, so text is never duplicated or silently rewritten.
//

import Foundation
import Speech
import AVFoundation

nonisolated final class SpeechTranscriptionService: NSObject, TranscriptionEngine, @unchecked Sendable {

    private let lock = NSLock()
    private let timerQueue = DispatchQueue(label: "com.quetta.speech.stability")

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?
    private var stabilityTimer: DispatchSourceTimer?

    private var isActive = false
    private var restartCount = 0
    private let maxConsecutiveRestarts = 5

    // Utterance stabilization state (guarded by `lock`).
    private var lastPartialText = ""
    private var lastChangeAt = Date()
    private var requestStartedAt = Date()
    /// Seconds of unchanged partial text after which the utterance is finalized.
    private let stabilityWindow: TimeInterval = 1.8
    /// Hard rotation point, safely before the framework's per-request limit.
    private let maxRequestDuration: TimeInterval = 45

    func supportsOnDevice(for language: LanguageCode) -> Bool {
        let locale = Locale(identifier: language.localeIdentifier)
        return SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
    }

    func start(language: LanguageCode) throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        let locale = Locale(identifier: language.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        lock.lock()
        self.recognizer = recognizer
        self.isActive = true
        self.restartCount = 0
        self.lastPartialText = ""
        lock.unlock()

        return AsyncThrowingStream { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
            self.beginRequest()
            self.startStabilityTimer()
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }

    /// Emits any pending partial text as a final segment, then stops. The stream
    /// finishes synchronously — no dependency on a server round-trip.
    func finish() {
        lock.lock()
        isActive = false
        let pending = lastPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastPartialText = ""
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        self.task = nil
        self.request = nil
        lock.unlock()

        stopStabilityTimer()
        task?.cancel()
        if !pending.isEmpty {
            continuation?.yield(TranscriptionUpdate(text: pending, isFinal: true))
        }
        continuation?.finish()
    }

    /// Stops immediately, discarding any pending audio and text.
    func cancel() {
        lock.lock()
        isActive = false
        lastPartialText = ""
        let task = self.task
        self.task = nil
        self.request = nil
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        stopStabilityTimer()
        task?.cancel()
        continuation?.finish()
    }

    // MARK: - Requests

    private func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        // The product requires connectivity; allow server recognition when needed.
        request.requiresOnDeviceRecognition = false
        return request
    }

    private func beginRequest() {
        lock.lock()
        guard isActive, let recognizer = self.recognizer else {
            lock.unlock()
            return
        }
        let newRequest = makeRequest()
        request = newRequest
        requestStartedAt = Date()
        lastPartialText = ""
        lastChangeAt = Date()
        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            self?.handle(result: result, error: error, from: newRequest)
        }
        lock.unlock()
    }

    /// Finalizes the current utterance from its settled partial text, then starts
    /// a fresh request. The old request is cancelled — its text was already
    /// emitted, so nothing is lost and late callbacks from it are ignored.
    private func rotateRequest() {
        lock.lock()
        guard isActive, request != nil else {
            lock.unlock()
            return
        }
        let settled = lastPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastPartialText = ""
        let continuation = self.continuation
        let oldTask = task
        task = nil
        request = nil // late callbacks from the old request become non-current
        lock.unlock()

        oldTask?.cancel()
        if !settled.isEmpty {
            continuation?.yield(TranscriptionUpdate(text: settled, isFinal: true))
        }
        beginRequest()
    }

    // MARK: - Result handling

    private func handle(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        from sourceRequest: SFSpeechAudioBufferRecognitionRequest
    ) {
        if let result {
            let text = result.bestTranscription.formattedString

            lock.lock()
            guard sourceRequest === request else {
                // Rotated-out request — its settled text was already emitted.
                lock.unlock()
                return
            }
            let active = isActive
            let continuation = self.continuation
            var finishing: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?
            if result.isFinal {
                restartCount = 0
                lastPartialText = ""
                if !active {
                    finishing = self.continuation
                    self.continuation = nil
                }
            } else if text != lastPartialText {
                lastPartialText = text
                lastChangeAt = Date()
            }
            lock.unlock()

            if result.isFinal {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    continuation?.yield(TranscriptionUpdate(text: trimmed, isFinal: true))
                }
                if active {
                    // Natural end of utterance on the live request — keep going.
                    beginRequest()
                }
                finishing?.finish()
            } else {
                continuation?.yield(TranscriptionUpdate(text: text, isFinal: false))
            }
            return
        }

        if error != nil {
            lock.lock()
            guard sourceRequest === request else {
                // Expected noise from cancelled/rotated-out requests.
                lock.unlock()
                return
            }
            let active = isActive
            var shouldRestart = false
            var finishGracefully: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?
            var finishThrowing: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?
            if active {
                shouldRestart = restartCount < maxConsecutiveRestarts
                if shouldRestart {
                    restartCount += 1
                } else {
                    isActive = false
                    finishThrowing = continuation
                    continuation = nil
                }
            } else {
                finishGracefully = continuation
                continuation = nil
            }
            lock.unlock()

            if shouldRestart { beginRequest() }
            finishGracefully?.finish()
            finishThrowing?.finish(throwing: TranscriptionError.recognitionFailed)
        }
    }

    // MARK: - Stability timer

    private func startStabilityTimer() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.checkStability()
        }
        timer.resume()
        lock.lock()
        stabilityTimer = timer
        lock.unlock()
    }

    private func stopStabilityTimer() {
        lock.lock()
        let timer = stabilityTimer
        stabilityTimer = nil
        lock.unlock()
        timer?.cancel()
    }

    private func checkStability() {
        lock.lock()
        guard isActive, request != nil else {
            lock.unlock()
            return
        }
        let now = Date()
        let stable = !lastPartialText.isEmpty
            && now.timeIntervalSince(lastChangeAt) >= stabilityWindow
        let tooLong = now.timeIntervalSince(requestStartedAt) >= maxRequestDuration
        lock.unlock()

        if stable || tooLong {
            rotateRequest()
        }
    }
}

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return String(localized: "error.speech.unavailable")
        case .recognitionFailed:
            return String(localized: "error.speech.failed")
        }
    }
}
