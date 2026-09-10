//
//  WindowManager.swift
//  quetta
//
//  Manages regular app windows (sessions list, new-session setup) via AppKit
//  NSWindowController so they open reliably regardless of the app's activation
//  policy state. Unlike SwiftUI's openWindow, this gives us direct control over
//  window lifecycle and activation.
//

import AppKit
import SwiftUI

@MainActor
final class WindowManager {

    private var sessionsWindow: NSWindow?
    private var sessionSetupWindow: NSWindow?

    // MARK: - Sessions

    func showSessions(appState: AppState) {
        if let window = sessionsWindow {
            // Window exists (even if hidden after user closed it) — just re-show.
            present(window)
            return
        }
        let hosting = NSHostingController(
            rootView: SessionsListView().quettaEnvironment(appState)
        )
        let window = makeWindow(
            title: String(localized: "window.sessions"),
            contentViewController: hosting,
            size: NSSize(width: 860, height: 520),
            minSize: NSSize(width: 720, height: 460),
            resizable: true
        )
        sessionsWindow = window
        present(window)
    }

    // MARK: - Session Setup

    func showSessionSetup(appState: AppState) {
        if let window = sessionSetupWindow, window.isVisible {
            present(window)
            return
        }
        // Always create a fresh hosting controller so form state resets between uses.
        let hosting = NSHostingController(
            rootView: SessionSetupView().quettaEnvironment(appState)
        )
        let window = makeWindow(
            title: String(localized: "window.newSession"),
            contentViewController: hosting,
            size: NSSize(width: 560, height: 560),
            minSize: NSSize(width: 560, height: 560),
            resizable: false
        )
        sessionSetupWindow = window
        present(window)
    }

    // MARK: - Helpers

    private func makeWindow(
        title: String,
        contentViewController: NSViewController,
        size: NSSize,
        minSize: NSSize,
        resizable: Bool
    ) -> NSWindow {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { styleMask.insert(.resizable) }

        let window = NSWindow(contentViewController: contentViewController)
        window.title = title
        window.styleMask = styleMask
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.setContentSize(size)
        window.center()
        return window
    }

    func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
