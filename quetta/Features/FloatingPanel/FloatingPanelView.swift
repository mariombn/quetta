//
//  FloatingPanelView.swift
//  quetta
//
//  The live session UI shown inside the floating NSPanel (spec §6.2).
//

import SwiftUI

struct FloatingPanelView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: 0) {
            if let session = coordinator.currentSession {
                header(session)
                Divider()
                sourceBar
                Divider()
                content(session)
                Divider()
                footer(session)
            } else {
                Text(String(localized: "panel.noSession")).padding()
            }
        }
        .frame(width: FloatingPanelController.width)
        .frame(minHeight: FloatingPanelController.minHeight, maxHeight: 480)
    }

    // MARK: - Header

    private func header(_ session: MeetingSession) -> some View {
        HStack(spacing: 10) {
            indicator(session)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.headline).lineLimit(1)
                Text(String(localized: String.LocalizationValue(session.mode.displayNameKey)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(MarkdownExporter.formatDuration(coordinator.elapsed))
                .monospacedDigit().font(.headline)
            Button {
                coordinator.hidePanel()
            } label: { Image(systemName: "eye.slash") }
                .help(String(localized: "menu.hidePanel"))
            Button {
                coordinator.finalize()
            } label: { Image(systemName: "stop.circle.fill").foregroundStyle(.red) }
                .help(String(localized: "menu.finish"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func indicator(_ session: MeetingSession) -> some View {
        Group {
            if coordinator.networkInterrupted {
                Circle().fill(.red)
            } else if session.status == .paused {
                Circle().fill(.yellow)
            } else {
                Circle().fill(.red)
            }
        }
        .frame(width: 10, height: 10)
    }

    // MARK: - Source bar

    private var sourceBar: some View {
        HStack(spacing: 16) {
            sourceToggle(
                title: String(localized: "source.microphone"),
                systemImage: "mic.fill",
                isOn: coordinator.audio.microphoneActive,
                error: coordinator.audio.microphoneError
            ) { coordinator.setMicrophone(enabled: !coordinator.audio.microphoneActive) }

            sourceToggle(
                title: String(localized: "source.systemAudio"),
                systemImage: "speaker.wave.2.fill",
                isOn: coordinator.audio.systemAudioActive,
                error: coordinator.audio.systemAudioError
            ) { coordinator.setSystemAudio(enabled: !coordinator.audio.systemAudioActive) }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func sourceToggle(title: String, systemImage: String, isOn: Bool, error: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            if let error {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ session: MeetingSession) -> some View {
        if session.mode == .translation {
            translationColumns(session)
        } else {
            transcriptList(session)
        }
    }

    private func transcriptList(_ session: MeetingSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.orderedTranscriptSegments) { segment in
                        segmentView(segment)
                    }
                    if !coordinator.livePartialText.isEmpty {
                        Text(coordinator.livePartialText)
                            .foregroundStyle(.secondary)
                            .id("live")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .onChange(of: session.transcriptSegments.count) {
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: TranscriptSegment) -> some View {
        switch segment.kind {
        case .speech:
            Text(segment.text).textSelection(.enabled)
        case .pausedMarker, .resumedMarker:
            Text(segment.text).font(.caption).italic().foregroundStyle(.secondary)
        }
    }

    private func translationColumns(_ session: MeetingSession) -> some View {
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 16) {
                column(title: String(localized: "panel.original")) {
                    ForEach(session.orderedTranscriptSegments.filter { $0.kind == .speech }) { seg in
                        Text(seg.text).textSelection(.enabled)
                    }
                    if !coordinator.livePartialText.isEmpty {
                        Text(coordinator.livePartialText).foregroundStyle(.secondary)
                    }
                }
                Divider()
                column(title: String(localized: "panel.translation")) {
                    ForEach(session.orderedTranslationSegments) { seg in
                        translationView(seg)
                    }
                }
            }
            .padding(16)
        }
    }

    private func column<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
        .frame(width: 340, alignment: .leading)
    }

    @ViewBuilder
    private func translationView(_ segment: TranslationSegment) -> some View {
        switch segment.status {
        case .completed:
            Text(segment.translatedText).textSelection(.enabled)
        case .streaming:
            Text(segment.translatedText.isEmpty ? String(localized: "panel.translating") : segment.translatedText)
                .foregroundStyle(.secondary)
        case .pending:
            Text(String(localized: "panel.translating")).foregroundStyle(.secondary)
        case .failed:
            Label(segment.failureMessage ?? String(localized: "panel.translationError"), systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red)
        }
    }

    // MARK: - Footer

    private func footer(_ session: MeetingSession) -> some View {
        HStack(spacing: 12) {
            if session.status == .active {
                Button {
                    coordinator.pause()
                } label: { Label(String(localized: "menu.pause"), systemImage: "pause.fill") }
            } else if session.status == .paused {
                Button {
                    coordinator.resume()
                } label: { Label(String(localized: "menu.resume"), systemImage: "play.fill") }
            }

            Spacer()

            if coordinator.networkInterrupted {
                Label(String(localized: "error.network.interrupted"), systemImage: "wifi.slash")
                    .font(.caption).foregroundStyle(.red)
            } else if session.summaryProviderID == nil {
                Label(String(localized: "setup.noSummary"), systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
