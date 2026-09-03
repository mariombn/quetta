//
//  NotificationService.swift
//  quetta
//
//  Posts local notifications (e.g. when a summary finishes).
//

import Foundation
import UserNotifications

@MainActor
final class NotificationService {

    func notifySummaryReady(sessionTitle: String) {
        post(
            title: String(localized: "notification.summaryReady.title"),
            body: String(localized: "notification.summaryReady.body \(sessionTitle)")
        )
    }

    func notifySummaryFailed(sessionTitle: String) {
        post(
            title: String(localized: "notification.summaryFailed.title"),
            body: String(localized: "notification.summaryFailed.body \(sessionTitle)")
        )
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
