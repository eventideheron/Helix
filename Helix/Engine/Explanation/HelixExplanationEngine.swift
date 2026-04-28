// Engine/HelixExplanationEngine.swift
// Resolves plain-English explanation strings from helix_explanation_policy (bundled as v1.1 filename; `policy_version` may be newer, e.g. 1.2).
// Takes a completed StrandScore or HelixIndex and returns display-ready strings.
//
// This is the only file allowed to read language_templates from the explanation policy.
// No view or calculator should hardcode user-facing strings.

import Foundation

// MARK: — Routing context (optional inputs for template selection)

/// Optional fields for template keys that are not fully determined by `(score, delta)` alone.
struct SignalExplanationRoutingContext: Equatable {
    /// Raw ACWR ratio for `acuteChronicRatio` (matches load calculator banding via explanation policy thresholds).
    var acuteChronicWorkloadRatio: Double? = nil
    /// Absolute resting HR delta in bpm when available (recovery path).
    var restingHRBpmDelta: Double? = nil
}

class HelixExplanationEngine {

    private let policy: HelixExplanationPolicy

    init(policy: HelixExplanationPolicy) {
        self.policy = policy
    }

    // MARK: — Interim tone containment (Pass 1 — remove when policy JSON is cleaned)

    /// Strips prescriptive / coaching sentences from bundled templates without editing JSON in this pass.
    private func sanitizedExplanationText(_ text: String) -> String {
        Self.sanitizedNarrativeText(text)
    }

    /// Shared sanitizer for signal explanations and cross-strand overlay copy (bundled policy may still prescribe actions).
    static func sanitizedNarrativeText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let segments = trimmed.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let kept = segments.filter { !Self.segmentIsPrescriptive($0) }
        guard !kept.isEmpty else { return trimmed }
        return kept.joined(separator: ". ") + "."
    }

    private static func segmentIsPrescriptive(_ segment: String) -> Bool {
        let lower = segment.lowercased()
        for needle in prescriptiveSubstrings {
            if lower.contains(needle) { return true }
        }
        return false
    }

    /// Lowercased substrings; if a clause/segment contains one, the whole segment is dropped (Pass 1 containment).
    private static let prescriptiveSubstrings: [String] = [
        "consider reducing",
        "worth monitoring",
        "today is best approached",
        "best approached with",
        "prioritizing sleep",
        "balance it with adequate recovery",
        "consider rebuilding",
        "meaningful reduction in intensity",
        "rather than complete rest",
        "lower-intensity day",
        "resolved with a meaningful",
        "can help restore balance",
        "until recovery begins to rebound",
        "a useful signal that absorption has resumed",
        "short-term performance may persist",
        "without adjustment",
        "fine for a recovery week",
        "when recovery inputs lag behind demand",
        "today is best approached with caution",
        "this pattern often resolves with one",
        "identify the recovering strand",
        "adjust accordingly",
        "easy movement, good nutrition",
    ]

    // MARK: — Signal explanation

    /// Authoritative dotted template key for a signal (sleep / load / recovery families). Calculators should store this on `SignalContribution.explanation`.
    func languageTemplateKey(
        for signal: SignalIdentifier,
        score: Double,
        deltaFromBaseline: Double,
        context: SignalExplanationRoutingContext = SignalExplanationRoutingContext()
    ) -> String {
        templateKey(for: signal, score: score, delta: deltaFromBaseline, context: context)
    }

    /// Returns the plain-English explanation string for a signal at a given score.
    func explanation(for signal: SignalIdentifier, score: Double, deltaFromBaseline: Double) -> String {
        let key = languageTemplateKey(for: signal, score: score, deltaFromBaseline: deltaFromBaseline)
        return sanitizedExplanationText(resolve(signal: signal, key: key))
    }

    /// Returns explanation string from a pre-computed key (e.g. from HelixSleepCalculator).
    /// Dotted keys (e.g. "respiratory.stable") use language_templates category + variant.
    /// Single-word keys try confidence_language first, then language_templates category default (or first variant).
    func explanation(fromKey key: String) -> String {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2,
           let body = policy.languageTemplates[parts[0]]?[parts[1]] {
            return sanitizedExplanationText(body)
        }
        // Single-word key: try confidence_language then language_templates category default
        if let fromConfidence = policy.confidenceLanguage[key], !fromConfidence.isEmpty {
            return fromConfidence
        }
        if let category = policy.languageTemplates[key] {
            if let defaultStr = category["default"] { return sanitizedExplanationText(defaultStr) }
            if let firstVariant = category.values.first { return sanitizedExplanationText(firstVariant) }
        }
        return key
    }

    // MARK: — Signal card resolution (mapper / provenance)

    /// Deterministic: inputs → template key → policy body → Pass 1 sanitation.
    struct SignalExplanationResolution: Equatable {
        let signalKey: String
        let templateKey: String
        let stateKey: String
        let directionKey: String
        let explanationText: String
    }

    func resolveSignalCardExplanation(
        signal: SignalIdentifier,
        normalizedScore: Double,
        deltaFromBaseline: Double,
        pointContribution: Double,
        context: SignalExplanationRoutingContext = SignalExplanationRoutingContext()
    ) -> SignalExplanationResolution {
        let templateKey = languageTemplateKey(
            for: signal,
            score: normalizedScore,
            deltaFromBaseline: deltaFromBaseline,
            context: context
        )
        let raw = resolve(signal: signal, key: templateKey)
        let body = sanitizedExplanationText(raw)
        let directionKey: String = {
            if pointContribution >= 5 { return "supporting" }
            if pointContribution <= -5 { return "constraining" }
            return "neutral"
        }()
        let stateKey: String = {
            let parts = templateKey.split(separator: ".", maxSplits: 1).map(String.init)
            return parts.count == 2 ? parts[1] : templateKey
        }()
        return SignalExplanationResolution(
            signalKey: signal.rawValue,
            templateKey: templateKey,
            stateKey: stateKey,
            directionKey: directionKey,
            explanationText: body
        )
    }

    /// `confidence_language` key for provenance / display resolution.
    func confidenceSourceKey(for strand: StrandScore) -> String {
        switch strand.confidence {
        case .high:
            return "high"
        case .low:
            return "low"
        case .medium:
            return strand.missingSignals.isEmpty ? "medium_confidence_full_signals" : "medium"
        @unknown default:
            return strand.confidence.rawValue.lowercased()
        }
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

    /// Resolves a string that may be a raw key into human-readable template text.
    /// Tries language_templates (key with ".") then confidence_language (e.g. "medium").
    /// Falls back to sanitized free text (e.g. calculator-composed primary copy).
    func resolveForDisplay(_ text: String) -> String {
        let resolved = explanation(fromKey: text)
        if resolved != text { return resolved }
        let fromConfidence = confidenceString(forKey: text)
        if !fromConfidence.isEmpty { return fromConfidence }
        return sanitizedExplanationText(text)
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
        delta: Double,
        context: SignalExplanationRoutingContext
    ) -> String {
        let thresholds = policy.signalThresholds

        switch signal {
        case .hrv:
            let t = thresholds.hrv
            if delta <= -t.strongDropPercent { return "hrv.strong_drop" }
            if delta <= -t.significantDropPercent { return "hrv.significant_drop" }
            if delta <= -t.notableDropPercent { return "hrv.notable_drop" }
            if delta >= t.significantRisePercent { return "hrv.significant_rise" }
            if delta >= t.notableRisePercent { return "hrv.notable_rise" }
            return "hrv.within_baseline"

        case .restingHR:
            let t = thresholds.restingHr
            if let bpmDelta = context.restingHRBpmDelta {
                if bpmDelta > t.strongRiseBpm        { return "resting_hr.strong_rise" }
                if bpmDelta > t.significantRiseBpm   { return "resting_hr.significant_rise" }
                if bpmDelta > t.notableRiseBpm       { return "resting_hr.notable_rise" }
                if bpmDelta < -t.notableDropBpm      { return "resting_hr.notable_drop" }
                return "resting_hr.within_baseline"
            }
            if score < 50 { return "resting_hr.strong_rise" }
            if score < 65 { return "resting_hr.notable_rise" }
            if score > 75 { return "resting_hr.notable_drop" }
            return "resting_hr.within_baseline"

        case .sleepDuration:
            if score < 40 { return delta > 0 ? "sleep_duration.surplus" : "sleep_duration.strong_deficit" }
            if score < 60 { return delta > 0 ? "sleep_duration.surplus" : "sleep_duration.significant_deficit" }
            if score < 80 { return delta > 0 ? "sleep_duration.surplus" : "sleep_duration.notable_deficit" }
            if delta > 0 { return "sleep_duration.surplus" }
            if delta < -0.05 { return "sleep_duration.notable_deficit" }
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
            if score >= 75 { return "sleep_consistency.consistent" }
            if score >= 50 {
                return delta > 0 ? "sleep_consistency.notable_variance" : "sleep_consistency.consistent"
            }
            return delta > 0 ? "sleep_consistency.significant_variance" : "sleep_consistency.notable_variance"

        case .awakeningsPerHour:
            if score >= 75 { return "disturbance.low" }
            if score >= 50 { return "disturbance.within_baseline" }
            return "disturbance.elevated"

        case .wristTemperature:
            // Matches sleep strand scoring: elevated thermal load is reflected as score < 50.
            if score < 50 { return "wrist_temperature.elevated" }
            let tc = thresholds.wristTemperature
            if delta > tc.notableDeviationCelsius { return "wrist_temperature.elevated" }
            if delta < -tc.notableDeviationCelsius { return "wrist_temperature.depressed" }
            return "wrist_temperature.stable"

        case .overnightHRDip:
            if score > 80 { return "overnight_hr_dip.strong" }
            if score > 50 { return "overnight_hr_dip.moderate" }
            return "overnight_hr_dip.shallow"

        case .respiratoryRecovery:
            if score < 70 { return "respiratory.elevated" }
            return "respiratory.stable"

        case .overnightRespiratory:
            if score < 70 { return "respiratory.elevated" }
            return "respiratory.stable"

        case .acuteChronicRatio:
            if let acwr = context.acuteChronicWorkloadRatio {
                let t = thresholds.acwr
                if acwr > t.veryHighLoadThreshold { return "acwr.very_high" }
                if acwr > t.highLoadThreshold { return "acwr.high" }
                if acwr < t.lowLoadThreshold { return "acwr.low" }
                return "acwr.optimal"
            }
            if score < 40 { return "acwr.very_high" }
            if score < 65 { return "acwr.high" }
            if score < 75 { return "acwr.low" }
            return "acwr.optimal"

        case .trainingVolume:
            if score < 40 { return "training_volume.low" }
            if score < 60 { return "training_volume.moderate" }
            if score < 80 { return "training_volume.optimal" }
            return "training_volume.high"

        case .activityCompletion:
            if score < 50 { return "activity_completion.low" }
            if score < 75 { return "activity_completion.optimal" }
            return "activity_completion.high"

        case .hrElevation:
            let t = thresholds.hrElevation
            if score < t.moderateStrainThreshold { return "hr_elevation.high_strain" }
            if score < t.highStrainThreshold { return "hr_elevation.moderate_strain" }
            return "hr_elevation.low_strain"

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
