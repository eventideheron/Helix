// Models/HelixExtensions.swift
// Centralised score clamping and shared calculation context types.

import Foundation

// MARK: — Score clamping
extension Double {
    /// Clamps a computed strand or index score to the valid 0–100 output range.
    /// Use only for final scores — not for intermediate deltas, ratios, or modifiers.
    func clampedToHelixScore() -> Double {
        Swift.min(100.0, Swift.max(0.0, self))
    }
}

// MARK: — Load calculation context
// Carries user age for Tanaka max HR formula.
// ageIsEstimated = true when HealthKit date of birth was unavailable and the
// 30-year fallback is in use. Consumers should cap strand confidence at .medium
// and surface the missing_age explanation string when this flag is set.
struct LoadCalculationContext {
    let userAge: Double
    let ageIsEstimated: Bool

    static let fallback = LoadCalculationContext(userAge: 30.0, ageIsEstimated: true)

    var maxHeartRate: Double {
        208.0 - (0.7 * userAge)
    }
}
