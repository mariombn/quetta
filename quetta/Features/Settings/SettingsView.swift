//
//  SettingsView.swift
//  quetta
//
//  Settings with four tabs (spec §6.4): General, Providers, Data, Permissions.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(String(localized: "settings.tab.general"), systemImage: "gear") }
            ProvidersSettingsView()
                .tabItem { Label(String(localized: "settings.tab.providers"), systemImage: "cpu") }
            DataSettingsView()
                .tabItem { Label(String(localized: "settings.tab.data"), systemImage: "externaldrive") }
            PermissionsSettingsView()
                .tabItem { Label(String(localized: "settings.tab.permissions"), systemImage: "lock.shield") }
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Picker(String(localized: "settings.interfaceLanguage"), selection: $prefs.interfaceLanguage) {
                ForEach(InterfaceLanguage.allCases) { l in
                    Text(String(localized: String.LocalizationValue(l.displayNameKey))).tag(l)
                }
            }
            Picker(String(localized: "settings.appearance"), selection: $prefs.appearance) {
                ForEach(AppearancePreference.allCases) { a in
                    Text(String(localized: String.LocalizationValue(a.displayNameKey))).tag(a)
                }
            }
            Picker(String(localized: "settings.transcriptionLanguage"), selection: $prefs.transcriptionLanguage) {
                ForEach(LanguageCode.allCases) { l in
                    Text(String(localized: String.LocalizationValue(l.displayNameKey))).tag(l)
                }
            }
            Picker(String(localized: "settings.summaryLanguage"), selection: $prefs.summaryLanguage) {
                ForEach(LanguageCode.allCases) { l in
                    Text(String(localized: String.LocalizationValue(l.displayNameKey))).tag(l)
                }
            }
            Section {
                Toggle(String(localized: "settings.sendText"), isOn: $prefs.sendTextToProvider)
                Text(String(localized: "settings.sendText.explanation"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Providers

struct ProvidersSettingsView: View {
    @Query(sort: \ProviderConfiguration.createdAt) private var providers: [ProviderConfiguration]
    @Environment(AIProviderRegistry.self) private var registry
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext

    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(providers) { provider in
                    ProviderRow(provider: provider)
                }
                if providers.isEmpty {
                    Text(String(localized: "providers.empty")).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    showAdd = true
                } label: { Label(String(localized: "providers.add"), systemImage: "plus") }
                Spacer()
            }
            .padding(.horizontal)

            @Bindable var prefs = preferences
            Form {
                Picker(String(localized: "providers.defaultSummary"), selection: $prefs.defaultSummaryProviderID) {
                    Text(String(localized: "common.none")).tag(UUID?.none)
                    ForEach(registry.configurationsSupportingSummary(from: providers)) { p in
                        Text(p.displayName).tag(Optional(p.id))
                    }
                }
                Picker(String(localized: "providers.defaultTranslation"), selection: $prefs.defaultTranslationProviderID) {
                    Text(String(localized: "common.none")).tag(UUID?.none)
                    ForEach(providers.filter { registry.capabilities(for: $0).supportsLiveTranslation }) { p in
                        Text(p.displayName).tag(Optional(p.id))
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .sheet(isPresented: $showAdd) {
            AddProviderView()
        }
    }
}

private struct ProviderRow: View {
    @Bindable var provider: ProviderConfiguration
    @Environment(AIProviderRegistry.self) private var registry
    @Environment(\.modelContext) private var modelContext

    @State private var testMessage: String?
    @State private var testing = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(provider.displayName).font(.headline)
                    if provider.requiresAttention {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                Text(String(localized: String.LocalizationValue(provider.kind.displayNameKey)))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(
                    String(localized: "provider.model"),
                    text: Binding(
                        get: { provider.modelName ?? "" },
                        set: { provider.modelName = $0.isEmpty ? nil : $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(maxWidth: 220)
                .onSubmit { try? modelContext.save() }
                if provider.kind == .ollama {
                    TextField(
                        String(localized: "provider.baseURL"),
                        text: Binding(
                            get: { provider.baseURLString ?? "" },
                            set: { provider.baseURLString = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 220)
                    .onSubmit { try? modelContext.save() }
                }
                if let testMessage {
                    Text(testMessage).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if testing {
                ProgressView().controlSize(.small)
            } else {
                Button(String(localized: "providers.test")) { test() }
            }
            Button(role: .destructive) { remove() } label: {
                Image(systemName: "trash")
            }
        }
        .padding(.vertical, 2)
    }

    private func test() {
        testing = true
        testMessage = nil
        let provider = self.provider
        Task {
            do {
                let instance = registry.makeProvider(for: provider)
                try await instance?.validateConfiguration()
                provider.requiresAttention = false
                try? modelContext.save()
                testMessage = String(localized: "provider.test.success")
            } catch {
                provider.requiresAttention = true
                try? modelContext.save()
                testMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            testing = false
        }
    }

    private func remove() {
        try? registry.deleteSecret(for: provider)
        modelContext.delete(provider)
        try? modelContext.save()
    }
}

private struct AddProviderView: View {
    @Environment(AIProviderRegistry.self) private var registry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ProviderKind = .openAI
    @State private var name: String = "OpenAI"
    @State private var apiKey: String = ""
    @State private var model: String = "gpt-4o-mini"
    @State private var baseURL: String = ""
    @State private var message: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "providers.add")).font(.title3.bold())
            Form {
                Picker(String(localized: "provider.kind"), selection: $kind) {
                    Text(String(localized: "provider.openai")).tag(ProviderKind.openAI)
                    Text(String(localized: "provider.anthropic")).tag(ProviderKind.anthropic)
                    Text(String(localized: "provider.openrouter")).tag(ProviderKind.openRouter)
                    Text(String(localized: "provider.ollama")).tag(ProviderKind.ollama)
                    Text(String(localized: "provider.codex")).tag(ProviderKind.codexOAuth)
                }
                TextField(String(localized: "provider.name"), text: $name)
                if kind == .openAI || kind == .anthropic || kind == .openRouter {
                    SecureField(String(localized: "provider.apiKey"), text: $apiKey)
                }
                TextField(String(localized: "provider.model"), text: $model)
                if kind == .ollama {
                    TextField(String(localized: "provider.baseURL"), text: $baseURL)
                }
                if kind == .codexOAuth {
                    Text(String(localized: "provider.codex.hint"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if kind == .ollama {
                    Text(String(localized: "provider.ollama.hint"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button(String(localized: "common.cancel")) { dismiss() }
                Spacer()
                Button {
                    save()
                } label: {
                    if saving {
                        ProgressView().controlSize(.small)
                    } else if kind == .codexOAuth {
                        Text(String(localized: "provider.codex.login"))
                    } else {
                        Text(String(localized: "common.save"))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onChange(of: kind) {
            apiKey = ""
            baseURL = ""
            switch kind {
            case .openAI:
                name = "OpenAI"
                model = "gpt-4o-mini"
            case .codexOAuth:
                name = "ChatGPT (Codex)"
                model = "gpt-5.6-luna"
            case .anthropic:
                name = "Claude"
                model = "claude-sonnet-4-6"
            case .openRouter:
                name = "OpenRouter"
                model = "meta-llama/llama-3.3-70b-instruct"
            case .ollama:
                name = "Ollama"
                model = "llama3.2"
                baseURL = "http://localhost:11434/v1"
            default:
                break
            }
        }
    }

    private var canSave: Bool {
        guard !saving else { return false }
        switch kind {
        case .openAI, .anthropic, .openRouter: return !apiKey.isEmpty
        case .codexOAuth: return CodexOAuthProvider.isAvailable
        case .ollama: return !model.isEmpty
        default: return false
        }
    }

    private func save() {
        saving = true
        message = nil
        let config = ProviderConfiguration(
            kind: kind,
            displayName: name.isEmpty ? String(localized: String.LocalizationValue(kind.displayNameKey)) : name,
            modelName: model.isEmpty ? nil : model,
            baseURLString: kind == .ollama && !baseURL.isEmpty ? baseURL : nil
        )
        let key = apiKey
        Task {
            do {
                switch kind {
                case .openAI, .anthropic, .openRouter:
                    try registry.saveAPIKey(key, for: config)
                    let provider = registry.makeProvider(for: config)
                    try await provider?.validateConfiguration()
                case .codexOAuth:
                    let service = registry.makeOAuthService(for: config)
                    _ = try await service.login()
                case .ollama:
                    let provider = registry.makeProvider(for: config)
                    try await provider?.validateConfiguration()
                default:
                    throw ProviderError.unavailableInThisVersion
                }
                modelContext.insert(config)
                try? modelContext.save()
                dismiss()
            } catch {
                try? registry.deleteSecret(for: config)
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                saving = false
            }
        }
    }
}

// MARK: - Data

struct DataSettingsView: View {
    @Query private var sessions: [MeetingSession]
    @Environment(\.modelContext) private var modelContext
    @State private var confirmClear = false

    var body: some View {
        Form {
            LabeledContent(String(localized: "data.sessionCount"), value: "\(sessions.count)")
            LabeledContent(String(localized: "data.spaceUsed"), value: formattedSize)
            Section {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label(String(localized: "data.clearAll"), systemImage: "trash")
                }
                Text(String(localized: "data.clearAll.explanation"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert(String(localized: "data.clearAll.confirm.title"), isPresented: $confirmClear) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "data.clearAll"), role: .destructive) { clearAll() }
        } message: {
            Text(String(localized: "data.clearAll.confirm.message"))
        }
    }

    private var formattedSize: String {
        var bytes = 0
        for session in sessions {
            bytes += session.title.utf8.count
            for seg in session.transcriptSegments { bytes += seg.text.utf8.count }
            for seg in session.translationSegments { bytes += seg.translatedText.utf8.count }
            bytes += session.summary?.markdown.utf8.count ?? 0
        }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func clearAll() {
        for session in sessions { modelContext.delete(session) }
        try? modelContext.save()
    }
}

// MARK: - Permissions

struct PermissionsSettingsView: View {
    @Environment(PermissionService.self) private var permissions

    var body: some View {
        Form {
            Section {
                PermissionRow(kind: .microphone)
                PermissionRow(kind: .speech)
                PermissionRow(kind: .screenCapture)
                PermissionRow(kind: .notifications)
            } footer: {
                Text(String(localized: "permissions.footer")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { permissions.refreshAll() }
    }
}
