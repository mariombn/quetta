//
//  quettaApp.swift
//  quetta
//
//  App entry point: a menu-bar app (no main window) with Settings, Onboarding and
//  Sessions windows, backed by SwiftData and the shared AppState.
//

import SwiftUI
import SwiftData

@main
struct quettaApp: App {

    @State private var appState: AppState

    init() {
        let container = PersistenceController.makeContainer()
        _appState = State(initialValue: AppState(container: container))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .quettaEnvironment(appState)
        } label: {
            MenuBarLabel()
                .environment(appState.coordinator)
        }
        .menuBarExtraStyle(.menu)

        Window(String(localized: "window.onboarding"), id: WindowID.onboarding) {
            OnboardingView()
                .quettaEnvironment(appState)
                .frame(minWidth: 560, minHeight: 520)
        }
        .windowResizability(.contentSize)

        Window(String(localized: "window.sessions"), id: WindowID.sessions) {
            SessionsListView()
                .quettaEnvironment(appState)
                .frame(minWidth: 720, minHeight: 460)
        }

        Window(String(localized: "window.newSession"), id: WindowID.sessionSetup) {
            SessionSetupView()
                .quettaEnvironment(appState)
                .frame(width: 560, height: 560)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .quettaEnvironment(appState)
                .frame(width: 620, height: 480)
        }
    }
}

enum WindowID {
    static let onboarding = "onboarding"
    static let sessions = "sessions"
    static let sessionSetup = "sessionSetup"
}

extension View {
    /// Injects the shared environment (state, coordinator, preferences, services,
    /// model container) plus the resolved locale and color scheme.
    func quettaEnvironment(_ appState: AppState) -> some View {
        self
            .environment(appState)
            .environment(appState.coordinator)
            .environment(appState.preferences)
            .environment(appState.permissions)
            .environment(appState.connectivity)
            .environment(appState.registry)
            .modelContainer(appState.container)
            .environment(\.locale, Locale(identifier: appState.preferences.localeIdentifierForUI ?? Locale.current.identifier))
            .preferredColorScheme(appState.preferences.colorScheme)
    }
}
