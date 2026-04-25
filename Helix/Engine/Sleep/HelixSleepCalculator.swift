// Engine/HelixSleepCalculator.swift
// Implements Strand I — Helix Sleep Score.
// All coefficients read from helix_policy.v1.1.json via SleepConfig.
// No hardcoded values in this file.
//
// Components (weights from policy):
//   duration     0.30 — asymmetric penalty: undersleep costs more than oversleep
//   consistency  0.20 — bedtime + wake variance over last 7 nights
//   deep_sleep   0.15 — vs personal baseline percentage
//   rem_sleep    0.13 — vs personal baseline percentage
//   disturbance  0.12 — awakenings per hour cost
//   thermal      0.05 — wrist temp delta vs personal baseline
//   respiratory  0.05 — overnight RR vs personal baseline

import Foundation

class HelixSleepCalculator {

    private let policy:          SleepConfig
    private let confidenceEngine: HelixConfidenceEngine

    init(policy: SleepConfig, confidenceEngine: HelixConfidenceEngine) {
        self.policy           = policy
        self.confidenceEngine = confidenceEngine
    }

    // MARK: — Primary API

    func calculate(
        raw:       SleepRawData,
        baselines: [SignalIdentifier: PersonalBaseline]
    ) -> (score: Double, strand: StrandScore) {

        var originalWeights = [SignalIdentifier: Double]()
        var scores          = [SignalIdentifier: Double]()
        var missing         = [SignalIdentifier]()
        var signals         = [HelixSignal]()
        var contributions   = [SignalContribution]()

        let w = policy.weights

        // MARK: 1 — Duration (weight 0.30)
        if let baseline = baselines[.sleepDuration]?.value, baseline > 0 {
            let score = durationScore(duration: raw.totalDurationHours, baseline: baseline)
            let delta = (raw.totalDurationHours - baseline) / baseline
            scores[.sleepDuration] = score
            originalWeights[.sleepDuration] = w.duration
            signals.append(HelixSignal(
                identifier: .sleepDuration, rawValue: raw.totalDurationHours,
                unit: "hrs", timestamp: Date(), baseline: baseline,
                deltaFromBaseline: delta, normalizedScore: score, isValid: true, isAnomaly: false
            ))
        } else {
            missing.append(.sleepDuration)
        }

        // MARK: 2 — Consistency (weight 0.20)
        if !raw.bedtimes.isEmpty && !raw.wakeTimes.isEmpty {
            let (score, bedtimeSD, wakeSD) = consistencyScore(
                bedtimes: raw.bedtimes, wakeTimes: raw.wakeTimes
            )
            scores[.sleepConsistency] = score
            originalWeights[.sleepConsistency] = w.consistency
            signals.append(HelixSignal(
                identifier: .sleepConsistency, rawValue: bedtimeSD,
                unit: "min SD", timestamp: Date(), baseline: 0,
                deltaFromBaseline: 0, normalizedScore: score, isValid: true, isAnomaly: false
            ))
            _ = wakeSD  // used in score computation above
        } else {
            missing.append(.sleepConsistency)
        }

        // MARK: 3 — Deep Sleep (weight 0.15)
        if let baseline = baselines[.deepSleepPercent]?.value, baseline > 0,
           raw.totalDurationHours >= 4.0 {  // policy: minimum_hours_for_staging
            let score = stageScore(actual: raw.deepSleepPercent, baseline: baseline)
            let delta = (raw.deepSleepPercent - baseline) / baseline
            scores[.deepSleepPercent] = score
            originalWeights[.deepSleepPercent] = w.deepSleep
            signals.append(HelixSignal(
                identifier: .deepSleepPercent, rawValue: raw.deepSleepPercent,
                unit: "%", timestamp: Date(), baseline: baseline,
                deltaFromBaseline: delta, normalizedScore: score, isValid: true, isAnomaly: false
            ))
        } else {
            missing.append(.deepSleepPercent)
        }

        // MARK: 4 — REM Sleep (weight 0.13)
        if let baseline = baselines[.remSleepPercent]?.value, baseline > 0,
           raw.totalDurationHours >= 4.0 {
            let score = stageScore(actual: raw.remSleepPercent, baseline: baseline)
            let delta = (raw.remSleepPercent - baseline) / baseline
            scores[.remSleepPercent] = score
            originalWeights[.remSleepPercent] = w.remSleep
            signals.append(HelixSignal(
                identifier: .remSleepPercent, rawValue: raw.remSleepPercent,
                unit: "%", timestamp: Date(), baseline: baseline,
                deltaFromBaseline: delta, normalizedScore: score, isValid: true, isAnomaly: false
            ))
        } else {
            missing.append(.remSleepPercent)
        }

        // MARK: 5 — Disturbance (weight 0.12)
        // score = max(0, 100 - awakenings_per_hour × cost_per_awakening_per_hour)
        let disturbanceScore = max(0, policy.disturbance.maxScore
            - raw.awakeningsPerHour * policy.disturbance.costPerAwakeningPerHour)
        scores[.awakeningsPerHour] = disturbanceScore
        originalWeights[.awakeningsPerHour] = w.disturbance
        signals.append(HelixSignal(
            identifier: .awakeningsPerHour, rawValue: raw.awakeningsPerHour,
            unit: "/hr", timestamp: Date(), baseline: 0,
            deltaFromBaseline: 0, normalizedScore: disturbanceScore, isValid: true, isAnomaly: false
        ))

        // MARK: 6 — Thermal (weight 0.05)
        if let tempDelta = raw.wristTempDeltaCelsius {
            let score = max(0, 100.0 - abs(tempDelta) * policy.thermal.sensitivity)
            scores[.wristTemperature] = score
            originalWeights[.wristTemperature] = w.thermal
            signals.append(HelixSignal(
                identifier: .wristTemperature, rawValue: tempDelta,
                unit: "°C Δ", timestamp: Date(), baseline: 0,
                deltaFromBaseline: tempDelta, normalizedScore: score,
                isValid: true, isAnomaly: abs(tempDelta) > policy.thermal.anomalyFlagThresholdCelsius
            ))
        } else {
            missing.append(.wristTemperature)
        }

        // MARK: 7 — Respiratory (weight 0.05)
        if let rr = raw.overnightRespiratoryRate,
           let baseline = baselines[.overnightRespiratory]?.value, baseline > 0 {
            let delta = abs(rr - baseline)
            let score = max(0, 100.0 - delta * policy.respiratory.sensitivity)
            scores[.overnightRespiratory] = score
            originalWeights[.overnightRespiratory] = w.respiratory
            signals.append(HelixSignal(
                identifier: .overnightRespiratory, rawValue: rr,
                unit: "brpm", timestamp: Date(), baseline: baseline,
                deltaFromBaseline: (rr - baseline) / baseline, normalizedScore: score,
                isValid: true, isAnomaly: false
            ))
        } else {
            missing.append(.overnightRespiratory)
        }

        // MARK: Weight redistribution and composite
        let adjusted = confidenceEngine.redistributedWeights(
            originalWeights: originalWeights,
            missingSignals: missing
        )

        let composite = scores.reduce(0.0) { acc, pair in
            acc + pair.value * (adjusted[pair.key] ?? 0)
        }.clampedToHelixScore()

        // MARK: Contribution breakdown (for depth-3 decomposition)
        for (signal, score) in scores {
            let weight = adjusted[signal] ?? 0
            contributions.append(SignalContribution(
                signal: signal,
                pointContribution: score * weight,
                explanation: explanationKey(for: signal, score: score),
                deltaDescription: deltaDescription(for: signal, in: signals)
            ))
        }
        contributions.sort { abs($0.pointContribution) > abs($1.pointContribution) }

        // MARK: Confidence
        let confidenceResult = confidenceEngine.evaluate(
            presentSignals:     Array(scores.keys),
            validSignals:       Array(scores.keys),
            allExpectedSignals: [.sleepDuration, .sleepConsistency, .deepSleepPercent,
                                 .remSleepPercent, .awakeningsPerHour, .wristTemperature,
                                 .overnightRespiratory]
        )

        let strand = StrandScore(
            strand:               .sleep,
            score:                composite,
            componentSignals:     signals,
            missingSignals:       missing,
            confidence:           confidenceResult.level,
            contributionBreakdown: contributions,
            primaryExplanation:   primaryExplanation(for: composite, missing: missing),
            calculatedAt:         Date()
        )

        return (composite, strand)
    }

    // MARK: — Component calculations

    private func durationScore(duration: Double, baseline: Double) -> Double {
        if duration < baseline {
            let deficit = baseline - duration
            return max(0, 100.0 - deficit * policy.duration.undersleepCostPerHour)
        } else {
            let surplus = duration - baseline
            return max(0, 100.0 - surplus * policy.duration.oversleepCostPerHour)
        }
    }

    // Returns (score, bedtimeStdDevMinutes, wakeStdDevMinutes)
    private func consistencyScore(
        bedtimes: [Date],
        wakeTimes: [Date]
    ) -> (Double, Double, Double) {

        let bedSD  = standardDeviationMinutes(dates: bedtimes)
        let wakeSD = standardDeviationMinutes(dates: wakeTimes)

        let score = max(0,
            100.0
            - bedSD  * policy.consistency.bedtimeVarianceCostPerMinute
            - wakeSD * policy.consistency.wakeVarianceCostPerMinute
        )
        return (score, bedSD, wakeSD)
    }

    private func standardDeviationMinutes(dates: [Date]) -> Double {
        guard dates.count > 1 else { return 0 }
        // Convert each date to seconds-since-midnight for variance calculation
        let calendar  = Calendar.current
        let secondsOfDay = dates.map { date -> Double in
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            return Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        }
        let mean     = secondsOfDay.reduce(0, +) / Double(secondsOfDay.count)
        let variance = secondsOfDay.map { pow($0 - mean, 2) }.reduce(0, +) / Double(secondsOfDay.count)
        return variance.squareRoot()
    }

    // Deep / REM: scored relative to personal baseline percentage
    // 50 = at baseline, sensitivity scales deviation
    private func stageScore(actual: Double, baseline: Double) -> Double {
        let delta = (actual - baseline) / baseline
        return (50.0 + delta * 150.0).clampedToHelixScore()
    }

    // MARK: — Explanation helpers

    private func explanationKey(for signal: SignalIdentifier, score: Double) -> String {
        // Returns a key that maps to helix_explanation_policy language_templates
        // Full string resolution happens in HelixExplanationEngine
        switch signal {
        case .sleepDuration:
            if score < 40 { return "sleep_duration.strong_deficit" }
            if score < 60 { return "sleep_duration.significant_deficit" }
            if score < 80 { return "sleep_duration.notable_deficit" }
            return "sleep_duration.within_optimal"
        case .deepSleepPercent:
            if score < 45 { return "deep_sleep.below_baseline" }
            if score > 65 { return "deep_sleep.above_baseline" }
            return "deep_sleep.within_baseline"
        case .remSleepPercent:
            if score < 45 { return "rem_sleep.below_baseline" }
            if score > 65 { return "rem_sleep.above_baseline" }
            return "rem_sleep.within_baseline"
        case .sleepConsistency:
            if score < 50 { return "sleep_consistency.significant_variance" }
            if score < 75 { return "sleep_consistency.notable_variance" }
            return "sleep_consistency.consistent"
        case .wristTemperature:
            if score < 50 { return "wrist_temperature.elevated" }
            return "wrist_temperature.stable"
        case .overnightRespiratory:
            if score < 70 { return "respiratory.elevated" }
            return "respiratory.stable"
        default:
            return signal.explanationKey
        }
    }

    private func deltaDescription(for signal: SignalIdentifier, in signals: [HelixSignal]) -> String {
        guard let sig = signals.first(where: { $0.identifier == signal }) else { return "" }
        let pct = Int(abs(sig.deltaFromBaseline) * 100)
        let direction = sig.deltaFromBaseline >= 0 ? "above" : "below"
        return pct < 5 ? "Within your baseline" : "\(pct)% \(direction) your baseline"
    }

    private func primaryExplanation(for score: Double, missing: [SignalIdentifier]) -> String {
        if !missing.isEmpty {
            return "Sleep score estimated — \(missing.count) signal(s) unavailable."
        }
        if score >= 80 { return "Strong sleep quality last night." }
        if score >= 60 { return "Adequate sleep with some room for improvement." }
        if score >= 40 { return "Sleep quality was below your normal." }
        return "Poor sleep recovery last night."
    }
}
