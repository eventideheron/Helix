// Engine/HelixExplanationEngine.swift
// Resolves plain-English explanation strings from helix_explanation_policy.v1.1.json.
// Takes a completed StrandScore or HelixIndex and returns display-ready strings.
//
// This is the only file allowed to read language_templates from the explanation policy.
// No view or calculator should hardcode user-facing strings.

import Foundation

class HelixExplanationEngine {

    private let policy: HelixExplanationPolicy

    init(policy: HelixExplanationPolicy) {
        self.policy = policy
    }

    // MARK: — Signal explanation

    /// Returns the plain-English explanation string for a signal at a given score.
    func explanation(for signal: SignalIdentifier, score: Double, deltaFromBaseline: Double) -> String {
        let key = templateKey(for: signal, score: score, delta: deltaFromBaseline)
        return resolve(signal: signal, key: key)
    }

    /// Returns explanation string from a pre-computed key (e.g. from HelixSleepCalculator).
    func explanation(fromKey key: String) -> String {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return key }
        return policy.languageTemplates[parts[0]]?[parts[1]] ?? key
    }

    // MARK: — Posture language

    func postureHeadline(for posture: HelixPosture) -> String {
        policy.postureLanguage[posture.rawValue.lowercased()]?.headline ?? posture.rawValue
    }

    func postureSubtext(for posture: HelixPosture) -> String {
        policy.postureLanguage[posture.rawValue.lowercased()]?.subtext ?? ""
    }

    // MARK: — Confidence language

    func confidenceString(for level: ConfidenceLevel) -> String {
        policy.confidenceLanguage[level.rawValue.lowercased()] ?? ""
    }

    func confidenceString(forKey key: String) -> String {
        policy.confidenceLanguage[key] ?? ""
    }

    // MARK: — Decomposition builder
    // Takes a strand's contribution breakdown and returns sorted, display-ready contributions.

    func buildDecomposition(
        from strand: StrandScore,
        confidenceLevel: ConfidenceLevel
    ) -> DecompositionView {

        let config       = policy.decomposition
        let maxShown     = config.maximumContributorsShown
        let contributions = strand.contributionBreakdown
            .sorted {
                config.sortBy == "absolute_impact"
                    ? abs($0.pointContribution) > abs($1.pointContribution)
                    : $0.pointContribution > $1.pointContribution
            }
            .prefix(maxShown)

        return DecompositionView(
            topContributors:       Array(contributions),
            confidence:            confidenceLevel,
            missingSignals:        strand.missingSignals,
            showPointContributions: config.showPointContribution,
            showDeltaFromBaseline:  config.showDeltaFromBaseline
        )
    }

    // MARK: — Private template resolution

    private func templateKey(
        for signal: SignalIdentifier,
        score: Double,
        delta: Double
    ) -> String {
        let thresholds = policy.signalThresholds

        switch signal {
        case .hrv:
            let t = thresholds.hrv
            if delta < -t.strongDropPercent      { return "hrv.strong_drop" }
            if delta < -t.significantDropPercent  { return "hrv.significant_drop" }
            if delta < -t.notableDropPercent      { return "hrv.notable_drop" }
            if delta > t.significantRisePercent   { return "hrv.significant_rise" }
            if delta > t.notableRisePercent        { return "hrv.notable_rise" }
            return "hrv.within_baseline"

        case .restingHR:
            let t = thresholds.restingHr
            let bpmDelta = delta * 60  // approximate — engine passes normalised delta
            if bpmDelta > t.strongRiseBpm        { return "resting_hr.strong_rise" }
            if bpmDelta > t.significantRiseBpm    { return "resting_hr.significant_rise" }
            if bpmDelta > t.notableRiseBpm        { return "resting_hr.notable_rise" }
            if bpmDelta < -t.notableDropBpm       { return "resting_hr.notable_drop" }
            return "resting_hr.within_baseline"

        case .sleepDuration:
            if score < 40 { return "sleep_duration.strong_deficit" }
            if score < 60 { return "sleep_duration.significant_deficit" }
            if score < 80 { return "sleep_duration.notable_deficit" }
            if delta > 0  { return "sleep_duration.surplus" }
            return "sleep_duration.within_optimal"

        case .deepSleepPercent:
            if score < 45  { return "deep_sleep.below_baseline" }
            if score > 65  { return "deep_sleep.above_baseline" }
            return "deep_sleep.within_baseline"

        case .remSleepPercent:
            if score < 45  { return "rem_sleep.below_baseline" }
            if score > 65  { return "rem_sleep.above_baseline" }
            return "rem_sleep.within_baseline"

        case .sleepConsistency:
            if score < 50 { return "sleep_consistency.significant_variance" }
            if score < 75 { return "sleep_consistency.notable_variance" }
            return "sleep_consistency.consistent"

        case .wristTemperature:
            if delta > 0.4  { return "wrist_temperature.elevated" }
            if delta < -0.4 { return "wrist_temperature.depressed" }
            return "wrist_temperature.stable"

        case .overnightHRDip, .respiratoryRecovery:
            if score > 80 { return "overnight_hr_dip.strong" }
            if score > 50 { return "overnight_hr_dip.moderate" }
            return "overnight_hr_dip.shallow"

        case .overnightRespiratory:
            if score < 70 { return "respiratory.elevated" }
            return "respiratory.stable"

        case .acuteChronicRatio:
            // delta here is (acwr - 1.0) — use score bands
            if score < 40 { return "acwr.very_high" }
            if score < 65 { return "acwr.high" }
            if score < 75 { return "acwr.low" }
            return "acwr.optimal"

        default:
            return signal.explanationKey
        }
    }

    private func resolve(signal: SignalIdentifier, key: String) -> String {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return policy.languageTemplates[signal.explanationKey]?[key] ?? key
        }
        return policy.languageTemplates[parts[0]]?[parts[1]] ?? key
    }
}
