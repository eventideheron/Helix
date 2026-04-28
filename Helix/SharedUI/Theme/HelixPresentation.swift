// Presentation/HelixPresentation.swift
// ChatGPT audit item #9: "Create a dedicated presentation mapping layer."
//
// The policy is clear that colors are not defined in policy files, but posture
// thresholds and confidence language are policy-driven. The original views hardcoded
// Color.cyan / .orange / .green / .purple directly against domain types.
//
// This layer separates what the domain produces (HelixPosture, ConfidenceLevel)
// from how the UI renders it. If the design language changes, only this file changes.
// If the domain semantics change, only the engine layer changes.

import SwiftUI

// MARK: — Posture presentation

struct PosturePresentation {
    let posture: HelixPosture

    var color: Color {
        switch posture {
        case .pursue:   return HelixTheme.pursueColor
        case .moderate: return HelixTheme.moderateColor
        case .restore:  return HelixTheme.restoreColor
        }
    }

    var headline: String {
        posture.rawValue
    }

    var fallbackSubtext: String {
        switch posture {
        case .pursue:   return "All three strands are in strong alignment."
        case .moderate: return "One strand is recovering. Moderate effort is appropriate."
        case .restore:  return "Your triple helix needs time to recover."
        }
    }
}

// MARK: — Confidence presentation

struct ConfidencePresentation {
    let level: ConfidenceLevel

    var color: Color {
        switch level {
        case .high:   return HelixTheme.confidenceHigh
        case .medium: return HelixTheme.confidenceMedium
        case .low:    return HelixTheme.confidenceLow
        }
    }

    var indicator: String {
        switch level {
        case .high:   return "●●● Confident"
        case .medium: return "●●○ Estimated"
        case .low:    return "●○○ Limited"
        }
    }

    /// Filled-dot count for triple-dot indicator (display-only; same semantics as `indicator`).
    var filledDotCount: Int {
        switch level {
        case .high:   return 3
        case .medium: return 2
        case .low:    return 1
        }
    }
}

// MARK: — Strand presentation

struct StrandPresentation {
    let strand: HelixStrand

    var color: Color {
        switch strand {
        case .sleep:    return HelixTheme.sleepColor
        case .load:     return HelixTheme.loadColor
        case .recovery: return HelixTheme.recoveryColor
        }
    }

    var displayLabel: String {
        strand.displayLabel
    }
}

// MARK: — App state presentation

struct AppStatePresentation {
    let state: HelixAppState

    var shouldShowScore: Bool {
        switch state {
        case .fullScore, .partialScore, .developingBaseline: return true
        default: return false
        }
    }

    var shouldShowSuppressedMessage: Bool {
        if case .suppressedScore = state { return true }
        return false
    }

    var statusMessage: String {
        switch state {
        case .idle, .requestingPermissions, .fetchingData:
            return "Loading your Helix data…"
        case .learningBaseline(let days):
            return "Helix is learning your baseline. \(days) day\(days == 1 ? "" : "s") until your first full score."
        case .developingBaseline:
            return "Baseline developing — scores become more accurate as your history grows."
        case .suppressedScore(let reason):
            return suppressedMessage(for: reason)
        case .healthKitUnavailable:
            return "Apple Health is not available on this device."
        case .permissionsDenied:
            return "Health data access is required. Please enable it in Settings → Privacy → Health."
        case .error(let msg):
            return "An error occurred: \(msg)"
        case .fullScore, .partialScore:
            return ""
        }
    }

    private func suppressedMessage(for reason: ScoreSuppressedReason) -> String {
        switch reason {
        case .watchOfflineTooLong:
            return "Watch was not worn for part of the night. Score reflects available data only."
        case .insufficientSignals:
            return "Too few signals available to calculate a reliable score today."
        case .baselineNotYetActivated:
            return "Not enough data yet. Keep wearing your watch to build your baseline."
        }
    }
}
