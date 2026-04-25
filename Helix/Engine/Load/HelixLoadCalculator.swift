// Engine/HelixLoadCalculator.swift
// Implements Strand II — Helix Load Score.
// All coefficients read from helix_policy.v1.1.json via LoadConfig.
//
// Components (weights from policy):
//   acwr              0.40 — acute:chronic workload ratio
//   acute_load        0.35 — absolute recent training stress
//   activity_completion 0.15 — consistency of intended training
//   hr_elevation_penalty 0.10 — resting HR elevated above baseline (load marker)
//
// TSS calculation uses Tanaka max HR formula via LoadCalculationContext.
// If age is estimated (DOB unavailable), strand confidence is capped at .medium.

import Foundation

class HelixLoadCalculator {

    private let policy:          LoadConfig
    private let confidenceEngine: HelixConfidenceEngine

    init(policy: LoadConfig, confidenceEngine: HelixConfidenceEngine) {
        self.policy           = policy
        self.confidenceEngine = confidenceEngine
    }

    // MARK: — Primary API

    func calculate(
        raw:        LoadRawData,
        baselines:  [SignalIdentifier: PersonalBaseline],
        ageContext: LoadCalculationContext
    ) -> (score: Double, strand: StrandScore) {

        var originalWeights = [SignalIdentifier: Double]()
        var scores          = [SignalIdentifier: Double]()
        var missing         = [SignalIdentifier]()
        var signals         = [HelixSignal]()
        var contributions   = [SignalContribution]()

        let w   = policy.weights
        let ac  = policy.acuteChronic

        // MARK: 1 — Compute daily TSS from workouts + HR
        let dailyTSS = computeDailyTSS(
            workouts:       raw.workouts,
            hrSamples:      raw.heartRateSamples,
            ageContext:     ageContext,
            energyKcal:     raw.activeEnergyKcal
        )

        // MARK: 2 — ACWR: Acute (7-day EWMA) / Chronic (28-day EWMA)
        let acuteLoad   = ewmaLoad(dailyTSS: dailyTSS, windowDays: ac.acuteWindowDays,   decay: ac.acuteDecay)
        let chronicLoad = ewmaLoad(dailyTSS: dailyTSS, windowDays: ac.chronicWindowDays, decay: ac.chronicDecay)
        let acwr        = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0

        let acwrScore = acwrScore(acwr: acwr)
        scores[.acuteChronicRatio]          = acwrScore
        originalWeights[.acuteChronicRatio] = w.acwr
        signals.append(HelixSignal(
            identifier: .acuteChronicRatio, rawValue: acwr,
            unit: "ratio", timestamp: Date(), baseline: 1.0,
            deltaFromBaseline: acwr - 1.0, normalizedScore: acwrScore,
            isValid: true, isAnomaly: acwr > policy.acwrScoring.cautionCeiling
        ))

        // MARK: 3 — Acute Load score (absolute TSS vs baseline)
        if let baseline = baselines[.trainingVolume]?.value {
            let score = acuteLoadScore(acuteLoad: acuteLoad, baseline: baseline)
            scores[.trainingVolume]          = score
            originalWeights[.trainingVolume] = w.acuteLoad
            signals.append(HelixSignal(
                identifier: .trainingVolume, rawValue: acuteLoad,
                unit: "TSS", timestamp: Date(), baseline: baseline,
                deltaFromBaseline: baseline > 0 ? (acuteLoad - baseline) / baseline : 0,
                normalizedScore: score, isValid: true, isAnomaly: false
            ))
        } else {
            missing.append(.trainingVolume)
        }

        // MARK: 4 — Activity Completion (workout frequency vs baseline)
        // Uses recent workout count vs 28-day average as a proxy
        let recentWorkoutDays  = Set(raw.workouts.map { Calendar.current.startOfDay(for: $0.startDate) }).count
        let expectedPerWeek    = 28.0 > 0 ? Double(raw.workouts.count) / 4.0 : 3.0 // approx
        let completionRatio    = expectedPerWeek > 0 ? min(1.2, Double(recentWorkoutDays) / (expectedPerWeek * 7.0 / 7.0)) : 1.0
        let completionScore    = (completionRatio * 80.0).clampedToHelixScore()
        scores[.activityCompletion]          = completionScore
        originalWeights[.activityCompletion] = w.activityCompletion

        // MARK: 5 — HR Elevation Penalty (load signal from resting HR)
        // Elevated resting HR signals accumulated training load not yet dissipated
        if let rhr = baselines[.restingHR]?.value,
           let acuteRHR = signals.first(where: { $0.identifier == .restingHR })?.rawValue ?? nil {
            let penalty = min(
                policy.hrElevation.maximumPenalty,
                max(0, acuteRHR - rhr) * policy.hrElevation.costPerBpmAboveBaseline
            )
            let score = (100.0 - penalty).clampedToHelixScore()
            scores[.hrElevation]          = score
            originalWeights[.hrElevation] = w.hrElevationPenalty
        } else {
            missing.append(.hrElevation)
        }

        // MARK: Weight redistribution and composite
        let adjusted = confidenceEngine.redistributedWeights(
            originalWeights: originalWeights,
            missingSignals: missing
        )

        let composite = scores.reduce(0.0) { acc, pair in
            acc + pair.value * (adjusted[pair.key] ?? 0)
        }.clampedToHelixScore()

        // MARK: Contribution breakdown
        for (signal, score) in scores {
            let weight = adjusted[signal] ?? 0
            contributions.append(SignalContribution(
                signal: signal,
                pointContribution: score * weight,
                explanation: loadExplanationKey(for: signal, acwr: acwr, score: score),
                deltaDescription: ""
            ))
        }
        contributions.sort { abs($0.pointContribution) > abs($1.pointContribution) }

        // MARK: Confidence — capped at .medium if age was estimated
        let confidenceResult = confidenceEngine.evaluate(
            presentSignals:     Array(scores.keys),
            validSignals:       Array(scores.keys),
            allExpectedSignals: [.acuteChronicRatio, .trainingVolume, .activityCompletion, .hrElevation]
        )
        let finalConfidence: ConfidenceLevel = ageContext.ageIsEstimated
            ? Swift.min(confidenceResult.level, .medium)
            : confidenceResult.level

        var explanation = ageContext.ageIsEstimated
            ? "Training zones estimated — add date of birth in Apple Health for accuracy. "
            : ""
        explanation += primaryLoadExplanation(acwr: acwr, score: composite)

        let strand = StrandScore(
            strand:               .load,
            score:                composite,
            componentSignals:     signals,
            missingSignals:       missing,
            confidence:           finalConfidence,
            contributionBreakdown: contributions,
            primaryExplanation:   explanation,
            calculatedAt:         Date()
        )

        return (composite, strand)
    }

    // MARK: — TSS calculation

    // TSS = Σ(minutes_in_zone × zone_stress_multiplier) + NEAT contribution
    private func computeDailyTSS(
        workouts:   [HKWorkoutProxy],
        hrSamples:  [HKSampleProxy],
        ageContext: LoadCalculationContext,
        energyKcal: Double
    ) -> [(tss: Double, date: Date)] {

        let maxHR       = ageContext.maxHeartRate
        let multipliers = policy.heartRateZones.zoneStressMultipliers
        let zones       = zoneThresholds(maxHR: maxHR)
        let calendar    = Calendar.current

        // Group HR samples by workout
        var byWorkout = [Date: [(Double, Date)]]()
        for workout in workouts {
            let wSamples = hrSamples.filter {
                $0.startDate >= workout.startDate && $0.startDate <= workout.endDate
            }
            let key = calendar.startOfDay(for: workout.startDate)
            byWorkout[key, default: []].append(contentsOf: wSamples.map { ($0.value, $0.startDate) })
        }

        // Compute TSS per day
        var tssHistory: [(tss: Double, date: Date)] = []

        for (day, daySamples) in byWorkout {
            var tss = 0.0
            for i in 0..<daySamples.count {
                let hr        = daySamples[i].0
                let zone      = heartRateZone(hr: hr, zones: zones)
                let multiplier = multipliers["zone_\(zone)"] ?? 1.0
                // Minutes between this sample and next (or 1 min for last sample)
                let minutes: Double
                if i < daySamples.count - 1 {
                    minutes = daySamples[i + 1].1.timeIntervalSince(daySamples[i].1) / 60.0
                } else {
                    minutes = 1.0
                }
                tss += max(0, min(minutes, 5.0)) * multiplier  // Cap interval at 5 min to handle gaps
            }
            tssHistory.append((tss: tss, date: day))
        }

        // NEAT contribution for days without workouts
        let workoutDays = Set(tssHistory.map { $0.date })
        let neatTSS = energyKcal * policy.heartRateZones.neatEnergyMultiplier
        let today = calendar.startOfDay(for: Date())
        if !workoutDays.contains(today) && neatTSS > 0 {
            tssHistory.append((tss: neatTSS, date: today))
        }

        return tssHistory.sorted { $0.date < $1.date }
    }

    private func zoneThresholds(maxHR: Double) -> [(low: Double, high: Double)] {
        let boundaries = policy.heartRateZones
        return [
            (0.50 * maxHR, 0.60 * maxHR),
            (0.60 * maxHR, 0.70 * maxHR),
            (0.70 * maxHR, 0.80 * maxHR),
            (0.80 * maxHR, 0.90 * maxHR),
            (0.90 * maxHR, maxHR)
        ]
        _ = boundaries  // suppress unused warning
    }

    private func heartRateZone(hr: Double, zones: [(low: Double, high: Double)]) -> Int {
        for (i, zone) in zones.enumerated() {
            if hr >= zone.low && hr < zone.high { return i + 1 }
        }
        return hr < zones[0].low ? 1 : 5
    }

    // MARK: — EWMA load

    private func ewmaLoad(dailyTSS: [(tss: Double, date: Date)], windowDays: Int, decay: Double) -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: Date())!
        let relevant = dailyTSS.filter { $0.date >= cutoff }
        guard !relevant.isEmpty else { return 0 }

        let today = Date()
        var weightedSum = 0.0, weightTotal = 0.0
        for entry in relevant {
            let daysAgo = Calendar.current.dateComponents([.day], from: entry.date, to: today).day ?? 0
            let weight  = pow(decay, Double(daysAgo))
            weightedSum += entry.tss * weight
            weightTotal += weight
        }
        return weightTotal > 0 ? weightedSum / weightTotal : 0
    }

    // MARK: — ACWR scoring

    private func acwrScore(acwr: Double) -> Double {
        let bands = policy.acwrScoring
        switch acwr {
        case ..<bands.undertrainingCeiling:
            // Undertraining — score linearly from 40 to 60 as acwr approaches optimal_low
            let progress = acwr / bands.undertrainingCeiling
            return (40.0 + progress * 20.0).clampedToHelixScore()
        case bands.undertrainingCeiling..<bands.optimalLow:
            // Transitional — 60 to 80
            let range    = bands.optimalLow - bands.undertrainingCeiling
            let progress = (acwr - bands.undertrainingCeiling) / range
            return (60.0 + progress * 20.0).clampedToHelixScore()
        case bands.optimalLow...bands.optimalHigh:
            // Optimal — 80 to 100
            return 90.0
        case bands.optimalHigh..<bands.cautionCeiling:
            // Caution — 50 to 80 (declining as load rises)
            let range    = bands.cautionCeiling - bands.optimalHigh
            let excess   = acwr - bands.optimalHigh
            return (80.0 - (excess / range) * 30.0).clampedToHelixScore()
        default:
            // Excessive — below 50, declining further
            let excess = acwr - bands.cautionCeiling
            return (50.0 - excess * 20.0).clampedToHelixScore()
        }
    }

    private func acuteLoadScore(acuteLoad: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 50.0 }
        let ratio = acuteLoad / baseline
        // Near baseline = 80, progressive decay outward
        return (80.0 - abs(ratio - 1.0) * 40.0).clampedToHelixScore()
    }

    // MARK: — Explanation helpers

    private func loadExplanationKey(for signal: SignalIdentifier, acwr: Double, score: Double) -> String {
        if signal == .acuteChronicRatio {
            if acwr > policy.acwrScoring.cautionCeiling { return "acwr.very_high" }
            if acwr > policy.acwrScoring.optimalHigh    { return "acwr.high" }
            if acwr < policy.acwrScoring.undertrainingCeiling { return "acwr.low" }
            return "acwr.optimal"
        }
        return signal.explanationKey
    }

    private func primaryLoadExplanation(acwr: Double, score: Double) -> String {
        if acwr > policy.acwrScoring.cautionCeiling {
            return "Training load significantly exceeds your recent capacity."
        }
        if acwr > policy.acwrScoring.optimalHigh {
            return "Training load is above your recent average — a productive stimulus."
        }
        if acwr < policy.acwrScoring.undertrainingCeiling {
            return "Training volume is below your recent baseline."
        }
        return "Training load is well-balanced."
    }
}

// MARK: — Optional<Double> convenience for HR elevation calculation
private extension Optional where Wrapped == Double {
    static func ?? (lhs: Double?, rhs: Double?) -> Double? {
        lhs ?? rhs
    }
}
