//
//  TranslationQueue.swift
//  quetta
//
//  Serial, order-preserving translation pipeline (spec §7.3). Only final/stable
//  transcript segments are enqueued. An error in one item is reported for that
//  item (with limited internal retry) and never blocks the following items. A
//  translation already marked final is never silently rewritten.
//

import Foundation

struct TranslationQueueItem: Sendable, Equatable {
    let transcriptSegmentID: UUID
    let orderIndex: Int
    let text: String
    let sourceLanguage: LanguageCode
    let targetLanguage: LanguageCode
}

struct TranslationResult: Sendable, Equatable {
    let transcriptSegmentID: UUID
    let orderIndex: Int
    let status: TranslationStatus
    let text: String
    let failureMessage: String?
}

@MainActor
final class TranslationQueue {

    private let provider: any TranslationProvider
    private let maxRetries: Int
    private let contextWindow = 3

    private var pending: [TranslationQueueItem] = []
    private var finalizedIDs: Set<UUID> = []
    private var recentTranslations: [String] = []
    private var isProcessing = false

    /// Delivers status/text updates for the UI and persistence layer.
    var onResult: ((TranslationResult) -> Void)?

    init(provider: any TranslationProvider, maxRetries: Int = 1) {
        self.provider = provider
        self.maxRetries = maxRetries
    }

    func enqueue(_ item: TranslationQueueItem) {
        pending.append(item)
        onResult?(TranslationResult(
            transcriptSegmentID: item.transcriptSegmentID,
            orderIndex: item.orderIndex,
            status: .pending,
            text: "",
            failureMessage: nil
        ))
        startIfNeeded()
    }

    /// Stops processing further items (e.g. session ending). In-flight item finishes.
    func drainAndStop() {
        pending.removeAll()
    }

    private func startIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        Task { await self.processLoop() }
    }

    private func processLoop() async {
        while !pending.isEmpty {
            let item = pending.removeFirst()
            // Never re-translate a segment already finalized.
            guard !finalizedIDs.contains(item.transcriptSegmentID) else { continue }
            await process(item)
        }
        isProcessing = false
    }

    private func process(_ item: TranslationQueueItem) async {
        var attempt = 0
        while attempt <= maxRetries {
            do {
                let request = TranslationRequest(
                    text: item.text,
                    sourceLanguage: item.sourceLanguage,
                    targetLanguage: item.targetLanguage,
                    sessionSegmentIndex: item.orderIndex,
                    context: recentTranslations
                )
                var lastText = ""
                for try await event in provider.translate(request) {
                    switch event {
                    case .partial(let text):
                        lastText = text
                        emit(item, status: .streaming, text: text, error: nil)
                    case .completed(let text):
                        lastText = text
                    }
                }
                finalizedIDs.insert(item.transcriptSegmentID)
                appendContext(lastText)
                emit(item, status: .completed, text: lastText, error: nil)
                return
            } catch {
                attempt += 1
                if attempt > maxRetries {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    emit(item, status: .failed, text: "", error: message)
                    return
                }
            }
        }
    }

    private func emit(_ item: TranslationQueueItem, status: TranslationStatus, text: String, error: String?) {
        onResult?(TranslationResult(
            transcriptSegmentID: item.transcriptSegmentID,
            orderIndex: item.orderIndex,
            status: status,
            text: text,
            failureMessage: error
        ))
    }

    private func appendContext(_ text: String) {
        guard !text.isEmpty else { return }
        recentTranslations.append(text)
        if recentTranslations.count > contextWindow {
            recentTranslations.removeFirst(recentTranslations.count - contextWindow)
        }
    }
}
