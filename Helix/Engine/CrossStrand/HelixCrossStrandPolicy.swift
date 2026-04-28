// Engine/CrossStrand/HelixCrossStrandPolicy.swift
// Decodable structs for helix_cross_strand_policy.json (bundled under Resources/Policy).
// Loaded with other policies via HelixPolicyLoader.loadAll() / HelixPolicyBundle.crossStrand.
//
// v1.1: Added LoadDominantStrainPattern. Added loadLt: Double? to ContradictionConditions
// to enforce the upper load bound introduced in policy v1.1.

import Foundation

struct CrossStrandPolicy: Decodable {
    let policyVersion:   String
    let languageStyle:   String
    let v1ProxyOnly:     Bool
    let suppression:     CrossStrandSuppression
    let patternPriority: [String]
    let patterns:        CrossStrandPatterns
}

struct CrossStrandSuppression: Decodable {
    let suppressIfConfidence:      String
    let suppressIfBaselineDaysLt:  Int
}

struct CrossStrandPatterns: Decodable {
    let contradiction:      ContradictionPattern
    let suppressedRecovery: SuppressedRecoveryPattern
    let loadDominantStrain: LoadDominantStrainPattern
    let alignment:          AlignmentPattern
}

// MARK: — Contradiction

struct ContradictionPattern: Decodable {
    let conditions: ContradictionConditions
    let language:   TwoDepthLanguage
}

struct ContradictionConditions: Decodable {
    let sleepGte:    Double
    let recoveryLte: Double
    let loadGte:     Double
    let loadLt:      Double?   // upper load bound; nil = no ceiling enforced
}

// MARK: — Suppressed Recovery

struct SuppressedRecoveryPattern: Decodable {
    let conditions: SuppressedRecoveryConditions
    let language:   TwoDepthLanguage
}

struct SuppressedRecoveryConditions: Decodable {
    let sleepGte:    Double
    let loadGte:     Double
    let recoveryLte: Double
}

// MARK: — Load Dominant Strain

struct LoadDominantStrainPattern: Decodable {
    let conditions: LoadDominantStrainConditions
    let language:   TwoDepthLanguage
}

struct LoadDominantStrainConditions: Decodable {
    let loadGte:     Double
    let sleepLte:    Double
    let recoveryLte: Double
}

// MARK: — Alignment

struct AlignmentPattern: Decodable {
    let conditions: AlignmentConditions
    let language:   AlignmentLanguage
}

struct AlignmentConditions: Decodable {
    let strong:     AlignmentThreshold
    let suppressed: AlignmentThreshold
}

struct AlignmentThreshold: Decodable {
    let allGte: Double?
    let allLte: Double?
}

struct AlignmentLanguage: Decodable {
    let strong:     TwoDepthLanguage
    let suppressed: TwoDepthLanguage
}

// MARK: — Shared language primitives

struct TwoDepthLanguage: Decodable {
    let depth2: LanguageBlock
    let depth3: LanguageBlock
}

struct LanguageBlock: Decodable {
    let headline: String
    let body:     String
}
