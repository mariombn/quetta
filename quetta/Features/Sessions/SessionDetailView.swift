//
//  SessionDetailView.swift
//  quetta
//
//  Session detail (spec §6.3): editable title, metadata, tabs for transcript,
//  translation (when present) and summary, plus export, delete and retry-summary.
//

import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Bindable var session: MeetingSession

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppPreferences.self) private var preferences
    @Environment(AIProviderRegistry.self) private var registry
    @Environment(\.modelContext) private var modelContext

    private enum Tab: Hashable { case transcript, translation, summary }
    @State private var tab: Tab = .transcript
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(String(localized: "session.title"), text: $session.title)
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .onSubmit { try? modelContext.save() }

            metadata

            Picker("", selection: $tab) {
                Text(String(localized: "tab.transcript")).tag(Tab.transcript)
                if session.mode == .translation {
                    Text(String(localized: "tab.translation")).tag(Tab.translation)
                }
                Text(String(localized: "tab.summary")).tag(Tab.summary)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            ScrollView {
                switch tab {
                case .transcript: transcriptTab
                case .translation: translationTab
                case .summary: summaryTab
                }
            }

            Spacer()
        }
        .padding(20)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    MarkdownExportService.export(session, locale: preferences.interfaceLocale)
                } label: { Label(String(localized: "session.export"), systemImage: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: { Label(String(localized: "session.delete"), systemImage: "trash") }
            }
        }
        .alert(String(localized: "session.delete.confirm.title"), isPresented: $confirmDelete) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "session.delete"), role: .destructive) {
                modelContext.delete(session)
                try? modelContext.save()
            }
        } message: {
            Text(String(localized: "session.delete.confirm.message"))
        }
    }

    private var metadata: some View {
        HStack(spacing: 12) {
            metaChip(String(localized: String.LocalizationValue(session.mode.displayNameKey)))
            metaChip(MarkdownExporter.formatDuration(session.duration))
            metaChip(String(localized: String.LocalizationValue(session.transcriptionLanguage.displayNameKey)))
            if session.mode == .translation, let s = session.sourceLanguage, let t = session.targetLanguage {
                metaChip("\(s.rawValue.uppercased()) → \(t.rawValue.uppercased())")
            }
            metaChip(String(localized: String.LocalizationValue(session.status.displayNameKey)))
        }
        .font(.caption)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    private var transcriptTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            let speech = session.orderedTranscriptSegments.filter { $0.isFinal }
            if speech.isEmpty {
                Text(String(localized: "export.empty")).foregroundStyle(.secondary)
            } else {
                ForEach(speech) { seg in
                    if seg.kind == .speech {
                        Text(seg.text).textSelection(.enabled)
                    } else {
                        Text(seg.text).font(.caption).italic().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var translationTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            let transcriptByID = Dictionary(uniqueKeysWithValues: session.transcriptSegments.map { ($0.id, $0.text) })
            ForEach(session.orderedTranslationSegments) { seg in
                VStack(alignment: .leading, spacing: 2) {
                    Text(transcriptByID[seg.transcriptSegmentID] ?? "").font(.callout.bold())
                    if seg.status == .failed {
                        Text(seg.failureMessage ?? String(localized: "panel.translationError"))
                            .font(.caption).foregroundStyle(.red)
                    } else {
                        Text(seg.translatedText).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.status == .generatingSummary {
                ProgressView(String(localized: "status.generatingSummary"))
            }
            if let summary = session.summary, !summary.markdown.isEmpty {
                MarkdownText(markdown: summary.markdown)
            } else if let message = session.summary?.failureMessage ?? session.failureMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "summary.unavailable"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    if canRetrySummary {
                        Button(String(localized: "summary.retry")) {
                            coordinator.retrySummary(for: session)
                        }
                    }
                }
            } else {
                Text(String(localized: "summary.none")).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canRetrySummary: Bool {
        guard let id = session.summaryProviderID else { return false }
        let descriptor = FetchDescriptor<ProviderConfiguration>(predicate: #Predicate { $0.id == id })
        guard let config = try? modelContext.fetch(descriptor).first else { return false }
        return registry.capabilities(for: config).supportsSummary
    }
}
