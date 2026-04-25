// App/HelixAppState.swift
// Replaces the original HelixViewModel pattern of isLoading + optional index + error.
//
// ChatGPT audit item #10: "Add explicit score suppression states, not just nil/error UI."
// The confidence policy defines cases where scoring is suppressed or estimate-only.
// These are not errors — they are valid physiological confidence states that need
// distinct UI treatment and distinct explanation language.
//
// State machine:
//   App launch → .requestingPermissions
//   Permissions granted, < 14 days data → .learningBaseline(daysRemaining:)
//   14–89 days data, all signals → .fullScore(HelixIndex)
//   14–89 days data, some signals → .partialScore(HelixIndex, missingSignals:)
//   Watch offline > 6 hrs → .suppressedScore(reason:)
//   < 2 usable signals per strand → .suppressedScore(reason:)
//   HealthKit unavailable → .healthKitUnavailable
//   Auth denied → .permissionsDenied
//   Unexpected throw → .error(Error)

import Foundation

enum HelixAppState: Equatable {

    // MARK: — Pre-score states
    case idle
    case requestingPermissions
    case fetchingData

    // MARK: — Baseline maturity
    case learningBaseline(daysRemaining: Int)
    case developingBaseline(daysRecorded: Int, index: HelixIndex)

    // MARK: — Score states
    case fullScore(HelixIndex)
    case partialScore(HelixIndex, missingSignals: [SignalIdentifier])
    case suppressedScore(reason: ScoreSuppressedReason)

    // MARK: — System states
    case healthKitUnavailable
    case permissionsDenied
    case error(String) // Localised description only

    // Equatable conformance for associated-value cases
    static func == (lhs: HelixAppState, rhs: HelixAppState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.requestingPermissions, .requestingPermissions),
             (.fetchingData, .fetchingData),
             (.healthKitUnavailable, .healthKitUnavailable),
             (.permissionsDenied, .permissionsDenied):
            return true
        case (.learningBaseline(let a), .learningBaseline(let b)):
            return a == b
        case (.suppressedScore(let a), .suppressedScore(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        // Index-bearing states: compare by date as a proxy for same calculation
        case (.fullScore(let a), .fullScore(let b)):
            return a.date == b.date
        case (.partialScore(let a, _), .partialScore(let b, _)):
            return a.date == b.date
        case (.developingBaseline(_, let a), .developingBaseline(_, let b)):
            return a.date == b.date
        default:
            return false
        }
    }
}

enum ScoreSuppressedReason: String, Equatable {
    case watchOfflineTooLong          // offline > score_suppressed_if_offline_hours
    case insufficientSignals           // < minimum_signals_to_calculate
    case baselineNotYetActivated       // < minimum_days_to_activate
}
