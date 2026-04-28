// Features/Dashboard/SignalExplanationCardView.swift
// Depth 3 signal explanation cards — presentation only; data via `SignalCardMapper`.

import SwiftUI

// MARK: — Models

enum ExplanationCardStrand: String, CaseIterable {
    case sleep
    case load
    case recovery
}

enum SignalCardDirection {
    case supporting
    case constraining
    case neutral
}

struct SignalExplanationCardModel: Identifiable {
    var id: String
    var signalKey: String
    var title: String
    var strand: ExplanationCardStrand
    /// Trailing template variant (e.g. `notable_drop`).
    var stateKey: String
    /// Full dotted template id from `HelixExplanationEngine` (e.g. `hrv.notable_drop`).
    var templateKey: String
    var direction: SignalCardDirection
    /// `supporting` | `constraining` | `neutral` — provenance / DEBUG.
    var directionKey: String
    var confidence: ConfidenceLevel
    /// `confidence_language` lookup key (e.g. `medium_confidence_full_signals`).
    var confidenceSourceKey: String?
    var valueText: String
    var baselineText: String?
    var deltaText: String?
    var pointContributionText: String?
    var headlineText: String?
    /// Physiological explanation body (sanitized in engine); separate from confidence / caveats.
    var explanationText: String
    var implicationText: String?
    var confidenceText: String
    var missingSignalNotes: [String]
    /// Sample / marketing preview only — not produced by `SignalCardMapper`.
    var isCrossStrandSample: Bool = false
}

// MARK: — View

struct SignalExplanationCardView: View {
    let model: SignalExplanationCardModel

    private var strandTint: Color {
        switch model.strand {
        case .sleep:    return HelixTheme.sleepColor
        case .load:     return HelixTheme.loadColor
        case .recovery: return HelixTheme.recoveryColor
        }
    }

    private var directionTint: Color {
        switch model.direction {
        case .supporting:   return HelixTheme.confidenceHigh
        case .constraining: return HelixTheme.restoreColor
        case .neutral:      return HelixTheme.textSecondary
        }
    }

    private var directionLabel: String {
        switch model.direction {
        case .supporting:   return "Supporting"
        case .constraining: return "Constraining"
        case .neutral:      return "Neutral"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isCrossStrandSample {
                Text("CROSS-STRAND")
                    .font(HelixTypography.microLabel)
                    .foregroundColor(HelixTheme.textSecondary)
                    .padding(.bottom, 6)
            }

            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(strandTint)
                    .frame(width: 3, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.title.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(strandTint)
                        Spacer()
                        Text(model.stateKey)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(HelixTheme.textSecondary.opacity(0.85))
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Text(directionLabel)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(directionTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(directionTint.opacity(0.12))
                            .cornerRadius(4)

                        if let pts = model.pointContributionText {
                            Text(pts)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(HelixTheme.textPrimary)
                        }
                    }
                }
            }
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Value")
                        .font(HelixTypography.captionBody)
                        .foregroundColor(HelixTheme.textSecondary)
                    Spacer()
                    Text(model.valueText)
                        .font(HelixTypography.signalLabel)
                        .foregroundColor(HelixTheme.textPrimary)
                }
                if let baseline = model.baselineText {
                    HStack {
                        Text("Baseline")
                            .font(HelixTypography.captionBody)
                            .foregroundColor(HelixTheme.textSecondary)
                        Spacer()
                        Text(baseline)
                            .font(HelixTypography.captionBody)
                            .foregroundColor(HelixTheme.textPrimary)
                    }
                }
                if let delta = model.deltaText, !delta.isEmpty {
                    HStack {
                        Text("Delta")
                            .font(HelixTypography.captionBody)
                            .foregroundColor(HelixTheme.textSecondary)
                        Spacer()
                        Text(delta)
                            .font(HelixTypography.captionBody)
                            .foregroundColor(HelixTheme.textSecondary)
                    }
                }
            }
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                if let headline = model.headlineText, !headline.isEmpty {
                    Text(headline)
                        .font(HelixTypography.signalLabel)
                        .foregroundColor(HelixTheme.textPrimary)
                }

                Text(model.explanationText)
                    .font(HelixTypography.explanationBody)
                    .foregroundColor(HelixTheme.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let implication = model.implicationText, !implication.isEmpty {
                    Text(implication)
                        .font(HelixTypography.captionBody)
                        .foregroundColor(HelixTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 8) {
                ConfidenceIndicator(confidence: model.confidence)

                Text(model.confidenceText)
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 4)

            if !model.missingSignalNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.missingSignalNotes, id: \.self) { note in
                        Text(note)
                            .font(HelixTypography.captionBody)
                            .foregroundColor(HelixTheme.confidenceMedium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)
            }

            #if DEBUG
            if !model.templateKey.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEBUG · provenance")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(HelixTheme.textSecondary.opacity(0.7))
                    Text("signal \(model.signalKey) · template \(model.templateKey) · direction \(model.directionKey)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(HelixTheme.textSecondary.opacity(0.65))
                    if let ck = model.confidenceSourceKey {
                        Text("confidence_key \(ck)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(HelixTheme.textSecondary.opacity(0.65))
                    }
                }
                .padding(.top, 10)
            }
            #endif
        }
        .padding(16)
        .background(HelixTheme.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(HelixTheme.borderSubtle, lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

// MARK: — Previews

#if DEBUG
#Preview("Signal Cards") {
    ScrollView {
        VStack(spacing: 16) {
            SignalExplanationCardView(model: .previewCrossStrand)
            SignalExplanationCardView(model: .previewSleepDuration)
            SignalExplanationCardView(model: .previewACWR)
            SignalExplanationCardView(model: .previewHRV)
            SignalExplanationCardView(model: .previewWristTemp)
        }
        .padding()
    }
    .background(HelixTheme.backgroundPrimary)
}

private extension SignalExplanationCardModel {
    static let previewCrossStrand = SignalExplanationCardModel(
        id: "sample_cross",
        signalKey: "cross_strand",
        title: "Strand balance",
        strand: .recovery,
        stateKey: "mixed",
        templateKey: "cross_strand.mixed",
        direction: .neutral,
        directionKey: "neutral",
        confidence: .medium,
        confidenceSourceKey: "medium",
        valueText: "—",
        baselineText: nil,
        deltaText: nil,
        pointContributionText: nil,
        headlineText: nil,
        explanationText: "Sleep and recovery scores diverge today — load is moderate while recovery is soft. The index reflects the tighter strand.",
        implicationText: nil,
        confidenceText: "One or more signals unavailable — score estimated from remaining data.",
        missingSignalNotes: [],
        isCrossStrandSample: true
    )

    static let previewSleepDuration = SignalExplanationCardModel(
        id: "sample_sleep_duration",
        signalKey: "sleep_duration",
        title: "Sleep Duration",
        strand: .sleep,
        stateKey: "notable_deficit",
        templateKey: "sleep_duration.notable_deficit",
        direction: .constraining,
        directionKey: "constraining",
        confidence: .high,
        confidenceSourceKey: "high",
        valueText: "6h 40m",
        baselineText: "7h 30m",
        deltaText: "−12%",
        pointContributionText: "-8",
        headlineText: nil,
        explanationText: "Sleep duration is slightly below your baseline.",
        implicationText: nil,
        confidenceText: "All signals present — high confidence.",
        missingSignalNotes: []
    )

    static let previewACWR = SignalExplanationCardModel(
        id: "sample_acwr",
        signalKey: "acute_chronic_ratio",
        title: "ACWR",
        strand: .load,
        stateKey: "high",
        templateKey: "acwr.high",
        direction: .constraining,
        directionKey: "constraining",
        confidence: .high,
        confidenceSourceKey: "high",
        valueText: "1.18 ratio",
        baselineText: "1.00 ratio",
        deltaText: "+0.18",
        pointContributionText: "-11",
        headlineText: nil,
        explanationText: "Training load is above your recent average.",
        implicationText: nil,
        confidenceText: "All signals present — high confidence.",
        missingSignalNotes: []
    )

    static let previewHRV = SignalExplanationCardModel(
        id: "sample_hrv",
        signalKey: "hrv",
        title: "HRV",
        strand: .recovery,
        stateKey: "notable_drop",
        templateKey: "hrv.notable_drop",
        direction: .constraining,
        directionKey: "constraining",
        confidence: .high,
        confidenceSourceKey: "high",
        valueText: "42 ms",
        baselineText: "54 ms",
        deltaText: "−22%",
        pointContributionText: "-14",
        headlineText: nil,
        explanationText: "HRV is slightly below your baseline — mild autonomic stress is present.",
        implicationText: nil,
        confidenceText: "All signals present — high confidence.",
        missingSignalNotes: []
    )

    static let previewWristTemp = SignalExplanationCardModel(
        id: "sample_wrist_temp",
        signalKey: "wrist_temperature",
        title: "Wrist Temperature",
        strand: .sleep,
        stateKey: "elevated",
        templateKey: "wrist_temperature.elevated",
        direction: .constraining,
        directionKey: "constraining",
        confidence: .medium,
        confidenceSourceKey: "medium",
        valueText: "+0.42 °C Δ",
        baselineText: "0.00 °C",
        deltaText: "vs baseline",
        pointContributionText: "-5",
        headlineText: nil,
        explanationText: "Overnight wrist temperature was above your baseline — this can reflect immune activity, metabolic processing, or hormonal variation.",
        implicationText: nil,
        confidenceText: "One or more signals unavailable — score estimated from remaining data.",
        missingSignalNotes: ["SpO2 not available — excluded from score"]
    )
}
#endif
