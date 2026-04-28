// Policy/HelixPolicyValidator.swift
// ChatGPT audit item #12: "Add startup policy validation."
//
// Validates policy structure at launch before any scoring begins.
// Catches bad policy files immediately rather than producing wrong scores silently.
// Call HelixPolicyValidator.validate(bundle:) from HelixViewModel.init().
//
// Checks performed:
//   - Non-empty policy_version on each bundled policy (decode proves structure)
//   - Weight sums are correct where required (±0.001 tolerance)
//   - Threshold ordering is logically valid
//   - Required keys are present
//   - ACWR bands are contiguous and ordered

import Foundation

enum PolicyValidationError: Error, LocalizedError {
    case weightSumInvalid(strand: String, sum: Double)
    case thresholdOrderingInvalid(context: String, description: String)
    case missingRequiredKey(file: String, key: String)

    var errorDescription: String? {
        switch self {
        case .weightSumInvalid(let s, let sum):
            return "\(s) weights sum to \(String(format: "%.4f", sum)), expected 1.0."
        case .thresholdOrderingInvalid(let ctx, let desc):
            return "Threshold ordering error in \(ctx): \(desc)"
        case .missingRequiredKey(let f, let key):
            return "Missing required key '\(key)' in \(f)."
        }
    }
}

struct HelixPolicyValidator {

    static let weightTolerance = 0.001

    static func validate(bundle: HelixPolicyBundle) throws {
        try validateCorePolicy(bundle.core)
        try validateConfidencePolicy(bundle.confidence)
        try validateExplanationPolicy(bundle.explanation)
        try validateHistoryPolicy(bundle.history)
        try validateCrossStrandPolicy(bundle.crossStrand)
    }

    // MARK: — policy_version

    private static func requireNonEmptyPolicyVersion(_ version: String, file: String) throws {
        guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PolicyValidationError.missingRequiredKey(file: file, key: "policy_version")
        }
    }

    // MARK: — Core policy

    private static func validateCorePolicy(_ policy: HelixCorePolicy) throws {
        try requireNonEmptyPolicyVersion(policy.policyVersion, file: "helix_policy")

        // Sleep strand weight sum
        let sw = policy.strandSleep.weights
        let sleepSum = sw.duration + sw.deepSleep + sw.remSleep +
                       sw.disturbance + sw.consistency + sw.thermal + sw.respiratory
        guard abs(sleepSum - 1.0) < weightTolerance else {
            throw PolicyValidationError.weightSumInvalid(strand: "Sleep", sum: sleepSum)
        }

        // Load strand weight sum
        let lw = policy.strandLoad.weights
        let loadSum = lw.acwr + lw.acuteLoad + lw.activityCompletion + lw.hrElevationPenalty
        guard abs(loadSum - 1.0) < weightTolerance else {
            throw PolicyValidationError.weightSumInvalid(strand: "Load", sum: loadSum)
        }

        // Recovery strand weight sum
        let rw = policy.strandRecovery.weights
        let recoverySum = rw.hrv + rw.restingHr + rw.overnightHrDip + rw.respiratory
        guard abs(recoverySum - 1.0) < weightTolerance else {
            throw PolicyValidationError.weightSumInvalid(strand: "Recovery", sum: recoverySum)
        }

        // Helix Index weight sum
        let iw = policy.helixIndex.weights
        let indexSum = iw.sleep + iw.recovery + iw.load
        guard abs(indexSum - 1.0) < weightTolerance else {
            throw PolicyValidationError.weightSumInvalid(strand: "Helix Index", sum: indexSum)
        }

        // Recovery gate: severe threshold must be lower than critical
        let gate = policy.helixIndex.recoveryGate
        guard gate.severeThreshold < gate.criticalThreshold else {
            throw PolicyValidationError.thresholdOrderingInvalid(
                context: "recovery_gate",
                description: "severe_threshold (\(gate.severeThreshold)) must be < critical_threshold (\(gate.criticalThreshold))."
            )
        }

        // Recovery gate: severe multiplier must be weaker (lower) than critical
        guard gate.severeMultiplier < gate.criticalMultiplier else {
            throw PolicyValidationError.thresholdOrderingInvalid(
                context: "recovery_gate",
                description: "severe_multiplier (\(gate.severeMultiplier)) must be < critical_multiplier (\(gate.criticalMultiplier)) since severe is the worse state."
            )
        }

        // Posture thresholds: pursue > moderate > restore (0)
        let pt = policy.helixIndex.postureThresholds
        guard pt.pursue > pt.moderate && pt.moderate > pt.restore else {
            throw PolicyValidationError.thresholdOrderingInvalid(
                context: "posture_thresholds",
                description: "Expected pursue > moderate > restore."
            )
        }

        // ACWR bands: ordering
        let acwr = policy.strandLoad.acwrScoring
        guard acwr.undertrainingCeiling < acwr.optimalLow &&
              acwr.optimalLow < acwr.optimalHigh &&
              acwr.optimalHigh < acwr.cautionCeiling else {
            throw PolicyValidationError.thresholdOrderingInvalid(
                context: "acwr_scoring",
                description: "Expected undertraining_ceiling < optimal_low < optimal_high < caution_ceiling."
            )
        }

        // SpO2 thresholds: nominal > caution > concern
        let spo2 = policy.strandRecovery.spo2.thresholds
        guard spo2.nominal > spo2.caution && spo2.caution > spo2.concern else {
            throw PolicyValidationError.thresholdOrderingInvalid(
                context: "spo2_thresholds",
                description: "Expected nominal > caution > concern."
            )
        }
    }

    // MARK: — Confidence policy

    private static func validateConfidencePolicy(_ policy: HelixConfidencePolicy) throws {
        try requireNonEmptyPolicyVersion(policy.policyVersion, file: "helix_confidence_policy")

        // High confidence uses a percent threshold; validate it is in range
        let high   = policy.confidenceLevels.high
        _ = policy.confidenceLevels.medium
        guard high.minimumSignalsPresentPercent > 0.0 && high.minimumSignalsPresentPercent <= 1.0 else {
            throw PolicyValidationError.thresholdOrderingInvalid(
                context: "confidence_levels",
                description: "high.minimum_signals_present_percent must be between 0.0 and 1.0."
            )
        }

        // Minimum signals to calculate must be positive
        guard policy.gracefulDegradation.minimumSignalsToCalculate > 0 else {
            throw PolicyValidationError.thresholdOrderingInvalid(
                context: "graceful_degradation",
                description: "minimum_signals_to_calculate must be > 0."
            )
        }
    }

    // MARK: — History policy

    private static func validateHistoryPolicy(_ policy: HelixHistoryPolicy) throws {
        try requireNonEmptyPolicyVersion(policy.policyVersion, file: "helix_history_policy")
        let s = policy.seasonalDetection
        guard s.exactAnchorDayWeight >= s.edgeOfWindowWeight else {
            throw PolicyValidationError.thresholdOrderingInvalid(
                context: "seasonal_detection",
                description: "exact_anchor_day_weight must be >= edge_of_window_weight for linear decay."
            )
        }
        guard s.comparisonWindowDaysBeforeAnchor > 0, s.comparisonWindowDaysAfterAnchor > 0 else {
            throw PolicyValidationError.thresholdOrderingInvalid(
                context: "seasonal_detection",
                description: "comparison window days must be positive."
            )
        }
    }

    // MARK: — Explanation policy

    private static func validateExplanationPolicy(_ policy: HelixExplanationPolicy) throws {
        try requireNonEmptyPolicyVersion(policy.policyVersion, file: "helix_explanation_policy")
        // Language template presence checks could be added here
        // as the explanation engine is built out
    }

    // MARK: — Cross-strand policy

    private static func validateCrossStrandPolicy(_ policy: CrossStrandPolicy) throws {
        try requireNonEmptyPolicyVersion(policy.policyVersion, file: "helix_cross_strand_policy")
    }
}
