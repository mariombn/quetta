//
//  AppCoordinator.swift
//  quetta
//
//  The single source of truth for the active session lifecycle (spec §12, §13).
//  Views observe this coordinator; they never start capture, call providers, or
//  touch the database directly.
//

import Foundation
import SwiftUI
import SwiftData
import AVFoundation

@MainActor
@Observable
final class AppCoordinator {

    // Dependencies
    let modelContext: ModelContext
    let preferences: AppPreferences
    let permissions: PermissionService
    let connectivity: ConnectivityService
    let notifications: NotificationService
    let registry: AIProviderRegistry
    let panel: FloatingPanelController
    let audio = AudioCaptureService()

    // Live state observed by the UI
    private(set) var currentSession: MeetingSession?
    var livePartialText: String = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var networkInterrupted = false
    private(set) var panelVisible = false
    private(set) var lastErrorMessage: String?

    /// Provides the SwiftUI content for the floating panel (set by the app root).
    var panelContent: (() -> AnyView)?

    /// Called when a session fully completes (after summary or without summary). Set by AppState.
    var onSessionFinished: (() -> Void)?

    // Private session machinery
    private var speech: SpeechTranscriptionService?
    private var transcriptionTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var translationQueue: TranslationQueue?
    private var summaryTask: Task<Void, Never>?
    private var nextOrderIndex = 0

    init(
        modelContext: ModelContext,
        preferences: AppPreferences,
        permissions: PermissionService,
        connectivity: ConnectivityService,
        notifications: NotificationService,
        registry: AIProviderRegistry,
        panel: FloatingPanelController
    ) {
        self.modelContext = modelContext
        self.preferences = preferences
        self.permissions = permissions
        self.connectivity = connectivity
        self.notifications = notifications
        self.registry = registry
        self.panel = panel

        self.connectivity.onChange = { [weak self] connected in
            self?.handleConnectivityChange(connected: connected)
        }

        repairInterruptedSessions()
    }

    /// If the app terminated mid-session (crash/quit), close out any sessions
    /// stuck in a non-terminal state, preserving their texts (spec §15).
    private func repairInterruptedSessions() {
        let descriptor = FetchDescriptor<MeetingSession>()
        guard let sessions = try? modelContext.fetch(descriptor) else { return }
        var repaired = false
        for session in sessions where !session.status.isTerminal {
            session.status = .completedWithoutSummary
            if session.endedAt == nil { session.endedAt = Date() }
            session.failureMessage = String(localized: "session.interrupted")
            repaired = true
        }
        if repaired { try? modelContext.save() }
    }

    var isSessionActive: Bool {
        guard let status = currentSession?.status else { return false }
        return !status.isTerminal
    }

    // MARK: - Start

    func startSession(
        mode: SessionMode,
        transcriptionLanguage: LanguageCode,
        sourceLanguage: LanguageCode?,
        targetLanguage: LanguageCode?,
        summaryLanguage: LanguageCode,
        micEnabled: Bool,
        systemEnabled: Bool,
        translationProviderID: UUID?,
        summaryProviderID: UUID?
    ) async throws -> MeetingSession {
        guard currentSession == nil else { throw SessionStartError.alreadyRunning }
        guard connectivity.isConnected else { throw SessionStartError.noConnection }
        guard micEnabled || systemEnabled else { throw SessionStartError.noSource }

        // Re-check permissions for the requested sources.
        permissions.refreshAll()
        if micEnabled && permissions.microphone != .granted { throw SessionStartError.microphoneNotGranted }
        if systemEnabled && permissions.screenCapture != .granted { throw SessionStartError.screenNotGranted }
        if permissions.speech != .granted { throw SessionStartError.speechNotGranted }

        let title = TitleGenerator.automaticTitle(for: Date(), locale: preferences.interfaceLocale)
        let session = MeetingSession(
            title: title,
            mode: mode,
            status: .draft,
            transcriptionLanguage: transcriptionLanguage,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            summaryLanguage: summaryLanguage,
            microphoneEnabled: micEnabled,
            systemAudioEnabled: systemEnabled,
            translationProviderID: translationProviderID,
            summaryProviderID: summaryProviderID
        )
        modelContext.insert(session)

        session.status = try SessionStateMachine.validate(from: .draft, to: .active)
        session.startedAt = Date()
        currentSession = session
        nextOrderIndex = 0
        networkInterrupted = false
        lastErrorMessage = nil
        livePartialText = ""
        try? modelContext.save()

        // Translation pipeline (translation mode only).
        if mode == .translation,
           let configID = translationProviderID,
           let config = configuration(for: configID),
           let provider = registry.translationProvider(for: config) {
            let queue = TranslationQueue(provider: provider)
            queue.onResult = { [weak self] result in self?.apply(result) }
            translationQueue = queue
        }

        await startCapturePipeline(session: session)
        startTimer()
        showPanel()
        return session
    }

    // MARK: - Capture pipeline

    private func startCapturePipeline(session: MeetingSession) async {
        let speech = SpeechTranscriptionService()
        self.speech = speech
        audio.setMicGain(preferences.micGain)
        audio.setBufferSink { [weak speech] buffer in
            speech?.append(buffer)
        }
        do {
            let stream = try speech.start(language: session.transcriptionLanguage)
            transcriptionTask = Task { [weak self] in
                do {
                    for try await update in stream {
                        await self?.handleTranscription(update)
                    }
                } catch {
                    await self?.reportRecognitionFailure(error)
                }
            }
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        await audio.start(microphone: session.microphoneEnabled, systemAudio: session.systemAudioEnabled)
    }

    /// Hard stop: discards any in-flight utterance (used on connectivity loss).
    private func stopCapturePipeline() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        audio.setBufferSink(nil)
        audio.stopAll()
        speech?.cancel()
        speech = nil
    }

    /// Graceful stop: ends the audio, waits (bounded) for the recognizer to emit
    /// the final result of the in-flight utterance, then tears down.
    private func flushRecognition(timeout: TimeInterval = 5) async {
        audio.setBufferSink(nil)
        audio.stopAll()
        let task = transcriptionTask
        transcriptionTask = nil
        speech?.finish()
        if let task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await task.value }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                }
                _ = await group.next()
                group.cancelAll()
            }
        }
        speech?.cancel()
        speech = nil
        livePartialText = ""
    }

    private func handleTranscription(_ update: TranscriptionUpdate) {
        // Finals may also arrive while pausing/finalizing (utterance flush).
        guard let session = currentSession,
              session.status == .active || session.status == .paused || session.status == .finalizing
        else { return }
        if update.isFinal {
            let trimmed = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
            livePartialText = ""
            guard !trimmed.isEmpty else { return }
            let segment = TranscriptSegment(
                orderIndex: nextOrderIndex,
                kind: .speech,
                text: trimmed,
                isFinal: true
            )
            modelContext.insert(segment)
            segment.session = session
            nextOrderIndex += 1
            try? modelContext.save()
            enqueueTranslationIfNeeded(for: segment, in: session)
        } else {
            livePartialText = update.text
        }
    }

    private func enqueueTranslationIfNeeded(for segment: TranscriptSegment, in session: MeetingSession) {
        guard session.mode == .translation,
              let queue = translationQueue,
              let source = session.sourceLanguage,
              let target = session.targetLanguage else { return }

        let translation = TranslationSegment(
            transcriptSegmentID: segment.id,
            orderIndex: segment.orderIndex,
            status: .pending
        )
        modelContext.insert(translation)
        translation.session = session
        try? modelContext.save()

        queue.enqueue(TranslationQueueItem(
            transcriptSegmentID: segment.id,
            orderIndex: segment.orderIndex,
            text: segment.text,
            sourceLanguage: source,
            targetLanguage: target
        ))
    }

    private func apply(_ result: TranslationResult) {
        // Fetch by id so late results still persist while the session finalizes.
        let targetID = result.transcriptSegmentID
        let descriptor = FetchDescriptor<TranslationSegment>(
            predicate: #Predicate { $0.transcriptSegmentID == targetID }
        )
        guard let translation = try? modelContext.fetch(descriptor).first else { return }
        // Never rewrite a segment already completed.
        if translation.status == .completed { return }
        translation.status = result.status
        if result.status == .completed || result.status == .streaming {
            translation.translatedText = result.text
        }
        translation.failureMessage = result.failureMessage
        try? modelContext.save()
    }

    private func reportRecognitionFailure(_ error: Error) {
        lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Pause / Resume

    func pause() {
        guard let session = currentSession, session.status == .active else { return }
        session.status = (try? SessionStateMachine.validate(from: .active, to: .paused)) ?? session.status
        try? modelContext.save()
        Task { [weak self] in
            guard let self else { return }
            // Flush the pending utterance first so the marker lands after it.
            await self.flushRecognition()
            guard let session = self.currentSession, session.status == .paused else { return }
            self.addMarker(.pausedMarker, to: session)
            try? self.modelContext.save()
        }
    }

    func resume() {
        guard let session = currentSession, session.status == .paused else { return }
        guard connectivity.isConnected else {
            lastErrorMessage = String(localized: "error.network")
            return
        }
        session.status = (try? SessionStateMachine.validate(from: .paused, to: .active)) ?? session.status
        networkInterrupted = false
        addMarker(.resumedMarker, to: session)
        try? modelContext.save()
        Task { await startCapturePipeline(session: session) }
    }

    private func addMarker(_ kind: SegmentKind, to session: MeetingSession) {
        let text = kind == .pausedMarker
            ? String(localized: "session.pausedMarker")
            : String(localized: "session.resumedMarker")
        let marker = TranscriptSegment(orderIndex: nextOrderIndex, kind: kind, text: text, isFinal: true)
        modelContext.insert(marker)
        marker.session = session
        nextOrderIndex += 1
    }

    // MARK: - Audio source toggles

    func setMicrophone(enabled: Bool) {
        guard let session = currentSession else { return }
        // Keep at least one source active.
        if !enabled && !session.systemAudioEnabled { return }
        session.microphoneEnabled = enabled
        try? modelContext.save()
        Task { await audio.setMicrophone(enabled: enabled) }
    }

    func setSystemAudio(enabled: Bool) {
        guard let session = currentSession else { return }
        if !enabled && !session.microphoneEnabled { return }
        session.systemAudioEnabled = enabled
        try? modelContext.save()
        Task { await audio.setSystemAudio(enabled: enabled) }
    }

    // MARK: - Finalize & summarize

    func finalize() {
        guard let session = currentSession else { return }
        let from = session.status
        guard from == .active || from == .paused else { return }

        stopTimer()
        session.status = (try? SessionStateMachine.validate(from: from, to: .finalizing)) ?? .finalizing
        session.endedAt = Date()
        try? modelContext.save()

        Task { [weak self] in
            guard let self else { return }
            // Wait for the recognizer to flush the in-flight utterance so it is
            // persisted (and translated) before the summary runs.
            await self.flushRecognition()
            self.completeFinalize(session)
        }
    }

    private func completeFinalize(_ session: MeetingSession) {
        let summaryConfig = configuration(for: session.summaryProviderID)
        let summaryProvider = summaryConfig.flatMap { registry.summaryProvider(for: $0) }

        if let summaryProvider, summaryConfig != nil {
            session.status = .generatingSummary
            try? modelContext.save()
            runSummary(for: session, provider: summaryProvider, providerName: summaryConfig?.displayName)
        } else {
            session.status = .completedWithoutSummary
            try? modelContext.save()
            finishSession()
        }
    }

    private func runSummary(for session: MeetingSession, provider: any SummaryProvider, providerName: String?) {
        let transcript = assembleTranscript(session)
        let translation = session.mode == .translation ? assembleTranslation(session) : nil
        let request = SummaryRequest(
            transcript: transcript,
            translation: translation,
            outputLanguage: session.summaryLanguage,
            meetingTitle: session.title
        )
        let sessionID = session.id
        summaryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await provider.generateSummary(request)
                await self.completeSummary(sessionID: sessionID, result: result, providerName: providerName)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await self.failSummary(sessionID: sessionID, message: message)
            }
        }
    }

    private func completeSummary(sessionID: UUID, result: MeetingSummaryResult, providerName: String?) {
        guard let session = session(with: sessionID) else { return }
        if let summary = session.summary {
            // Update in place — replacing a cascade to-one relationship deletes
            // the old object under the observing UI and crashes SwiftData.
            summary.markdown = result.markdown
            summary.generatedAt = Date()
            summary.providerDisplayName = providerName
            summary.modelName = result.modelName
            summary.failureMessage = nil
        } else {
            let summary = MeetingSummary(
                markdown: result.markdown,
                providerDisplayName: providerName,
                modelName: result.modelName
            )
            // Insert BEFORE wiring the relationship; the inverse fills the other side.
            modelContext.insert(summary)
            summary.session = session
        }
        session.failureMessage = nil
        session.status = .completed
        try? modelContext.save()
        notifications.notifySummaryReady(sessionTitle: session.title)
        if session.id == currentSession?.id { finishSession() }
    }

    private func failSummary(sessionID: UUID, message: String) {
        guard let session = session(with: sessionID) else { return }
        session.status = .completedWithoutSummary
        session.failureMessage = message
        if let summary = session.summary {
            summary.failureMessage = message
        }
        try? modelContext.save()
        notifications.notifySummaryFailed(sessionTitle: session.title)
        if session.id == currentSession?.id { finishSession() }
    }

    /// Re-attempts summary generation from the session detail screen.
    func retrySummary(for session: MeetingSession) {
        guard let config = configuration(for: session.summaryProviderID),
              let provider = registry.summaryProvider(for: config) else { return }
        session.failureMessage = nil
        session.status = .generatingSummary
        try? modelContext.save()
        runSummary(for: session, provider: provider, providerName: config.displayName)
    }

    private func finishSession() {
        stopTimer()
        currentSession = nil
        translationQueue = nil
        hidePanel()
        onSessionFinished?()
    }

    // MARK: - Panel

    func showPanel() {
        guard let content = panelContent else { return }
        panel.show { content() }
        panelVisible = true
    }

    func hidePanel() {
        panel.persistCurrentOrigin()
        panel.hide()
        panelVisible = false
    }

    func togglePanel() {
        panelVisible ? hidePanel() : showPanel()
    }

    // MARK: - Connectivity

    private func handleConnectivityChange(connected: Bool) {
        guard let session = currentSession else { return }
        if !connected && session.status == .active {
            // Stop all capture/sending and surface the cause; do not silently retry.
            stopCapturePipeline()
            session.status = (try? SessionStateMachine.validate(from: .active, to: .paused)) ?? session.status
            networkInterrupted = true
            session.failureMessage = String(localized: "error.network.interrupted")
            try? modelContext.save()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.elapsed = self?.currentSession?.duration ?? 0
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Helpers

    private func configuration(for id: UUID?) -> ProviderConfiguration? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<ProviderConfiguration>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func session(with id: UUID) -> MeetingSession? {
        let descriptor = FetchDescriptor<MeetingSession>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func assembleTranscript(_ session: MeetingSession) -> String {
        session.orderedTranscriptSegments
            .filter { $0.kind == .speech && $0.isFinal }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    private func assembleTranslation(_ session: MeetingSession) -> String {
        session.orderedTranslationSegments
            .filter { $0.status == .completed }
            .map(\.translatedText)
            .joined(separator: "\n\n")
    }
}

enum SessionStartError: LocalizedError {
    case alreadyRunning
    case noConnection
    case noSource
    case microphoneNotGranted
    case screenNotGranted
    case speechNotGranted

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return String(localized: "error.session.alreadyRunning")
        case .noConnection: return String(localized: "error.network")
        case .noSource: return String(localized: "error.audio.noSource")
        case .microphoneNotGranted: return String(localized: "error.permission.microphone")
        case .screenNotGranted: return String(localized: "error.permission.screen")
        case .speechNotGranted: return String(localized: "error.permission.speech")
        }
    }
}
