//
//  SessionSetupView.swift
//  quetta
//
//  New-session configuration (spec §5.2): mode, audio sources, translation
//  languages/provider, summary provider.
//

import SwiftUI
import SwiftData

struct SessionSetupView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppPreferences.self) private var preferences
    @Environment(AIProviderRegistry.self) private var registry
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ProviderConfiguration.createdAt) private var providers: [ProviderConfiguration]

    @State private var mode: SessionMode = .simple
    @State private var micEnabled = true
    @State private var systemEnabled = true
    @State private var sourceLanguage: LanguageCode = .portuguese
    @State private var targetLanguage: LanguageCode = .english
    @State private var translationProviderID: UUID?
    @State private var summaryProviderID: UUID?

    @State private var micGain: Float = 2.0
    @State private var starting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "setup.title")).font(.title2.bold()).padding([.top, .horizontal], 20)

            Form {
                modeSection
                sourcesSection
                if mode == .translation { translationSection }
                summarySection
                hintsSection
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .onAppear(perform: applyDefaults)
        .alert(String(localized: "common.error"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var modeSection: some View {
        Section(String(localized: "setup.mode")) {
            Picker(String(localized: "setup.mode"), selection: $mode) {
                ForEach(SessionMode.allCases) { m in
                    Text(String(localized: String.LocalizationValue(m.displayNameKey))).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var sourcesSection: some View {
        Section(String(localized: "setup.sources")) {
            Toggle(String(localized: "source.microphone"), isOn: $micEnabled)
            if micEnabled {
                HStack {
                    Text(String(localized: "setup.micGain"))
                        .font(.callout)
                    Slider(value: $micGain, in: 1.0...4.0, step: 0.5)
                    Text(String(format: "%.1f×", micGain))
                        .font(.callout.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                }
            }
            Toggle(String(localized: "source.systemAudio"), isOn: $systemEnabled)
            if !micEnabled && !systemEnabled {
                Text(String(localized: "setup.noSource")).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var translationSection: some View {
        Section(String(localized: "setup.translation")) {
            Picker(String(localized: "setup.sourceLanguage"), selection: $sourceLanguage) {
                ForEach(LanguageCode.allCases) { l in
                    Text(String(localized: String.LocalizationValue(l.displayNameKey))).tag(l)
                }
            }
            Picker(String(localized: "setup.targetLanguage"), selection: $targetLanguage) {
                ForEach(LanguageCode.allCases) { l in
                    Text(String(localized: String.LocalizationValue(l.displayNameKey))).tag(l)
                }
            }
            if sourceLanguage == targetLanguage {
                Text(String(localized: "setup.sameLanguage")).font(.caption).foregroundStyle(.red)
            }

            let compatible = registry.configurationsSupportingTranslation(
                from: providers, source: sourceLanguage, target: targetLanguage
            )
            if compatible.isEmpty {
                Text(String(localized: "setup.noTranslationProvider")).font(.caption).foregroundStyle(.red)
            } else {
                Picker(String(localized: "setup.translationProvider"), selection: $translationProviderID) {
                    ForEach(compatible) { p in
                        Text(p.displayName).tag(Optional(p.id))
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        Section(String(localized: "setup.summary")) {
            let compatible = registry.configurationsSupportingSummary(from: providers)
            if compatible.isEmpty {
                Text(String(localized: "setup.noSummaryProvider")).font(.caption).foregroundStyle(.secondary)
            } else {
                Picker(String(localized: "setup.summaryProvider"), selection: $summaryProviderID) {
                    Text(String(localized: "setup.noSummary")).tag(UUID?.none)
                    ForEach(compatible) { p in
                        Text(p.displayName).tag(Optional(p.id))
                    }
                }
            }
        }
    }

    private var hintsSection: some View {
        Section {
            if mode == .simple {
                Label(
                    String(localized: "setup.transcriptionLanguageHint \(String(localized: String.LocalizationValue(preferences.transcriptionLanguage.displayNameKey)))"),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Label(String(localized: "setup.languageQualityHint"), systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button(String(localized: "common.cancel")) { dismiss() }
            Spacer()
            Button {
                start()
            } label: {
                if starting { ProgressView().controlSize(.small) }
                else { Text(String(localized: "setup.start")) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canStart)
        }
        .padding(16)
    }

    private var canStart: Bool {
        guard micEnabled || systemEnabled, !starting else { return false }
        if mode == .translation {
            guard sourceLanguage != targetLanguage, translationProviderID != nil else { return false }
        }
        return true
    }

    private func applyDefaults() {
        summaryProviderID = preferences.defaultSummaryProviderID
        translationProviderID = preferences.defaultTranslationProviderID
        sourceLanguage = preferences.transcriptionLanguage
        targetLanguage = preferences.transcriptionLanguage == .english ? .portuguese : .english
        micGain = preferences.micGain
    }

    private func start() {
        preferences.micGain = micGain
        starting = true
        Task {
            do {
                _ = try await coordinator.startSession(
                    mode: mode,
                    transcriptionLanguage: mode == .translation ? sourceLanguage : preferences.transcriptionLanguage,
                    sourceLanguage: mode == .translation ? sourceLanguage : nil,
                    targetLanguage: mode == .translation ? targetLanguage : nil,
                    summaryLanguage: preferences.summaryLanguage,
                    micEnabled: micEnabled,
                    systemEnabled: systemEnabled,
                    translationProviderID: mode == .translation ? translationProviderID : nil,
                    summaryProviderID: summaryProviderID
                )
                starting = false
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                starting = false
            }
        }
    }
}
