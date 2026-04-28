// PolicyValidationTests.swift
// HelixTests
//
// Validates that all bundled policy JSON files load without error and that
// their internal values satisfy the structural invariants the engine depends on.
// Run this suite after every policy file edit before touching Swift code.

import XCTest
@testable import Helix

final class PolicyValidationTests: XCTestCase {

    var bundle: HelixPolicyBundle!

    override func setUpWithError() throws {
        bundle = try HelixPolicyLoader.loadAll()
    }

    // MARK: - Load

    func test_allPolicyFilesLoad() {
        XCTAssertNotNil(bundle.core)
        XCTAssertNotNil(bundle.confidence)
        XCTAssertNotNil(bundle.explanation)
        XCTAssertNotNil(bundle.history)
        XCTAssertNotNil(bundle.crossStrand)
    }

    func test_policyVersionsAreNonEmpty() {
        XCTAssertFalse(bundle.core.policyVersion.isEmpty)
        XCTAssertFalse(bundle.confidence.policyVersion.isEmpty)
        XCTAssertFalse(bundle.explanation.policyVersion.isEmpty)
        XCTAssertFalse(bundle.history.policyVersion.isEmpty)
        XCTAssertFalse(bundle.crossStrand.policyVersion.isEmpty)
    }

    func test_allPoliciesPassValidation() {
        XCTAssertNoThrow(try HelixPolicyValidator.validate(bundle: bundle))
    }

    func test_crossStrandPolicyLoads() {
        XCTAssertFalse(bundle.crossStrand.patternPriority.isEmpty)
    }

    // MARK: - Strand Weight Invariants

    func test_sleepWeightsSumToOne() {
        let w = bundle.core.strandSleep.weights
        let sum = w.duration + w.deepSleep + w.remSleep +
                  w.disturbance + w.consistency + w.thermal + w.respiratory
        XCTAssertEqual(sum, 1.0, accuracy: 0.001,
            "Sleep strand weights must sum to 1.0 — got \(sum).")
    }

    func test_loadWeightsSumToOne() {
        let w = bundle.core.strandLoad.weights
        let sum = w.acwr + w.acuteLoad + w.activityCompletion + w.hrElevationPenalty
        XCTAssertEqual(sum, 1.0, accuracy: 0.001,
            "Load strand weights must sum to 1.0 — got \(sum).")
    }

    func test_recoveryWeightsSumToOne() {
        let w = bundle.core.strandRecovery.weights
        let sum = w.hrv + w.restingHr + w.overnightHrDip + w.respiratory
        XCTAssertEqual(sum, 1.0, accuracy: 0.001,
            "Recovery strand weights must sum to 1.0 — got \(sum).")
    }

    func test_indexWeightsSumToOne() {
        let w = bundle.core.helixIndex.weights
        let sum = w.sleep + w.recovery + w.load
        XCTAssertEqual(sum, 1.0, accuracy: 0.001,
            "Helix Index weights must sum to 1.0 — got \(sum).")
    }

    // MARK: - Recovery Gate Ordering
    //
    // SEVERE (worse state) must have a LOWER threshold than CRITICAL.
    // If inverted, the wrong multiplier is applied to the worse physiological state.

    func test_recoveryGate_severeThresholdIsLowerThanCritical() {
        let gate = bundle.core.helixIndex.recoveryGate
        XCTAssertLessThan(gate.severeThreshold, gate.criticalThreshold,
            "severeThreshold (\(gate.severeThreshold)) must be < " +
            "criticalThreshold (\(gate.criticalThreshold)).")
    }

    func test_recoveryGate_severeMultiplierIsStrongerThanCritical() {
        let gate = bundle.core.helixIndex.recoveryGate
        XCTAssertLessThan(gate.severeMultiplier, gate.criticalMultiplier,
            "severeMultiplier (\(gate.severeMultiplier)) must be < " +
            "criticalMultiplier (\(gate.criticalMultiplier)). " +
            "Lower multiplier = stronger suppression.")
    }

    // MARK: - Posture Threshold Ordering

    func test_postureThresholds_pursueAboveModerateAboveZero() {
        let t = bundle.core.helixIndex.postureThresholds
        XCTAssertGreaterThan(t.pursue, t.moderate,
            "PURSUE threshold must be above MODERATE.")
        XCTAssertGreaterThan(t.moderate, 0,
            "MODERATE threshold must be above 0 (RESTORE floor).")
    }

    // MARK: - Validation Ranges

    func test_validationRanges_minIsLessThanMax() {
        for (key, range) in bundle.core.validationRanges {
            XCTAssertLessThan(range.min, range.max,
                "Validation range '\(key)': min (\(range.min)) >= max (\(range.max)).")
        }
    }

    // MARK: - Baseline Decay Rates

    func test_baselineDecayRates_allBetweenZeroAndOne() {
        for (key, rate) in bundle.core.baseline.decayRates {
            XCTAssertGreaterThan(rate, 0.0, "Decay rate for '\(key)' must be > 0.")
            XCTAssertLessThanOrEqual(rate, 1.0, "Decay rate for '\(key)' must be <= 1.0.")
        }
    }

    func test_baselineWindowDays_exceedsMinimumActivation() {
        let b = bundle.core.baseline
        XCTAssertGreaterThan(b.windowDays, b.minimumDaysToActivate,
            "windowDays (\(b.windowDays)) must exceed minimumDaysToActivate (\(b.minimumDaysToActivate)).")
    }

    // MARK: - SpO2 Ordering

    func test_spo2Modifiers_nominalIsHighest() {
        let m = bundle.core.strandRecovery.spo2.modifiers
        XCTAssertGreaterThan(m.nominal, m.caution)
        XCTAssertGreaterThan(m.caution, m.concern)
        XCTAssertGreaterThan(m.concern, m.critical)
    }

    func test_spo2Thresholds_orderedDescending() {
        let t = bundle.core.strandRecovery.spo2.thresholds
        XCTAssertGreaterThan(t.nominal, t.caution)
        XCTAssertGreaterThan(t.caution, t.concern)
    }

    // MARK: - Balance Penalty

    func test_balancePenalty_maximumIsReasonable() {
        let penalty = bundle.core.helixIndex.balancePenalty.maximumPenalty
        XCTAssertGreaterThan(penalty, 0)
        XCTAssertLessThanOrEqual(penalty, 25,
            "Balance penalty max (\(penalty)) is unexpectedly large. Methodology specifies ~12 pts.")
    }

    // MARK: - Confidence Level Signal Counts

    func test_confidenceLevels_signalCountsAreOrdered() {
        // high uses a percent threshold (0.0-1.0); medium and low use absolute counts
        let highPercent = bundle.confidence.confidenceLevels.high.minimumSignalsPresentPercent
        let medium      = bundle.confidence.confidenceLevels.medium.minimumSignalsPresent
        let low         = bundle.confidence.confidenceLevels.low.minimumSignalsPresent
        XCTAssertGreaterThan(highPercent, 0.0, "HIGH percent threshold must be > 0.")
        XCTAssertLessThanOrEqual(highPercent, 1.0, "HIGH percent threshold must be <= 1.0.")
        XCTAssertGreaterThan(medium, low, "MEDIUM requires more signals than LOW.")
    }

}
