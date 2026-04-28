// Features/Dashboard/HelixPreviewSample.swift
// Preview-only sample data. Not referenced from runtime code.
// Used by #Preview blocks in DepthOneView, DepthTwoView, DepthThreeView.

import Foundation

enum HelixPreviewSample {

    /// Single canonical sample index for all depth previews. Display-only; no policy or HealthKit.
    static let index: HelixIndex = {
        let date = Date()
        let interactionTerms = InteractionTerms(
            sleepBoostApplied: 2.0,
            loadCostApplied: 0,
            netInteractionEffect: 2.0
        )
        let sleepStrand = StrandScore(
            strand: .sleep,
            score: 68,
            componentSignals: [],
            missingSignals: [],
            confidence: .medium,
            contributionBreakdown: [
                SignalContribution(signal: .sleepDuration, pointContribution: 12, explanation: "Sleep duration within range.", deltaDescription: "+0.2h"),
                SignalContribution(signal: .deepSleepPercent, pointContribution: 8, explanation: "Deep sleep contribution.", deltaDescription: "−1%"),
                SignalContribution(signal: .remSleepPercent, pointContribution: 6, explanation: "REM sleep stable.", deltaDescription: "0%")
            ],
            primaryExplanation: "Sleep quality is moderate; duration and structure are within your baseline range.",
            calculatedAt: date
        )
        let loadStrand = StrandScore(
            strand: .load,
            score: 78,
            componentSignals: [],
            missingSignals: [],
            confidence: .high,
            contributionBreakdown: [
                SignalContribution(signal: .acuteChronicRatio, pointContribution: 14, explanation: "ACWR in optimal band.", deltaDescription: "1.02"),
                SignalContribution(signal: .trainingVolume, pointContribution: 10, explanation: "Volume aligned with baseline.", deltaDescription: "+5 TSS"),
                SignalContribution(signal: .activityCompletion, pointContribution: 6, explanation: "Consistent training days.", deltaDescription: "4/7")
            ],
            primaryExplanation: "Training load is well-balanced; acute load matches your recent baseline.",
            calculatedAt: date
        )
        let recoveryStrand = StrandScore(
            strand: .recovery,
            score: 72,
            componentSignals: [],
            missingSignals: [],
            confidence: .medium,
            contributionBreakdown: [
                SignalContribution(signal: .hrv, pointContribution: 15, explanation: "HRV above baseline.", deltaDescription: "+8 ms"),
                SignalContribution(signal: .restingHR, pointContribution: 6, explanation: "Resting HR normal.", deltaDescription: "−2 bpm"),
                SignalContribution(signal: .overnightHRDip, pointContribution: 4, explanation: "Overnight dip present.", deltaDescription: "−3 bpm")
            ],
            primaryExplanation: "Recovery signals are in a good range; HRV supports readiness.",
            calculatedAt: date
        )
        return HelixIndex(
            score: 72,
            posture: .moderate,
            sleepStrand: sleepStrand,
            loadStrand: loadStrand,
            recoveryStrand: recoveryStrand,
            overallConfidence: .medium,
            balancePenalty: 0,
            recoveryGateApplied: false,
            recoveryGateLevel: nil,
            interactionTerms: interactionTerms,
            date: date
        )
    }()
}
