//
//  quettaApp.swift
//  quetta
//
//  App entry point: a menu-bar app (no main window) with Settings, Onboarding and
//  Sessions windows, backed by SwiftData and the shared AppState.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct quettaApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

        Settings {
            SettingsView()
                .quettaEnvironment(appState)
                .frame(width: 620, height: 480)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as accessory so no Dock icon appears when no windows are open.
        NSApp.setActivationPolicy(.accessory)

        // Promote to regular when any titled window becomes key so the app
        // appears in Command+Tab and windows behave normally.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  !(window is NSPanel),
                  window.styleMask.contains(.titled) else { return }
            NSApp.setActivationPolicy(.regular)
        }

        // Return to accessory when all titled windows are closed.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let hasRegularWindows = NSApp.windows.contains {
                    !($0 is NSPanel) && $0.styleMask.contains(.titled) && $0.isVisible
                }
                if !hasRegularWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}

// MARK: - Window IDs

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
