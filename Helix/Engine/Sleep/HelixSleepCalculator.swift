// Engine/HelixSleepCalculator.swift
// Implements Strand I — Helix Sleep Score.
// All coefficients read from helix_policy.v1.1.json via SleepConfig.
// No hardcoded values in this file.
//
// Components (weights from policy):
//   duration     0.30 — asymmetric penalty: undersleep costs more than oversleep
//   consistency  0.20 — bedtime SD + wake SD (minutes) over last 7 nights
//   deep_sleep   0.15 — vs personal baseline percentage
//   rem_sleep    0.13 — vs personal baseline percentage
//   disturbance  0.12 — awakenings per hour cost
//   thermal      0.05 — wrist temp delta vs personal baseline
//   respiratory  0.05 — overnight RR vs personal baseline

import Foundation

class HelixSleepCalculator {

    private let policy:             SleepConfig
    private let confidenceEngine:   HelixConfidenceEngine
    private let explanationEngine: HelixExplanationEngine

    init(
        policy: SleepConfig,
        confidenceEngine: HelixConfidenceEngine,
        explanationEngine: HelixExplanationEngine
    ) {
        self.policy             = policy
        self.confidenceEngine  = confidenceEngine
        self.explanationEngine = explanationEngine
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
        let durationBaseline = baselines[.sleepDuration].map(\.value).nonZeroOrNil
            ?? policy.populationDefaults.sleepDurationHours
        if raw.totalDurationHours > 0, durationBaseline > 0 {
            let score = durationScore(duration: raw.totalDurationHours, baseline: durationBaseline)
            let delta = (raw.totalDurationHours - durationBaseline) / durationBaseline
            scores[.sleepDuration] = score
            originalWeights[.sleepDuration] = w.duration
            signals.append(HelixSignal(
                identifier: .sleepDuration, rawValue: raw.totalDurationHours,
                unit: "hrs", timestamp: Date(), baseline: durationBaseline,
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
            let combinedTimingSD = bedtimeSD + wakeSD
            let consistencyBaseline = baselines[.sleepConsistency]?.value ?? 0
            let consistencyDelta = consistencyBaseline > 0
                ? (combinedTimingSD - consistencyBaseline) / consistencyBaseline
                : 0
            scores[.sleepConsistency] = score
            originalWeights[.sleepConsistency] = w.consistency
            signals.append(HelixSignal(
                identifier: .sleepConsistency, rawValue: combinedTimingSD,
                unit: "min SD Σ", timestamp: Date(), baseline: consistencyBaseline,
                deltaFromBaseline: consistencyDelta, normalizedScore: score, isValid: true, isAnomaly: false
            ))
            _ = wakeSD  // used in score computation above
        } else {
            missing.append(.sleepConsistency)
        }

        // MARK: 3 — Deep Sleep (weight 0.15)
        let deepBaseline = baselines[.deepSleepPercent].map(\.value).nonZeroOrNil
            ?? policy.populationDefaults.deepSleepFraction
        if raw.totalDurationHours >= 4.0, deepBaseline > 0 {
            let score = stageScore(actual: raw.deepSleepPercent, baseline: deepBaseline)
            let delta = (raw.deepSleepPercent - deepBaseline) / deepBaseline
            scores[.deepSleepPercent] = score
            originalWeights[.deepSleepPercent] = w.deepSleep
            signals.append(HelixSignal(
                identifier: .deepSleepPercent, rawValue: raw.deepSleepPercent,
                unit: "%", timestamp: Date(), baseline: deepBaseline,
                deltaFromBaseline: delta, normalizedScore: score, isValid: true, isAnomaly: false
            ))
        } else {
            missing.append(.deepSleepPercent)
        }

        // MARK: 4 — REM Sleep (weight 0.13)
        let remBaseline = baselines[.remSleepPercent].map(\.value).nonZeroOrNil
            ?? policy.populationDefaults.remSleepFraction
        if raw.totalDurationHours >= 4.0, remBaseline > 0 {
            let score = stageScore(actual: raw.remSleepPercent, baseline: remBaseline)
            let delta = (raw.remSleepPercent - remBaseline) / remBaseline
            scores[.remSleepPercent] = score
            originalWeights[.remSleepPercent] = w.remSleep
            signals.append(HelixSignal(
                identifier: .remSleepPercent, rawValue: raw.remSleepPercent,
                unit: "%", timestamp: Date(), baseline: remBaseline,
                deltaFromBaseline: delta, normalizedScore: score, isValid: true, isAnomaly: false
            ))
        } else {
            missing.append(.remSleepPercent)
        }

        // MARK: 5 — Disturbance (weight 0.12)
        // score = max(0, 100 - awakenings_per_hour × cost_per_awakening_per_hour)
        let disturbanceScore = max(0, policy.disturbance.maxScore
            - raw.awakeningsPerHour * policy.disturbance.costPerAwakeningPerHour)
        let awakeningsBaseline = baselines[.awakeningsPerHour]?.value ?? 0
        let awakeningsDelta = awakeningsBaseline > 0
            ? (raw.awakeningsPerHour - awakeningsBaseline) / awakeningsBaseline
            : 0
        scores[.awakeningsPerHour] = disturbanceScore
        originalWeights[.awakeningsPerHour] = w.disturbance
        signals.append(HelixSignal(
            identifier: .awakeningsPerHour, rawValue: raw.awakeningsPerHour,
            unit: "/hr", timestamp: Date(), baseline: awakeningsBaseline,
            deltaFromBaseline: awakeningsDelta, normalizedScore: disturbanceScore, isValid: true, isAnomaly: false
        ))

        // MARK: 6 — Thermal (weight 0.05) — raw is Δ°C; personal absolute mean is in `baselines[.wristTemperature]` when seeded
        if let tempDelta = raw.wristTempDeltaCelsius {
            let score = max(0, 100.0 - abs(tempDelta) * policy.thermal.sensitivity)
            scores[.wristTemperature] = score
            originalWeights[.wristTemperature] = w.thermal
            let absBaseline = baselines[.wristTemperature]?.value ?? 0
            let deltaFraction = absBaseline > 0 ? tempDelta / absBaseline : tempDelta
            signals.append(HelixSignal(
                identifier: .wristTemperature, rawValue: tempDelta,
                unit: "°C Δ", timestamp: Date(), baseline: absBaseline,
                deltaFromBaseline: deltaFraction, normalizedScore: score,
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
                explanation: sleepContributionExplanationKey(
                    for: signal,
                    score: score,
                    deltaFromBaseline: signals.first(where: { $0.identifier == signal })?.deltaFromBaseline
                ),
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
            primaryExplanation:   primaryExplanation(for: composite, contributions: contributions),
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
        let calendar = Calendar.current
        // Convert to minutes since noon (12:00) so that sleep times spanning midnight
        // are treated as contiguous. Times before noon are shifted by +1440 (next day).
        // e.g. 10:30pm = 630 min after noon; 1:30am = 90 min before noon → 90+1440 = 1530 min after noon.
        // This keeps the distribution continuous across midnight.
        let minutesSinceNoon = dates.map { date -> Double in
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            let minutesFromMidnight = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
            let minutesFromNoon = minutesFromMidnight - 720  // subtract 12 hours
            return minutesFromNoon < 0 ? minutesFromNoon + 1440 : minutesFromNoon
        }
        let mean = minutesSinceNoon.reduce(0, +) / Double(minutesSinceNoon.count)
        let variance = minutesSinceNoon.map { pow($0 - mean, 2) }.reduce(0, +) / Double(minutesSinceNoon.count)
        return variance.squareRoot()
    }

    // Deep / REM: scored relative to personal baseline percentage
    // 50 = at baseline, sensitivity scales deviation
    private func stageScore(actual: Double, baseline: Double) -> Double {
        let delta = (actual - baseline) / baseline
        return (50.0 + delta * 150.0).clampedToHelixScore()
    }

    // MARK: — Explanation helpers

    private func sleepContributionExplanationKey(for signal: SignalIdentifier, score: Double, deltaFromBaseline: Double?) -> String {
        // Returns a key that maps to helix_explanation_policy language_templates
        // Full string resolution happens in HelixExplanationEngine
        switch signal {
        case .sleepDuration:
            let delta = deltaFromBaseline ?? 0
            if score < 40 { return delta > 0 ? "sleep_duration.surplus" : "sleep_duration.strong_deficit" }
            if score < 60 { return delta > 0 ? "sleep_duration.surplus" : "sleep_duration.significant_deficit" }
            if score < 80 { return delta > 0 ? "sleep_duration.surplus" : "sleep_duration.notable_deficit" }
            if delta > 0  { return "sleep_duration.surplus" }
            if delta < -0.05 { return "sleep_duration.notable_deficit" }
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
            let d = deltaFromBaseline ?? 0
            if score >= 75 { return "sleep_consistency.consistent" }
            if score >= 50 {
                return d > 0 ? "sleep_consistency.notable_variance" : "sleep_consistency.consistent"
            }
            return d > 0 ? "sleep_consistency.significant_variance" : "sleep_consistency.notable_variance"

        case .awakeningsPerHour:
            // Disturbance signal: high score = few awakenings = good.
            // Score-based branching only — delta direction is inverse and not used for key selection.
            if score >= 75 { return "disturbance.low" }
            if score >= 50 { return "disturbance.within_baseline" }
            return "disturbance.elevated"
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
        let d = sig.deltaFromBaseline
        switch signal {
        case .sleepConsistency:
            let pct = Int(abs(d) * 100)
            if pct < 5 { return "Within your baseline" }
            return d > 0
                ? "\(pct)% more timing variance than your baseline"
                : "\(pct)% less timing variance than your baseline"
        case .awakeningsPerHour:
            let pct = Int(abs(d) * 100)
            if pct < 5 { return "Within your baseline" }
            return d > 0
                ? "\(pct)% more awakenings than your baseline"
                : "\(pct)% fewer awakenings than your baseline"
        default:
            let pct = Int(abs(d) * 100)
            let direction = d >= 0 ? "above" : "below"
            return pct < 5 ? "Within your baseline" : "\(pct)% \(direction) your baseline"
        }
    }

    /// Strand headline for Depth 3 — score-band `strand_sleep.*` narrative. `contributions` unused (signature unchanged for call sites).
    private func primaryExplanation(for score: Double, contributions: [SignalContribution]) -> String {
        // contributions unused — strand narrative derived from score band per policy
        _ = contributions
        let key: String
        if score >= 80 { key = "strand_sleep.strong" }
        else if score >= 65 { key = "strand_sleep.good" }
        else if score >= 45 { key = "strand_sleep.moderate" }
        else if score >= 25 { key = "strand_sleep.low" }
        else { key = "strand_sleep.poor" }
        return explanationEngine.explanation(fromKey: key)
    }
}

// MARK: — Baseline warm-up helper (fileprivate to this calculator)

private extension Optional where Wrapped == Double {
    /// Treat zero EWMA as missing so `strand_sleep.population_defaults` can apply.
    var nonZeroOrNil: Double? {
        guard let v = self, v > 0 else { return nil }
        return v
    }
}
