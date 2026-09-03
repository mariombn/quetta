//
//  SessionsListView.swift
//  quetta
//
//  Local session history (spec §6.3): list ordered by date descending, with open,
//  rename, export and delete via the detail pane.
//

import SwiftUI
import SwiftData

struct SessionsListView: View {
    @Query(sort: \MeetingSession.createdAt, order: .reverse) private var sessions: [MeetingSession]
    @Environment(\.modelContext) private var modelContext

    @State private var selection: MeetingSession?
    @State private var pendingDelete: MeetingSession?
    // Keep the list column always visible; a collapsed sidebar persists across
    // launches and makes the window look permanently empty.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                        .tag(session)
                        .contextMenu {
                            Button(String(localized: "session.delete"), role: .destructive) {
                                pendingDelete = session
                            }
                        }
                }
            }
            .navigationTitle(String(localized: "window.sessions"))
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        String(localized: "sessions.empty"),
                        systemImage: "list.bullet.rectangle",
                        description: Text(String(localized: "sessions.empty.detail"))
                    )
                }
            }
        } detail: {
            if let selection {
                SessionDetailView(session: selection)
            } else {
                ContentUnavailableView(
                    String(localized: "sessions.selectPrompt"),
                    systemImage: "sidebar.left",
                    description: Text(String(localized: "sessions.selectPrompt.detail"))
                )
            }
        }
        .onChange(of: columnVisibility) {
            // Never allow the sidebar to stay collapsed in this window.
            if columnVisibility == .detailOnly { columnVisibility = .all }
        }
        .alert(
            String(localized: "session.delete.confirm.title"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button(String(localized: "common.cancel"), role: .cancel) { pendingDelete = nil }
            Button(String(localized: "session.delete"), role: .destructive) {
                if let pendingDelete {
                    if selection == pendingDelete { selection = nil }
                    modelContext.delete(pendingDelete)
                    try? modelContext.save()
                }
                pendingDelete = nil
            }
        } message: {
            Text(String(localized: "session.delete.confirm.message"))
        }
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    let context = container.mainContext
    for i in 1...3 {
        let s = MeetingSession(
            title: "Reunião de teste \(i)",
            mode: i % 2 == 0 ? .translation : .simple,
            status: .completedWithoutSummary,
            transcriptionLanguage: .portuguese,
            summaryLanguage: .portuguese,
            microphoneEnabled: true,
            systemAudioEnabled: false
        )
        s.startedAt = Date().addingTimeInterval(Double(-i) * 3600)
        s.endedAt = Date().addingTimeInterval(Double(-i) * 3600 + 65)
        context.insert(s)
    }
    try? context.save()
    let appState = AppState(container: container, secretStore: FakePreviewSecretStore())
    return SessionsListView()
        .quettaEnvironment(appState)
        .frame(width: 760, height: 480)
}

/// Preview-only secret store; never touches the Keychain.
private struct FakePreviewSecretStore: SecretStore {
    func save(_ value: String, account: String) throws {}
    func read(account: String) throws -> String? { nil }
    func delete(account: String) throws {}
}

private struct SessionRow: View {
    let session: MeetingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title).font(.headline).lineLimit(1)
            HStack(spacing: 8) {
                Text(session.createdAt, format: .dateTime.day().month().year().hour().minute())
                Text("·")
                Text(MarkdownExporter.formatDuration(session.duration))
                Text("·")
                Text(String(localized: String.LocalizationValue(session.mode.displayNameKey)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(String(localized: String.LocalizationValue(session.status.displayNameKey)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
