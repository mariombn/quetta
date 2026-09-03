//
//  MenuBarLabel.swift
//  quetta
//
//  The status-bar item content: neutral icon when idle, red dot + elapsed while
//  active, yellow when paused, red when in error (spec §6.1).
//

import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        HStack(spacing: 4) {
            switch state {
            case .idle:
                Image(systemName: "waveform")
            case .active:
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(MarkdownExporter.formatDuration(coordinator.elapsed))
                    .monospacedDigit()
            case .paused:
                Circle().fill(.yellow).frame(width: 8, height: 8)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private enum LabelState { case idle, active, paused, error }

    private var state: LabelState {
        guard let session = coordinator.currentSession else {
            return coordinator.lastErrorMessage == nil ? .idle : .idle
        }
        switch session.status {
        case .active: return coordinator.networkInterrupted ? .error : .active
        case .paused: return coordinator.networkInterrupted ? .error : .paused
        case .failed: return .error
        default: return .active
        }
    }
}
