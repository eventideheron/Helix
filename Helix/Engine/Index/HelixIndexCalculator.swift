// Engine/HelixIndexCalculator.swift
// v1.1: Uses .clampedToHelixScore() throughout instead of inline min/max.
// Operation order is documented and matches helix_policy exactly:
//   1. Interaction terms (modifies adjusted_recovery)
//   2. Weighted composite
//   3. Recovery gate — SEVERE checked first (lower threshold, worse state)
//   4. Balance penalty
//   5. Final clamp and posture

import Foundation

class HelixIndexCalculator {

    private let policy: IndexConfig

    init(policy: IndexConfig) {
        self.policy = policy
    }

    func calculate(
        sleep: StrandScore,
        load: StrandScore,
        recovery: StrandScore
    ) -> HelixIndex {

        let w           = policy.weights
        let interaction = policy.interactionTerms

        // Step 1 — Interaction terms
        // sleep_boost: good sleep amplifies recovery
        // load_cost:   high load suppresses recovery
        // Max net effect ≈ +8 / -10 points on adjusted_recovery (per policy note)
        let sleepBoost = (sleep.score - 50.0) / interaction.sleepBoostDivisor
        let loadCost   = (load.score - 50.0)  / interaction.loadCostDivisor

        let adjustedRecovery = (recovery.score + sleepBoost - loadCost)
            .clampedToHelixScore()

        #if DEBUG
        let _netEffect = sleepBoost - loadCost
        let _preComposite = w.sleep * sleep.score + w.recovery * adjustedRecovery + w.load * load.score
        let _pct = _preComposite > 0 ? abs(_netEffect / _preComposite) * 100.0 : 0.0
        print(String(format: "[HELIX DEBUG] interaction_terms: sleepBoost=%.3f loadCost=%.3f net=%.3f effect=%.1f%% of composite",
              sleepBoost, loadCost, _netEffect, _pct))
        #endif

        // Step 2 — Weighted composite
        var composite =
              w.sleep    * sleep.score
            + w.recovery * adjustedRecovery
            + w.load     * load.score

        // Step 3 — Recovery gate
        // IMPORTANT: Check SEVERE first. Severe (< 20) is the worse physiological state
        // and applies the stronger suppression (0.55). Checking critical first would
        // incorrectly apply the weaker multiplier (0.75) to the more serious condition.
        let gate = policy.recoveryGate
        let gateLevel: RecoveryGateLevel?

        if recovery.score < gate.severeThreshold {
            composite  *= gate.severeMultiplier
            gateLevel   = .severe
        } else if recovery.score < gate.criticalThreshold {
            composite  *= gate.criticalMultiplier
            gateLevel   = .critical
        } else {
            gateLevel   = nil
        }

        // Step 4 — Balance penalty
        // Modest nudge (max -12 pts) toward strand coherence.
        // A deliberate recovery week with low load is expected to incur a small penalty.
        let bp     = policy.balancePenalty
        let scores = [sleep.score, load.score, recovery.score]
        let mean   = scores.reduce(0, +) / 3.0
        let variance = scores.map { pow($0 - mean, 2) }.reduce(0, +) / 3.0
        let stdDev = variance.squareRoot()
        let penalty = Swift.min(bp.maximumPenalty, stdDev * bp.varianceMultiplier)

        composite -= penalty

        // Step 5 — Clamp and posture
        let finalScore = composite.clampedToHelixScore()
        let posture    = determinePosture(score: finalScore)

        return HelixIndex(
            score: finalScore,
            posture: posture,
            sleepStrand: sleep,
            loadStrand: load,
            recoveryStrand: recovery,
            overallConfidence: lowestConfidence(
                sleep.confidence,
                load.confidence,
                recovery.confidence
            ),
            balancePenalty: penalty,
            recoveryGateApplied: gateLevel != nil,
            recoveryGateLevel: gateLevel,
            interactionTerms: InteractionTerms(
                sleepBoostApplied: sleepBoost,
                loadCostApplied: loadCost,
                netInteractionEffect: sleepBoost - loadCost
            ),
            date: Date()
        )
    }

    private func determinePosture(score: Double) -> HelixPosture {
        let t = policy.postureThresholds
        switch score {
        case t.pursue...:           return .pursue
        case t.moderate..<t.pursue: return .moderate
        default:                    return .restore
        }
    }

    private func lowestConfidence(_ levels: ConfidenceLevel...) -> ConfidenceLevel {
        if levels.contains(.low)    { return .low }
        if levels.contains(.medium) { return .medium }
        return .high
    }
}
