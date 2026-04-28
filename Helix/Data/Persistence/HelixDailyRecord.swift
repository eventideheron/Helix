// Models/HelixDailyRecord.swift
// v1.2: Expanded from the original thin record to support the full product roadmap.
//
// ChatGPT audit item #8: "Change persistence shape to support the roadmap, not just v0 UI."
// The original record stored only the composite scores and one explanation string.
// That is insufficient for:
//   - Depth 3 decomposition (12-spoke contribution breakdown)
//   - Today In History engine (needs signal-level history, trigger records)
//   - Seasonal pattern detection (needs strand scores + confidence + missing signals)
//   - Trend arrows (needs per-signal delta history)
//   - Confidence explanation (needs reason codes, not just level)
//
// Design decision (Claude synthesis): persist derived state, not raw HealthKit samples.
// Raw samples remain in HealthKit. App owns derived/computed state.
// Baseline state lives in HelixBaselineSnapshot (separate model, already defined).

import SwiftData
import Foundation


// MARK: — Daily composite record

@Model
class HelixDailyRecord {

    // Identity
    var date: Date = Date()

    // Composite
    var helixIndex: Double = 0.0
    var postureRaw: String = ""
    var confidenceRaw: String = ""
    var balancePenalty: Double = 0.0
    var recoveryGateApplied: Bool = false
    var recoveryGateLevelRaw: String?   // "severe" | "critical" | nil

    // Strand scores
    var sleepScore: Double = 0.0
    var loadScore: Double = 0.0
    var recoveryScore: Double = 0.0

    // Strand confidence (needed for UI indicators per strand, not just composite)
    var sleepConfidenceRaw: String = ""
    var loadConfidenceRaw: String = ""
    var recoveryConfidenceRaw: String = ""

    // Interaction terms (for decomposition display)
    var sleepBoostApplied: Double = 0.0
    var loadCostApplied: Double = 0.0

    // Signal contributions — encoded as JSON for flexibility
    // Decodes to [SignalContribution] at read time
    var sleepContributionsJSON: String = "[]"
    var loadContributionsJSON: String = "[]"
    var recoveryContributionsJSON: String = "[]"

    // Missing signals per strand — encoded as comma-separated rawValues
    var sleepMissingSignalsRaw: String = ""
    var loadMissingSignalsRaw: String = ""
    var recoveryMissingSignalsRaw: String = ""

    // Primary explanation strings (shown in depth-2 view)
    var sleepPrimaryExplanation: String = ""
    var loadPrimaryExplanation: String = ""
    var recoveryPrimaryExplanation: String = ""

    // History engine fields
    var isTodayInHistory: Bool = false
    var historyTriggerRaw: String?       // e.g. "personal_record", "streak_milestone"
    var historyMessage: String?

    // Baseline maturity at time of calculation
    var baselineMaturityStageRaw: String = "learning"  // "learning" | "developing" | "established" | "mature"
    var dataPointCountAtCalculation: Int = 0

    // App state at time of calculation (`nil` = row written before this field existed; migration-safe).
    var appStateRaw: String? = nil

    /// Resolved persisted app state for display or analytics (legacy rows → `"unknown"`).
    var resolvedAppStateRaw: String {
        appStateRaw ?? "unknown"
    }

    /// Default initializer so that @Model is satisfied on all platforms (e.g. widget).
    /// App code uses init(from index:appState:dataPointCount:) when HelixIndex is available.
    init() {
        self.date                        = Date()
        self.helixIndex                  = 0
        self.postureRaw                  = ""
        self.confidenceRaw               = ""
        self.balancePenalty              = 0
        self.recoveryGateApplied         = false
        self.recoveryGateLevelRaw         = nil
        self.sleepScore                  = 0
        self.loadScore                   = 0
        self.recoveryScore               = 0
        self.sleepConfidenceRaw          = ""
        self.loadConfidenceRaw           = ""
        self.recoveryConfidenceRaw       = ""
        self.sleepBoostApplied           = 0
        self.loadCostApplied             = 0
        self.sleepContributionsJSON      = "[]"
        self.loadContributionsJSON       = "[]"
        self.recoveryContributionsJSON   = "[]"
        self.sleepMissingSignalsRaw      = ""
        self.loadMissingSignalsRaw       = ""
        self.recoveryMissingSignalsRaw   = ""
        self.sleepPrimaryExplanation     = ""
        self.loadPrimaryExplanation      = ""
        self.recoveryPrimaryExplanation  = ""
        self.isTodayInHistory            = false
        self.historyTriggerRaw           = nil
        self.historyMessage              = nil
        self.baselineMaturityStageRaw    = "learning"
        self.dataPointCountAtCalculation = 0
        self.appStateRaw                 = "unknown"
    }

    #if canImport(UIKit)
    init(from index: HelixIndex, appState: HelixAppState, dataPointCount: Int) {
        self.date                   = index.date
        self.helixIndex             = index.score
        self.postureRaw             = index.posture.rawValue
        self.confidenceRaw          = index.overallConfidence.rawValue
        self.balancePenalty         = index.balancePenalty
        self.recoveryGateApplied    = index.recoveryGateApplied
        self.recoveryGateLevelRaw   = index.recoveryGateLevel?.rawValue

        self.sleepScore             = index.sleepStrand.score
        self.loadScore              = index.loadStrand.score
        self.recoveryScore          = index.recoveryStrand.score

        self.sleepConfidenceRaw     = index.sleepStrand.confidence.rawValue
        self.loadConfidenceRaw      = index.loadStrand.confidence.rawValue
        self.recoveryConfidenceRaw  = index.recoveryStrand.confidence.rawValue

        self.sleepBoostApplied      = index.interactionTerms.sleepBoostApplied
        self.loadCostApplied        = index.interactionTerms.loadCostApplied

        self.sleepContributionsJSON     = Self.encode(index.sleepStrand.contributionBreakdown)
        self.loadContributionsJSON      = Self.encode(index.loadStrand.contributionBreakdown)
        self.recoveryContributionsJSON  = Self.encode(index.recoveryStrand.contributionBreakdown)

        self.sleepMissingSignalsRaw    = index.sleepStrand.missingSignals.map(\.rawValue).joined(separator: ",")
        self.loadMissingSignalsRaw     = index.loadStrand.missingSignals.map(\.rawValue).joined(separator: ",")
        self.recoveryMissingSignalsRaw = index.recoveryStrand.missingSignals.map(\.rawValue).joined(separator: ",")

        self.sleepPrimaryExplanation    = index.sleepStrand.primaryExplanation
        self.loadPrimaryExplanation     = index.loadStrand.primaryExplanation
        self.recoveryPrimaryExplanation = index.recoveryStrand.primaryExplanation

        self.isTodayInHistory           = false
        self.historyTriggerRaw          = nil
        self.historyMessage             = nil

        self.dataPointCountAtCalculation = dataPointCount
        self.baselineMaturityStageRaw    = Self.maturityStage(for: dataPointCount)
        self.appStateRaw                 = appState.persistedString
    }

    #endif
    // MARK: — Typed accessors

    var posture: HelixPosture {
        HelixPosture(rawValue: postureRaw) ?? .moderate
    }

    var confidence: ConfidenceLevel {
        ConfidenceLevel(rawValue: confidenceRaw) ?? .medium
    }

    var sleepMissingSignals: [SignalIdentifier] {
        Self.decodeSignals(sleepMissingSignalsRaw)
    }

    var loadMissingSignals: [SignalIdentifier] {
        Self.decodeSignals(loadMissingSignalsRaw)
    }

    var recoveryMissingSignals: [SignalIdentifier] {
        Self.decodeSignals(recoveryMissingSignalsRaw)
    }

    var sleepContributions: [SignalContribution] {
        Self.decodeContributions(sleepContributionsJSON)
    }

    var loadContributions: [SignalContribution] {
        Self.decodeContributions(loadContributionsJSON)
    }

    var recoveryContributions: [SignalContribution] {
        Self.decodeContributions(recoveryContributionsJSON)
    }

    // MARK: — Private helpers

    static func encode(_ contributions: [SignalContribution]) -> String {
        let dicts = contributions.map { c -> [String: String] in
            [
                "signal": c.signal.rawValue,
                "points": String(c.pointContribution),
                "explanation": c.explanation,
                "delta": c.deltaDescription
            ]
        }
        let data = try? JSONSerialization.data(withJSONObject: dicts)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private static func decodeContributions(_ json: String) -> [SignalContribution] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }

        return array.compactMap { dict -> SignalContribution? in
            guard let signalRaw = dict["signal"],
                  let signal = SignalIdentifier(rawValue: signalRaw),
                  let pointsStr = dict["points"],
                  let points = Double(pointsStr),
                  let explanation = dict["explanation"],
                  let delta = dict["delta"]
            else { return nil }
            return SignalContribution(
                signal: signal,
                pointContribution: points,
                explanation: explanation,
                deltaDescription: delta
            )
        }
    }

    private static func decodeSignals(_ raw: String) -> [SignalIdentifier] {
        raw.split(separator: ",")
            .compactMap { SignalIdentifier(rawValue: String($0)) }
    }

    static func maturityStage(for dataPoints: Int) -> String {
        switch dataPoints {
        case 0..<14:  return "learning"
        case 14..<90: return "developing"
        case 90..<365: return "established"
        default:       return "mature"
        }
    }
}

// MARK: — History trigger record
// Stored separately so the history engine can query triggers independently.

@Model
class HelixTriggerRecord {
    var date: Date = Date()
    var triggerTypeRaw: String = ""    // "personal_record" | "strand_record" | "streak_milestone" etc.
    var strandRaw: String? = nil         // nil for composite triggers
    var message: String = ""
    var metricValue: Double = 0.0
    var thresholdPercentile: Double? = nil

    init() {
        self.date = Date()
        self.triggerTypeRaw = ""
        self.strandRaw = nil
        self.message = ""
        self.metricValue = 0
        self.thresholdPercentile = nil
    }

    init(
        date: Date,
        triggerType: String,
        strand: HelixStrand? = nil,
        message: String,
        metricValue: Double,
        thresholdPercentile: Double? = nil
    ) {
        self.date                = date
        self.triggerTypeRaw      = triggerType
        self.strandRaw           = strand?.rawValue
        self.message             = message
        self.metricValue         = metricValue
        self.thresholdPercentile = thresholdPercentile
    }
}

#if canImport(UIKit)
// MARK: — HelixAppState persistence helper (extension, not new type)

extension HelixAppState {
    var persistedString: String {
        switch self {
        case .fullScore:             return "fullScore"
        case .partialScore:          return "partialScore"
        case .suppressedScore:       return "suppressedScore"
        case .learningBaseline:      return "learningBaseline"
        case .developingBaseline:    return "developingBaseline"
        case .healthKitUnavailable:  return "healthKitUnavailable"
        case .permissionsDenied:     return "permissionsDenied"
        case .error:                 return "error"
        default:                     return "unknown"
        }
    }
}
#endif
