//
//  PermissionRow.swift
//  quetta
//
//  Reusable row showing a permission's status with request / open-settings actions.
//

import SwiftUI

struct PermissionRow: View {
    @Environment(PermissionService.self) private var permissions

    let kind: PermissionKind

    var body: some View {
        let status = permissions.status(for: kind)
        HStack(alignment: .top, spacing: 12) {
            statusIcon(status)
                .font(.title3)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: String.LocalizationValue(kind.titleKey)))
                    .font(.headline)
                Text(String(localized: String.LocalizationValue(kind.explanationKey)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            actionButton(status)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actionButton(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Label(String(localized: "permission.granted"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.iconOnly)
                .font(.title3)
        case .notDetermined:
            Button(String(localized: "permission.allow")) { request() }
        case .denied, .restricted:
            Button(String(localized: "permission.openSettings")) {
                permissions.openSettings(for: kind)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied, .restricted:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .notDetermined:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    private func request() {
        Task {
            switch kind {
            case .microphone: await permissions.requestMicrophone()
            case .speech: await permissions.requestSpeech()
            case .screenCapture: await permissions.requestScreenCapture()
            case .notifications: await permissions.requestNotifications()
            }
        }
    }
}
