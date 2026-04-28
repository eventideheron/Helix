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
    private let explanationEngine: HelixExplanationEngine
    private let restingHrExplanationThresholds: RHRThresholds?
    /// HRV explanation routing: percent-delta bands from `helix_explanation_policy.signal_thresholds.hrv` (ratio-form delta).
    private let hrvExplanationThresholds: HRVThresholds?

    init(
        policy: RecoveryConfig,
        confidenceEngine: HelixConfidenceEngine,
        explanationEngine: HelixExplanationEngine,
        restingHrExplanationThresholds: RHRThresholds? = nil,
        hrvExplanationThresholds: HRVThresholds? = nil
    ) {
        self.policy = policy
        self.confidenceEngine = confidenceEngine
        self.explanationEngine = explanationEngine
        self.restingHrExplanationThresholds = restingHrExplanationThresholds
        self.hrvExplanationThresholds = hrvExplanationThresholds
    }

    func calculate(
        todayHRV: Double?,
        todayRHR: Double?,
        minSleepHR: Double?,
        overnightRR: Double?,
        spo2Rolling7Night: Double?,
        baselines: [SignalIdentifier: PersonalBaseline]
    ) -> (
        score: Double,
        missing: [SignalIdentifier],
        contributions: [SignalContribution],
        componentSignals: [HelixSignal],
        primaryExplanation: String
    ) {

        let w = policy.weights
        let originalWeights: [SignalIdentifier: Double] = [
            .hrv:                 w.hrv,
            .restingHR:           w.restingHr,
            .overnightHRDip:      w.overnightHrDip,
            .respiratoryRecovery: w.respiratory
        ]
        var scores           = [SignalIdentifier: Double]()
        var missing          = [SignalIdentifier]()
        var signals          = [HelixSignal]()
        let now              = Date()

        // MARK: HRV Component
        if let hrv = todayHRV,
           let baseline = baselines[.hrv]?.value,
           baseline > 0 {
            let deltaRatio = (hrv - baseline) / baseline
            let score = (policy.hrv.midpoint + deltaRatio * policy.hrv.sensitivity)
                .clampedToHelixScore()
            scores[.hrv]         = score
            _ = hrv - baseline
            signals.append(HelixSignal(
                identifier: .hrv, rawValue: hrv,
                unit: "ms", timestamp: now, baseline: baseline,
                deltaFromBaseline: deltaRatio, normalizedScore: score,
                isValid: true, isAnomaly: false
            ))
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
            signals.append(HelixSignal(
                identifier: .restingHR, rawValue: rhr,
                unit: "bpm", timestamp: now, baseline: baseline,
                deltaFromBaseline: delta, normalizedScore: score,
                isValid: true, isAnomaly: false
            ))
        } else {
            missing.append(.restingHR)
        }

        // MARK: Overnight HR Dip Component
        if let minHR = minSleepHR,
           let restingBaseline = baselines[.restingHR]?.value {
            let dipBPM = restingBaseline - minHR
            let dipBaseline = baselines[.overnightHRDip]?.value ?? 0
            let dipDelta = dipBPM - dipBaseline
            let score = (dipBPM * policy.overnightHrDip.scoreMultiplier)
                .clampedToHelixScore()
            scores[.overnightHRDip]          = score
            signals.append(HelixSignal(
                identifier: .overnightHRDip, rawValue: dipBPM,
                unit: "bpm", timestamp: now, baseline: dipBaseline,
                deltaFromBaseline: dipDelta, normalizedScore: score,
                isValid: true, isAnomaly: false
            ))
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
            let delta = rr - baseline
            signals.append(HelixSignal(
                identifier: .respiratoryRecovery, rawValue: rr,
                unit: "/min", timestamp: now, baseline: baseline,
                deltaFromBaseline: delta, normalizedScore: rrScore,
                isValid: true, isAnomaly: false
            ))
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
        }.clampedToHelixScore()

        // MARK: Contribution breakdown (explanation keys for ViewModel to resolve)
        var contributions = [SignalContribution]()
        for (signal, score) in scores {
            let weight = adjustedWeights[signal] ?? 0
            let pointContribution = score * weight
            let explanationKey = recoveryExplanationKey(for: signal, score: score, scores: scores, todayHRV: todayHRV, todayRHR: todayRHR, minSleepHR: minSleepHR, overnightRR: overnightRR, baselines: baselines)
            let deltaDesc = recoveryDeltaDescription(for: signal, scores: scores, todayHRV: todayHRV, todayRHR: todayRHR, minSleepHR: minSleepHR, overnightRR: overnightRR, baselines: baselines)
            contributions.append(SignalContribution(
                signal: signal,
                pointContribution: pointContribution,
                explanation: explanationKey,
                deltaDescription: deltaDesc
            ))
        }
        contributions.sort { abs($0.pointContribution) > abs($1.pointContribution) }

        /// Strand headline: score-band narrative (`strand_recovery.*`), not top contributor copy.
        let primaryExplanation = recoveryStrandNarrative(score: composite)

        return (composite, missing, contributions, signals, primaryExplanation)
    }

    private func recoveryStrandNarrative(score: Double) -> String {
        let key: String
        if score >= 80 { key = "strand_recovery.strong" }
        else if score >= 65 { key = "strand_recovery.good" }
        else if score >= 45 { key = "strand_recovery.moderate" }
        else if score >= 25 { key = "strand_recovery.low" }
        else { key = "strand_recovery.poor" }
        return explanationEngine.explanation(fromKey: key)
    }

    private func recoveryExplanationKey(for signal: SignalIdentifier, score: Double, scores: [SignalIdentifier: Double], todayHRV: Double?, todayRHR: Double?, minSleepHR: Double?, overnightRR: Double?, baselines: [SignalIdentifier: PersonalBaseline]) -> String {
        switch signal {
        case .hrv:
            guard let t = hrvExplanationThresholds,
                  let hrv = todayHRV,
                  let bl = baselines[.hrv]?.value,
                  bl > 0
            else {
                return "hrv.within_baseline"
            }
            let deltaRatio = (hrv - bl) / bl
            if deltaRatio <= -t.strongDropPercent { return "hrv.strong_drop" }
            if deltaRatio <= -t.significantDropPercent { return "hrv.significant_drop" }
            if deltaRatio <= -t.notableDropPercent { return "hrv.notable_drop" }
            if deltaRatio >= t.significantRisePercent { return "hrv.significant_rise" }
            if deltaRatio >= t.notableRisePercent { return "hrv.notable_rise" }
            return "hrv.within_baseline"
        case .restingHR:
            if let t = restingHrExplanationThresholds, let rhr = todayRHR, let bl = baselines[.restingHR]?.value {
                let bpmDelta = rhr - bl
                if bpmDelta > t.strongRiseBpm { return "resting_hr.strong_rise" }
                if bpmDelta > t.significantRiseBpm { return "resting_hr.significant_rise" }
                if bpmDelta > t.notableRiseBpm { return "resting_hr.notable_rise" }
                if bpmDelta < -t.notableDropBpm { return "resting_hr.notable_drop" }
                return "resting_hr.within_baseline"
            }
            if score < 50 { return "resting_hr.strong_rise" }
            if score < 65 { return "resting_hr.notable_rise" }
            if score > 75 { return "resting_hr.notable_drop" }
            return "resting_hr.within_baseline"
        case .overnightHRDip:
            if score > 80 { return "overnight_hr_dip.strong" }
            if score > 50 { return "overnight_hr_dip.moderate" }
            return "overnight_hr_dip.shallow"
        case .respiratoryRecovery:
            if score < 70 { return "respiratory.elevated" }
            return "respiratory.stable"
        default:
            return signal.explanationKey
        }
    }

    private func recoveryDeltaDescription(for signal: SignalIdentifier, scores: [SignalIdentifier: Double], todayHRV: Double?, todayRHR: Double?, minSleepHR: Double?, overnightRR: Double?, baselines: [SignalIdentifier: PersonalBaseline]) -> String {
        switch signal {
        case .hrv:
            guard let hrv = todayHRV, let bl = baselines[.hrv]?.value else { return "" }
            let d = hrv - bl
            return String(format: "%+.0f ms", d)
        case .restingHR:
            guard let rhr = todayRHR, let bl = baselines[.restingHR]?.value else { return "" }
            return String(format: "%+.0f bpm", rhr - bl)
        case .overnightHRDip:
            guard let minHR = minSleepHR, let rhrBl = baselines[.restingHR]?.value else { return "" }
            let dipBPM = rhrBl - minHR
            let dipBl = baselines[.overnightHRDip]?.value ?? 0
            return String(format: "%+.0f bpm", dipBPM - dipBl)
        case .respiratoryRecovery:
            guard let rr = overnightRR, let bl = baselines[.overnightRespiratory]?.value else { return "" }
            return String(format: "%+.1f /min", rr - bl)
        default:
            return ""
        }
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
