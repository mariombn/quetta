//
//  SessionStateMachine.swift
//  quetta
//
//  Pure, testable validator for session lifecycle transitions (spec §13).
//

import Foundation

enum SessionStateMachine {

    /// Allowed transitions from each status.
    static func allowedTransitions(from status: SessionStatus) -> Set<SessionStatus> {
        switch status {
        case .draft:
            return [.active, .failed]
        case .active:
            return [.paused, .finalizing, .failed]
        case .paused:
            return [.active, .finalizing, .failed]
        case .finalizing:
            return [.generatingSummary, .completedWithoutSummary, .failed]
        case .generatingSummary:
            // On success -> completed; on failure after text preserved -> completedWithoutSummary.
            return [.completed, .completedWithoutSummary]
        case .completed, .completedWithoutSummary, .failed:
            return []
        }
    }

    static func canTransition(from: SessionStatus, to: SessionStatus) -> Bool {
        allowedTransitions(from: from).contains(to)
    }

    /// Returns the next status if valid, otherwise throws.
    @discardableResult
    static func validate(from: SessionStatus, to: SessionStatus) throws -> SessionStatus {
        guard canTransition(from: from, to: to) else {
            throw SessionStateError.invalidTransition(from: from, to: to)
        }
        return to
    }
}

enum SessionStateError: LocalizedError, Equatable {
    case invalidTransition(from: SessionStatus, to: SessionStatus)

    var errorDescription: String? {
        switch self {
        case let .invalidTransition(from, to):
            return "Invalid session transition from \(from.rawValue) to \(to.rawValue)."
        }
    }
}
