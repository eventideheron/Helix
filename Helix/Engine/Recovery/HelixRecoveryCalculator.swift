// Engine/HelixRecoveryCalculator.swift
// v1.1 fixes:
//   - redistributeWeights() previously ignored the `missing` parameter and
//     simply normalized present weights. This produced the correct arithmetic
//     output but diverged from the policy's described proportional redistribution
//     and from HelixConfidenceEngine's correct implementation. Both now delegate
//     to the same shared logic.
//   - All score clamps use .clampedToHelixScore() for consistency.

import Foundation

class HelixRecoveryCalculator {

    private let policy: RecoveryConfig
    private let confidenceEngine: HelixConfidenceEngine

    init(policy: RecoveryConfig, confidenceEngine: HelixConfidenceEngine) {
        self.policy = policy
        self.confidenceEngine = confidenceEngine
    }

    func calculate(
        todayHRV: Double?,
        todayRHR: Double?,
        minSleepHR: Double?,
        overnightRR: Double?,
        spo2Rolling7Night: Double?,
        baselines: [SignalIdentifier: PersonalBaseline]
    ) -> (score: Double, missing: [SignalIdentifier]) {

        let w = policy.weights
        var originalWeights  = [SignalIdentifier: Double]()
        var scores           = [SignalIdentifier: Double]()
        var missing          = [SignalIdentifier]()

        // MARK: HRV Component
        if let hrv = todayHRV,
           let baseline = baselines[.hrv]?.value,
           baseline > 0 {
            let deltaRatio = (hrv - baseline) / baseline
            let score = (policy.hrv.midpoint + deltaRatio * policy.hrv.sensitivity)
                .clampedToHelixScore()
            scores[.hrv]         = score
            originalWeights[.hrv] = w.hrv
        } else {
            missing.append(.hrv)
        }

        // MARK: Resting HR Component
        if let rhr = todayRHR,
           let baseline = baselines[.restingHR]?.value {
            let delta = rhr - baseline
            let score = (100.0 - delta * policy.restingHr.costPerBpmAboveBaseline)
                .clampedToHelixScore()
            scores[.restingHR]          = score
            originalWeights[.restingHR] = w.restingHr
        } else {
            missing.append(.restingHR)
        }

        // MARK: Overnight HR Dip Component
        if let minHR = minSleepHR,
           let baseline = baselines[.restingHR]?.value {
            let dipBPM = baseline - minHR
            let score = (dipBPM * policy.overnightHrDip.scoreMultiplier)
                .clampedToHelixScore()
            scores[.overnightHRDip]          = score
            originalWeights[.overnightHRDip] = w.overnightHrDip
        } else {
            missing.append(.overnightHRDip)
        }

        // MARK: Respiratory + SpO2 modifier
        if let rr = overnightRR,
           let baseline = baselines[.overnightRespiratory]?.value {
            let rrDelta  = abs(rr - baseline)
            var rrScore  = (100.0 - rrDelta * policy.respiratory.sensitivity)
                .clampedToHelixScore()
            if let spo2 = spo2Rolling7Night {
                rrScore = (rrScore * spo2Modifier(for: spo2)).clampedToHelixScore()
            }
            scores[.respiratoryRecovery]          = rrScore
            originalWeights[.respiratoryRecovery] = w.respiratory
        } else {
            missing.append(.respiratoryRecovery)
        }

        // MARK: Proportional weight redistribution (shared logic via ConfidenceEngine)
        let adjustedWeights = confidenceEngine.redistributedWeights(
            originalWeights: originalWeights,
            missingSignals: missing
        )

        let composite = scores.reduce(0.0) { acc, pair in
            acc + pair.value * (adjustedWeights[pair.key] ?? 0)
        }

        return (composite.clampedToHelixScore(), missing)
    }

    // MARK: — SpO2 modifier (reads thresholds and modifiers from policy)
    private func spo2Modifier(for spo2: Double) -> Double {
        let t = policy.spo2.thresholds
        let m = policy.spo2.modifiers
        switch spo2 {
        case t.nominal...:              return m.nominal
        case t.caution..<t.nominal:    return m.caution
        case t.concern..<t.caution:    return m.concern
        default:                        return m.critical
        }
    }
}
