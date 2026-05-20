// Engine/HelixConfidenceEngine.swift
// v1.2: Full policy-driven confidence evaluation.
//
// ChatGPT audit item #3: "Move confidence from ad hoc logic to true policy-driven evaluation."
// The original engine only checked whether primary signals were present. It ignored:
//   - minimum_signals_present thresholds per confidence tier
//   - watch_offline behavior
//   - graceful degradation minimum
//   - per-strand vs composite confidence
//
// New evaluation flow (matching the policy):
//   1. Assess signal availability (valid + present)
//   2. Check watch-offline state
//   3. Determine confidence tier from primary-signals-present rule + minimum count
//   4. Determine if suppression applies
//   5. Return full ConfidenceResult for per-strand and composite decisions
//
// ChatGPT audit item #4: "Create one shared, tested weight redistribution utility."
// redistributedWeights() is the single implementation. All engines call this.
// HelixRecoveryCalculator no longer has its own copy.

import Foundation

struct ConfidenceResult {
    let level: ConfidenceLevel
    let missingSignals: [SignalIdentifier]
    let suppressScore: Bool
    let suppressionReason: ScoreSuppressedReason?
    let explanationKey: String    // Maps to helix_explanation_policy confidence_language
}

class HelixConfidenceEngine {

    private let policy: HelixConfidencePolicy

    init(policy: HelixConfidencePolicy) {
        self.policy = policy
    }

    // MARK: — Primary API: per-strand confidence evaluation

    func evaluate(
        presentSignals: [SignalIdentifier],
        validSignals: [SignalIdentifier],
        allExpectedSignals: [SignalIdentifier],
        watchOfflineHours: Double = 0,
        consecutiveHRVAbsentDays: Int = 0
    ) -> ConfidenceResult {

        let missing = allExpectedSignals.filter {
            !presentSignals.contains($0) || !validSignals.contains($0)
        }

        let presentCount = allExpectedSignals.count - missing.count

        // Watch-offline suppression check
        let watchConfig = policy.watchOffline
        if watchOfflineHours >= watchConfig.scoreSupressedIfOfflineHours {
            return ConfidenceResult(
                level: .low,
                missingSignals: missing,
                suppressScore: true,
                suppressionReason: .watchOfflineTooLong,
                explanationKey: "watch_offline"
            )
        }

        // Insufficient signals for calculation
        let minToCalculate = policy.gracefulDegradation.minimumSignalsToCalculate
        if presentCount < minToCalculate {
            return ConfidenceResult(
                level: .low,
                missingSignals: missing,
                suppressScore: true,
                suppressionReason: .insufficientSignals,
                explanationKey: "low"
            )
        }

        // Determine confidence tier
        let highConfig   = policy.confidenceLevels.high
        let mediumConfig = policy.confidenceLevels.medium

        let primaryMissing = missing.filter {
            highConfig.primarySignalsRequired.contains($0.rawValue)
        }

        let level: ConfidenceLevel
        let explanationKey: String

        let highThreshold = Int(ceil(Double(allExpectedSignals.count) * highConfig.minimumSignalsPresentPercent))
        if primaryMissing.isEmpty && presentCount >= highThreshold {
            level          = .high
            explanationKey = "high"
        } else if presentCount >= mediumConfig.minimumSignalsPresent {
            level = .medium
            // When nothing is missing, generic "medium" must not imply unavailable data (e.g. recovery
            // cannot reach high while policy requires five signals but the strand only expects four).
            if missing.isEmpty {
                explanationKey = "medium_confidence_full_signals"
            } else {
                explanationKey = missingExplanationKey(for: missing, consecutiveHRVAbsentDays: consecutiveHRVAbsentDays)
            }
        } else {
            level          = .low
            explanationKey = "low"
        }

        return ConfidenceResult(
            level: level,
            missingSignals: missing,
            suppressScore: false,
            suppressionReason: nil,
            explanationKey: explanationKey
        )
    }

    // MARK: — Composite confidence (lowest of three strands)
    // Using Comparable conformance on ConfidenceLevel

    func compositeConfidence(
        sleep: ConfidenceLevel,
        load: ConfidenceLevel,
        recovery: ConfidenceLevel
    ) -> ConfidenceLevel {
        Swift.min(sleep, Swift.min(load, recovery))
    }

    // MARK: — Proportional weight redistribution
    // Single authoritative implementation. All engines call this.
    //
    // Missing signal weight is redistributed proportionally to remaining signals
    // based on their share of the remaining total weight.
    // This preserves relative importance of remaining signals rather than
    // artificially equalising them.
    //
    // Formula: adjusted_i = original_i + (freed × original_i / Σ_remaining)

    func redistributedWeights(
        originalWeights: [SignalIdentifier: Double],
        missingSignals: [SignalIdentifier]
    ) -> [SignalIdentifier: Double] {

        var remaining = originalWeights
        var freedWeight = 0.0

        for signal in missingSignals {
            freedWeight += remaining.removeValue(forKey: signal) ?? 0
        }

        guard !remaining.isEmpty else { return [:] }

        let remainingTotal = remaining.values.reduce(0, +)
        guard remainingTotal > 0 else { return remaining }

        return remaining.mapValues { originalWeight in
            originalWeight + (freedWeight * (originalWeight / remainingTotal))
        }
    }

    // MARK: — Private helpers

    private func missingExplanationKey(
        for missing: [SignalIdentifier],
        consecutiveHRVAbsentDays: Int = 0
    ) -> String {
        if missing.contains(.hrv) {
            return consecutiveHRVAbsentDays >= 7 ? "hrv_device_unavailable" : "missing_hrv"
        }
        if missing.contains(.deepSleepPercent) ||
           missing.contains(.remSleepPercent)  { return "missing_staging" }
        if missing.contains(.wristTemperature) { return "missing_temperature" }
        return "medium"
    }
}
