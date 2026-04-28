// Engine/CrossStrand/HelixCrossStrandEngine.swift
// Strictly additive insight layer — reads a completed HelixIndex, evaluates V1 patterns,
// returns zero or one CrossStrandInsight for display at depth 2 and above.
//
// INV-3: Gate C/D separation. This engine is Gate D — it never modifies strand scores
// or the composite index. It only produces display text.
//
// v1.1: Added load_dominant_strain pattern. Contradiction now enforces load_lt upper
// bound from policy. Defensive score validation added per CG implementation note.

import Foundation

// MARK: — Output model

struct CrossStrandInsight {
    let patternID:      String
    let depth2Headline: String
    let depth2Body:     String
    let depth3Headline: String
    let depth3Body:     String
}

// MARK: — Engine

class HelixCrossStrandEngine {

    private let policy: CrossStrandPolicy

    init(policy: CrossStrandPolicy) {
        self.policy = policy
    }

    /// Returns zero or one insight. Patterns are evaluated in policy-defined priority order.
    /// Returns nil when engine-wide suppression conditions are met or scores are invalid.
    func evaluate(index: HelixIndex, baselineDays: Int) -> CrossStrandInsight? {
        // Engine-wide suppression
        if index.overallConfidence == .low { return nil }
        if baselineDays < policy.suppression.suppressIfBaselineDaysLt { return nil }

        let sleep    = index.sleepStrand.score
        let load     = index.loadStrand.score
        let recovery = index.recoveryStrand.score

        // CG Note 2: Defensive score validation. Engine must not crash or produce
        // spurious insights if called with edge-case score values. Not coupled to
        // app state — purely score-path safety.
        guard sleep.isFinite, load.isFinite, recovery.isFinite,
              (0...100).contains(sleep),
              (0...100).contains(load),
              (0...100).contains(recovery)
        else { return nil }

        for patternID in policy.patternPriority {
            switch patternID {
            case "suppressed_recovery":
                if let insight = evaluateSuppressedRecovery(sleep: sleep, load: load, recovery: recovery) { return insight }
            case "load_dominant_strain":
                if let insight = evaluateLoadDominantStrain(sleep: sleep, load: load, recovery: recovery) { return insight }
            case "contradiction":
                if let insight = evaluateContradiction(sleep: sleep, load: load, recovery: recovery) { return insight }
            case "alignment":
                if let insight = evaluateAlignment(sleep: sleep, load: load, recovery: recovery) { return insight }
            default:
                break
            }
        }
        return nil
    }

    // MARK: — Pattern evaluators

    private func evaluateSuppressedRecovery(sleep: Double, load: Double, recovery: Double) -> CrossStrandInsight? {
        let c = policy.patterns.suppressedRecovery.conditions
        guard sleep >= c.sleepGte,
              load >= c.loadGte,
              recovery <= c.recoveryLte
        else { return nil }
        let lang = policy.patterns.suppressedRecovery.language
        return CrossStrandInsight(
            patternID:      "suppressed_recovery",
            depth2Headline: lang.depth2.headline,
            depth2Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth2.body),
            depth3Headline: lang.depth3.headline,
            depth3Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth3.body)
        )
    }

    private func evaluateLoadDominantStrain(sleep: Double, load: Double, recovery: Double) -> CrossStrandInsight? {
        let c = policy.patterns.loadDominantStrain.conditions
        guard load >= c.loadGte,
              sleep <= c.sleepLte,
              recovery <= c.recoveryLte
        else { return nil }
        let lang = policy.patterns.loadDominantStrain.language
        return CrossStrandInsight(
            patternID:      "load_dominant_strain",
            depth2Headline: lang.depth2.headline,
            depth2Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth2.body),
            depth3Headline: lang.depth3.headline,
            depth3Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth3.body)
        )
    }

    private func evaluateContradiction(sleep: Double, load: Double, recovery: Double) -> CrossStrandInsight? {
        let c = policy.patterns.contradiction.conditions
        guard sleep >= c.sleepGte,
              recovery <= c.recoveryLte,
              load >= c.loadGte,
              c.loadLt.map({ load < $0 }) ?? true
              // loadLt: enforces upper load bound from policy.
              // If nil (not present in JSON), the guard passes — no ceiling applied.
        else { return nil }
        let lang = policy.patterns.contradiction.language
        return CrossStrandInsight(
            patternID:      "contradiction",
            depth2Headline: lang.depth2.headline,
            depth2Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth2.body),
            depth3Headline: lang.depth3.headline,
            depth3Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth3.body)
        )
    }

    private func evaluateAlignment(sleep: Double, load: Double, recovery: Double) -> CrossStrandInsight? {
        // CG Note 1: alignment_strong and alignment_suppressed are distinct surfaced meanings.
        // strong = positive readiness coherence; suppressed = cautionary whole-system suppression.
        // Evaluated in this order — strong takes precedence if thresholds somehow overlap.
        let strongThreshold = policy.patterns.alignment.conditions.strong.allGte
        if let t = strongThreshold, sleep >= t, load >= t, recovery >= t {
            let lang = policy.patterns.alignment.language.strong
            return CrossStrandInsight(
                patternID:      "alignment_strong",
                depth2Headline: lang.depth2.headline,
                depth2Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth2.body),
                depth3Headline: lang.depth3.headline,
                depth3Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth3.body)
            )
        }

        let suppressedThreshold = policy.patterns.alignment.conditions.suppressed.allLte
        if let t = suppressedThreshold, sleep <= t, load <= t, recovery <= t {
            let lang = policy.patterns.alignment.language.suppressed
            return CrossStrandInsight(
                patternID:      "alignment_suppressed",
                depth2Headline: lang.depth2.headline,
                depth2Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth2.body),
                depth3Headline: lang.depth3.headline,
                depth3Body:     HelixExplanationEngine.sanitizedNarrativeText(lang.depth3.body)
            )
        }

        return nil
    }
}
