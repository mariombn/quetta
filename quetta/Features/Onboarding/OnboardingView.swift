//
//  OnboardingView.swift
//  quetta
//
//  First-run flow (spec §5.1): privacy explanation, connectivity check, permission
//  requests in order, defaults, and optional provider setup.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(PermissionService.self) private var permissions
    @Environment(ConnectivityService.self) private var connectivity
    @Environment(AIProviderRegistry.self) private var registry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case intro, connectivity, permissions, preferences, provider
    }

    @State private var step: Step = .intro
    @State private var providerKind: ProviderKind = .codexOAuth
    @State private var apiKey: String = ""
    @State private var providerName: String = "ChatGPT (Codex)"
    @State private var savingProvider = false
    @State private var providerMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            ScrollView { content.padding(.vertical, 4) }
            Divider()
            footer
        }
        .padding(20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "onboarding.title")).font(.largeTitle.bold())
            Text(String(localized: "onboarding.subtitle")).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "onboarding.intro.noAudio"), systemImage: "waveform.slash")
                Label(String(localized: "onboarding.intro.textSent"), systemImage: "text.bubble")
                Text(String(localized: "onboarding.intro.detail"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .connectivity:
            VStack(alignment: .leading, spacing: 12) {
                if connectivity.isConnected {
                    Label(String(localized: "onboarding.connectivity.ok"), systemImage: "wifi")
                        .foregroundStyle(.green)
                } else {
                    Label(String(localized: "onboarding.connectivity.none"), systemImage: "wifi.slash")
                        .foregroundStyle(.red)
                    Text(String(localized: "onboarding.connectivity.retryHint"))
                        .foregroundStyle(.secondary)
                }
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "onboarding.permissions.detail")).foregroundStyle(.secondary)
                PermissionRow(kind: .microphone)
                PermissionRow(kind: .speech)
                PermissionRow(kind: .screenCapture)
                PermissionRow(kind: .notifications)
            }
        case .preferences:
            preferencesStep
        case .provider:
            providerStep
        }
    }

    @ViewBuilder
    private var preferencesStep: some View {
        @Bindable var prefs = preferences
        Form {
            Picker(String(localized: "settings.transcriptionLanguage"), selection: $prefs.transcriptionLanguage) {
                ForEach(LanguageCode.allCases) { lang in
                    Text(String(localized: String.LocalizationValue(lang.displayNameKey))).tag(lang)
                }
            }
            Picker(String(localized: "settings.appearance"), selection: $prefs.appearance) {
                ForEach(AppearancePreference.allCases) { a in
                    Text(String(localized: String.LocalizationValue(a.displayNameKey))).tag(a)
                }
            }
            Picker(String(localized: "settings.interfaceLanguage"), selection: $prefs.interfaceLanguage) {
                ForEach(InterfaceLanguage.allCases) { l in
                    Text(String(localized: String.LocalizationValue(l.displayNameKey))).tag(l)
                }
            }
        }
    }

    @ViewBuilder
    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "onboarding.provider.detail")).foregroundStyle(.secondary)

            Picker(String(localized: "provider.kind"), selection: $providerKind) {
                Text(String(localized: "provider.codex")).tag(ProviderKind.codexOAuth)
                Text(String(localized: "provider.openai")).tag(ProviderKind.openAI)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: providerKind) {
                providerName = providerKind == .codexOAuth ? "ChatGPT (Codex)" : "OpenAI"
                providerMessage = nil
            }

            Form {
                TextField(String(localized: "provider.name"), text: $providerName)
                if providerKind == .openAI {
                    SecureField(String(localized: "provider.apiKey"), text: $apiKey)
                }
            }
            if providerKind == .codexOAuth {
                Text(String(localized: "provider.codex.hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let providerMessage {
                Text(providerMessage).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                saveProvider()
            } label: {
                if savingProvider {
                    ProgressView().controlSize(.small)
                } else if providerKind == .codexOAuth {
                    Text(String(localized: "provider.codex.login"))
                } else {
                    Text(String(localized: "onboarding.provider.save"))
                }
            }
            .disabled(savingProvider || (providerKind == .openAI && apiKey.isEmpty))
            Text(String(localized: "onboarding.provider.skipHint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if step != .intro {
                Button(String(localized: "common.back")) { back() }
            }
            Spacer()
            if step == .provider {
                Button(String(localized: "onboarding.finish")) { finish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(String(localized: "common.next")) { next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == .connectivity && !connectivity.isConnected)
            }
        }
    }

    private func next() {
        if let idx = Step.allCases.firstIndex(of: step), idx + 1 < Step.allCases.count {
            step = Step.allCases[idx + 1]
        }
    }

    private func back() {
        if let idx = Step.allCases.firstIndex(of: step), idx > 0 {
            step = Step.allCases[idx - 1]
        }
    }

    private func saveProvider() {
        savingProvider = true
        providerMessage = nil
        let kind = providerKind
        let config = ProviderConfiguration(
            kind: kind,
            displayName: providerName.isEmpty
                ? String(localized: String.LocalizationValue(kind.displayNameKey))
                : providerName,
            modelName: kind == .codexOAuth ? "gpt-5.6-luna" : "gpt-4o-mini"
        )
        let key = apiKey
        Task {
            do {
                switch kind {
                case .openAI:
                    try registry.saveAPIKey(key, for: config)
                    let provider = registry.makeProvider(for: config)
                    try await provider?.validateConfiguration()
                case .codexOAuth:
                    let service = registry.makeOAuthService(for: config)
                    _ = try await service.login()
                default:
                    throw ProviderError.unavailableInThisVersion
                }
                modelContext.insert(config)
                preferences.defaultSummaryProviderID = config.id
                preferences.defaultTranslationProviderID = config.id
                try? modelContext.save()
                providerMessage = String(localized: "provider.test.success")
                apiKey = ""
            } catch {
                try? registry.deleteSecret(for: config)
                providerMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            savingProvider = false
        }
    }

    private func finish() {
        preferences.hasCompletedOnboarding = true
        dismiss()
    }
}
