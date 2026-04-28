// Engine/HelixLoadCalculator.swift
// Implements Strand II — Helix Load Score.
// All coefficients read from helix_policy.v1.1.json via LoadConfig.
//
// Components (weights from policy):
//   acwr              0.40 — acute:chronic workload ratio
//   acute_load        0.35 — absolute recent training stress
//   activity_completion 0.15 — consistency of intended training
//   hr_elevation_penalty 0.10 — workout HR vs personal resting HR baseline (EWMA), capped penalty
//
// TSS calculation uses Tanaka max HR formula via LoadCalculationContext.
// If age is estimated (DOB unavailable), strand confidence is capped at .medium.

import Foundation

class HelixLoadCalculator {

    let policy:             LoadConfig
    let confidenceEngine:   HelixConfidenceEngine
    let explanationEngine:  HelixExplanationEngine
    let hrElevationBands:   HrElevationThresholds

    init(
        policy: LoadConfig,
        confidenceEngine: HelixConfidenceEngine,
        explanationEngine: HelixExplanationEngine,
        hrElevationBands: HrElevationThresholds
    ) {
        self.policy            = policy
        self.confidenceEngine  = confidenceEngine
        self.explanationEngine = explanationEngine
        self.hrElevationBands = hrElevationBands
    }

    /// Template key for contribution copy (`hr_elevation.*`), aligned with `HelixExplanationEngine` bands.
    func hrElevationContributionKey(score: Double) -> String {
        let t = hrElevationBands
        if score < t.moderateStrainThreshold { return "hr_elevation.high_strain" }
        if score < t.highStrainThreshold { return "hr_elevation.moderate_strain" }
        return "hr_elevation.low_strain"
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

        let acwrBaseline = baselines[.acuteChronicRatio]?.value ?? 1.0
        let acwrScore = acwrScore(acwr: acwr)
        scores[.acuteChronicRatio]          = acwrScore
        originalWeights[.acuteChronicRatio] = w.acwr
        signals.append(HelixSignal(
            identifier: .acuteChronicRatio, rawValue: acwr,
            unit: "ratio", timestamp: Date(), baseline: acwrBaseline,
            deltaFromBaseline: acwr - acwrBaseline, normalizedScore: acwrScore,
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
        let expectedPerWeek   = Double(raw.workouts.count) / 4.0  // approx 28-day average per week
        let completionRatio    = expectedPerWeek > 0 ? min(1.2, Double(recentWorkoutDays) / (expectedPerWeek * 7.0 / 7.0)) : 1.0
        let completionScore    = (completionRatio * 80.0).clampedToHelixScore()
        scores[.activityCompletion]          = completionScore
        originalWeights[.activityCompletion] = w.activityCompletion

        // MARK: 5 — HR elevation (temporal window: today → last 7 days → neutral; see `selectHrElevationWorkoutHRSamples`)
        let hrCfg = policy.hrElevation
        let hrNow = Date()
        let (workoutHRSamples, hrElevationSource) = selectHrElevationWorkoutHRSamples(
            workouts: raw.workouts,
            hrSamples: raw.heartRateSamples,
            now: hrNow,
            calendar: .current
        )

        if let rhrBaseline = baselines[.restingHR]?.value {
            if hrElevationSource == .noneRecent {
                scores[.hrElevation] = 100.0
                originalWeights[.hrElevation] = w.hrElevationPenalty
                signals.append(HelixSignal(
                    identifier: .hrElevation,
                    rawValue: rhrBaseline,
                    unit: "bpm",
                    timestamp: hrNow,
                    baseline: rhrBaseline,
                    deltaFromBaseline: 0,
                    normalizedScore: 100.0,
                    isValid: true,
                    isAnomaly: false
                ))
                #if DEBUG
                print(String(format: "[HELIX DEBUG] hrElevation source=%@ samples=0 avgHR=n/a baseline=%.1f delta=0.0 rawPenalty=0.0 penalty=0.0 score=100.0 (neutral_no_recent_workout_hr)",
                               hrElevationSource.rawValue, rhrBaseline))
                #endif
            } else {
                let sumHR = workoutHRSamples.reduce(0.0) { $0 + $1.value }
                let avgWorkoutHR = sumHR / Double(workoutHRSamples.count)
                let delta = max(0, avgWorkoutHR - rhrBaseline)
                let rawPenalty = delta * hrCfg.costPerBpmAboveBaseline
                let penalty = min(rawPenalty, hrCfg.maximumPenalty)
                let elevationScore = (100.0 - penalty).clampedToHelixScore()
                let ts = workoutHRSamples.map(\.endDate).max() ?? hrNow
                scores[.hrElevation] = elevationScore
                originalWeights[.hrElevation] = w.hrElevationPenalty
                signals.append(HelixSignal(
                    identifier: .hrElevation,
                    rawValue: avgWorkoutHR,
                    unit: "bpm",
                    timestamp: ts,
                    baseline: rhrBaseline,
                    deltaFromBaseline: avgWorkoutHR - rhrBaseline,
                    normalizedScore: elevationScore,
                    isValid: true,
                    isAnomaly: false
                ))
                #if DEBUG
                print(String(format: "[HELIX DEBUG] hrElevation source=%@ samples=%d avgHR=%.1f baseline=%.1f delta=%.1f rawPenalty=%.1f penalty=%.1f score=%.1f",
                             hrElevationSource.rawValue, workoutHRSamples.count,
                             avgWorkoutHR, rhrBaseline, delta, rawPenalty, penalty, elevationScore))
                #endif
            }
        } else {
            missing.append(.hrElevation)
            #if DEBUG
            print("[HELIX DEBUG] hrElevation missing — no restingHR baseline")
            #endif
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
            let weight: Double = adjusted[signal] ?? 0
            contributions.append(SignalContribution(
                signal: signal,
                pointContribution: score * weight,
                explanation: loadContributionExplanationKey(for: signal, acwr: acwr, score: score),
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

        let loadKey = primaryLoadExplanationKey(acwr: acwr)
        let loadNarrative = explanationEngine.explanation(fromKey: loadKey)
        let explanation: String
        if ageContext.ageIsEstimated {
            let ageNote = explanationEngine.explanation(fromKey: "missing_age")
            explanation = ageNote + " " + loadNarrative
        } else {
            explanation = loadNarrative
        }

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

    // MARK: — Contribution copy (template keys only)

    private func loadContributionExplanationKey(
        for signal: SignalIdentifier,
        acwr: Double,
        score: Double
    ) -> String {
        switch signal {
        case .acuteChronicRatio:
            return loadExplanationKey(for: signal, acwr: acwr, score: score)
        case .hrElevation:
            return hrElevationContributionKey(score: score)
        case .trainingVolume:
            if score < 40 { return "training_volume.low" }
            if score < 60 { return "training_volume.moderate" }
            if score < 80 { return "training_volume.optimal" }
            return "training_volume.high"
        case .activityCompletion:
            if score < 50 { return "activity_completion.low" }
            if score < 75 { return "activity_completion.optimal" }
            return "activity_completion.high"
        default:
            return loadExplanationKey(for: signal, acwr: acwr, score: score)
        }
    }
}
