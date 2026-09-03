//
//  PermissionService.swift
//  quetta
//
//  Tracks and requests the four permissions the app is allowed to use:
//  microphone, speech recognition, screen (audio) capture and local notifications.
//

import Foundation
import AVFoundation
import Speech
import CoreGraphics
import AppKit
import UserNotifications

enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case granted
}

enum PermissionKind: CaseIterable, Identifiable, Sendable {
    case microphone
    case speech
    case screenCapture
    case notifications

    var id: String { titleKey }

    var titleKey: String {
        switch self {
        case .microphone: return "permission.microphone.title"
        case .speech: return "permission.speech.title"
        case .screenCapture: return "permission.screen.title"
        case .notifications: return "permission.notifications.title"
        }
    }

    var explanationKey: String {
        switch self {
        case .microphone: return "permission.microphone.explanation"
        case .speech: return "permission.speech.explanation"
        case .screenCapture: return "permission.screen.explanation"
        case .notifications: return "permission.notifications.explanation"
        }
    }

    /// Deep link to the relevant System Settings privacy pane.
    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speech:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .screenCapture:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .notifications:
            return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        }
    }
}

@MainActor
@Observable
final class PermissionService {

    var microphone: PermissionStatus = .notDetermined
    var speech: PermissionStatus = .notDetermined
    var screenCapture: PermissionStatus = .notDetermined
    var notifications: PermissionStatus = .notDetermined

    init() {
        refreshAll()
    }

    func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .microphone: return microphone
        case .speech: return speech
        case .screenCapture: return screenCapture
        case .notifications: return notifications
        }
    }

    func refreshAll() {
        microphone = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        speech = Self.map(SFSpeechRecognizer.authorizationStatus())
        screenCapture = CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        Task { await refreshNotifications() }
    }

    func refreshNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notifications = .granted
        case .denied:
            notifications = .denied
        case .notDetermined:
            notifications = .notDetermined
        @unknown default:
            notifications = .notDetermined
        }
    }

    // MARK: - Requests

    @discardableResult
    func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = granted ? .granted : .denied
        return microphone
    }

    @discardableResult
    func requestSpeech() async -> PermissionStatus {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        speech = Self.map(status)
        return speech
    }

    @discardableResult
    func requestScreenCapture() async -> PermissionStatus {
        // Requesting must happen off the main thread to avoid blocking the UI.
        let granted = await Task.detached { CGRequestScreenCaptureAccess() }.value
        screenCapture = granted ? .granted : .denied
        return screenCapture
    }

    @discardableResult
    func requestNotifications() async -> PermissionStatus {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            notifications = granted ? .granted : .denied
        } catch {
            notifications = .denied
        }
        return notifications
    }

    func openSettings(for kind: PermissionKind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Mapping

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
