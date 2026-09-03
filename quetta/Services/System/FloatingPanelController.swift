//
//  FloatingPanelController.swift
//  quetta
//
//  Manages the floating NSPanel that hosts the live session UI (spec §6.2).
//  Bottom-centered by default, draggable, non-activating, shown on all Spaces,
//  and it remembers its last valid position clamped to the visible screen.
//

import AppKit
import SwiftUI

/// A non-activating floating panel that can still host interactive controls.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController {

    static let width: CGFloat = 760
    static let minHeight: CGFloat = 260
    static let defaultHeight: CGFloat = 340

    private var panel: FloatingPanel?
    private let originDefaultsKey = "floatingPanel.origin"

    var isVisible: Bool { panel?.isVisible ?? false }

    func show<Content: View>(@ViewBuilder content: () -> Content) {
        let hosting = NSHostingController(rootView: AnyView(content()))

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = hosting

        let size = NSSize(width: Self.width, height: Self.defaultHeight)
        let origin = savedOrClampedOrigin(for: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Panel construction

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.defaultHeight),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = FloatingPanelDelegate.shared
        return panel
    }

    // MARK: - Positioning

    private func savedOrClampedOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin: NSPoint
        if let saved = savedOrigin() {
            origin = saved
        } else {
            // Bottom-centered default.
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + 40
            )
        }

        origin = clamp(origin: origin, size: size, into: visible)
        return origin
    }

    private func clamp(origin: NSPoint, size: NSSize, into visible: NSRect) -> NSPoint {
        var point = origin
        point.x = min(max(point.x, visible.minX), visible.maxX - size.width)
        point.y = min(max(point.y, visible.minY), visible.maxY - size.height)
        return point
    }

    private func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "\(originDefaultsKey).x") != nil else { return nil }
        let x = defaults.double(forKey: "\(originDefaultsKey).x")
        let y = defaults.double(forKey: "\(originDefaultsKey).y")
        return NSPoint(x: x, y: y)
    }

    func persistCurrentOrigin() {
        guard let frame = panel?.frame else { return }
        let defaults = UserDefaults.standard
        defaults.set(Double(frame.origin.x), forKey: "\(originDefaultsKey).x")
        defaults.set(Double(frame.origin.y), forKey: "\(originDefaultsKey).y")
    }
}

/// Persists panel position whenever the user finishes moving it.
private final class FloatingPanelDelegate: NSObject, NSWindowDelegate {
    static let shared = FloatingPanelDelegate()

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let defaults = UserDefaults.standard
        defaults.set(Double(window.frame.origin.x), forKey: "floatingPanel.origin.x")
        defaults.set(Double(window.frame.origin.y), forKey: "floatingPanel.origin.y")
    }
}
