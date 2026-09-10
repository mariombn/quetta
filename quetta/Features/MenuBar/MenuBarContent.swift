//
//  MenuBarContent.swift
//  quetta
//
//  The status-bar menu (spec §6.1). Order: state, new session / show panel,
//  pause-resume + finish, sessions, settings, quit.
//

import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            // 1. Current state
            Text(stateLabel)

            Divider()

            // 2. New session (idle) or show/hide panel (active)
            if let session = coordinator.currentSession, !session.status.isTerminal {
                Button(coordinator.panelVisible
                       ? String(localized: "menu.hidePanel")
                       : String(localized: "menu.showPanel")) {
                    coordinator.togglePanel()
                }

                // 3. Pause / resume + finish
                if session.status == .active {
                    Button(String(localized: "menu.pause")) { coordinator.pause() }
                } else if session.status == .paused {
                    Button(String(localized: "menu.resume")) { coordinator.resume() }
                }
                Button(String(localized: "menu.finish")) { coordinator.finalize() }
            } else {
                Button(String(localized: "menu.newSession")) {
                    appState.showSessionSetup()
                }
            }

            Divider()

            // 4. Sessions
            Button(String(localized: "menu.sessions")) {
                appState.showSessions()
            }

            // 5. Settings
            Button(String(localized: "menu.settings")) {
                activateAndOpenSettings()
            }

            Divider()

            // 6. Quit
            Button(String(localized: "menu.quit")) {
                NSApplication.shared.terminate(nil)
            }
        }
        .task {
            if !preferences.hasCompletedOnboarding {
                activateAndOpen(WindowID.onboarding)
            }
        }
    }

    private var stateLabel: String {
        if coordinator.networkInterrupted {
            return String(localized: "state.interrupted")
        }
        guard let session = coordinator.currentSession else {
            return String(localized: "state.idle")
        }
        let mode = String(localized: String.LocalizationValue(session.mode.displayNameKey))
        let status = String(localized: String.LocalizationValue(session.status.displayNameKey))
        return "\(status) · \(mode)"
    }

    private func activateAndOpenSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .filter { !($0 is NSPanel) && $0.styleMask.contains(.titled) && $0.isVisible }
                .forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }

    private func activateAndOpen(_ id: String) {
        // Switch to regular policy so the window becomes key and appears in Command+Tab.
        NSApp.setActivationPolicy(.regular)
        openWindow(id: id)
        // After the menu dismisses, activate the app and bring all regular windows to front.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .filter { !($0 is NSPanel) && $0.styleMask.contains(.titled) && $0.isVisible }
                .forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }
}
