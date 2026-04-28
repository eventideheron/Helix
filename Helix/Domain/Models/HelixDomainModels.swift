// Models/HelixDomainModels.swift
// Domain value types only. No enums (those live in SignalIdentifier.swift).
// No HealthKit or SwiftData imports — pure Swift value types.

import Foundation

// MARK: — Personal baseline

struct PersonalBaseline {
    let signalName:      String
    let value:           Double
    let windowDays:      Int
    let decayRate:       Double
    let dataPointCount:  Int
    let lastUpdated:     Date
    let stabilityStatus: BaselineStabilityStatus
}

// MARK: — Signal contribution (decomposition)

struct SignalContribution {
    let signal:            SignalIdentifier
    let pointContribution: Double
    let explanation:       String
    let deltaDescription:  String
}

struct DecompositionView {
    let topContributors:        [SignalContribution]
    let confidence:             ConfidenceLevel
    let missingSignals:         [SignalIdentifier]
    let showPointContributions: Bool
    let showDeltaFromBaseline:  Bool
}

// MARK: — Individual signal

struct HelixSignal {
    let identifier:        SignalIdentifier
    let rawValue:          Double
    let unit:              String
    let timestamp:         Date
    let baseline:          Double
    let deltaFromBaseline: Double
    let normalizedScore:   Double
    let isValid:           Bool
    let isAnomaly:         Bool
}

// MARK: — Strand score

struct StrandScore {
    let strand:                HelixStrand
    let score:                 Double
    let componentSignals:      [HelixSignal]
    let missingSignals:        [SignalIdentifier]
    let confidence:            ConfidenceLevel
    let contributionBreakdown: [SignalContribution]
    let primaryExplanation:    String
    let calculatedAt:          Date
}

// MARK: — Helix Index

struct HelixIndex: Equatable {
    let score:               Double
    let posture:             HelixPosture
    let sleepStrand:         StrandScore
    let loadStrand:          StrandScore
    let recoveryStrand:      StrandScore
    let overallConfidence:   ConfidenceLevel
    let balancePenalty:      Double
    let recoveryGateApplied: Bool
    let recoveryGateLevel:   RecoveryGateLevel?
    let interactionTerms:    InteractionTerms
    let date:                Date

    static func == (lhs: HelixIndex, rhs: HelixIndex) -> Bool {
        lhs.date == rhs.date && lhs.score == rhs.score
    }
}

struct InteractionTerms {
    let sleepBoostApplied:    Double
    let loadCostApplied:      Double
    let netInteractionEffect: Double
}

extension StrandScore: Equatable {
    static func == (lhs: StrandScore, rhs: StrandScore) -> Bool {
        lhs.strand == rhs.strand &&
        lhs.score == rhs.score &&
        lhs.calculatedAt == rhs.calculatedAt
    }
}
