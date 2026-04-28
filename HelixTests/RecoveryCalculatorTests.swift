// RecoveryCalculatorTests.swift
// HelixTests
//
// Tests HelixRecoveryCalculator for the three coefficients flagged in
// METHODOLOGY.md as most likely to need personal recalibration:
//
//   1. HRV sensitivity     (220) — how hard HRV deviation moves the score
//   2. Overnight HR dip multiplier (8) — highly individual signal
//   3. Resting HR cost per bpm above baseline (9)
//
// Also tests the recovery gate ordering invariant via HelixIndexCalculator.
//
// calculate() returns a 5-tuple:
//   (score, missing, contributions, componentSignals, primaryExplanation)

import XCTest
@testable import Helix

final class RecoveryCalculatorTests: XCTestCase {

    // MARK: - Setup

    var calculator: HelixRecoveryCalculator!
    var indexCalculator: HelixIndexCalculator!

    override func setUpWithError() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        calculator = HelixRecoveryCalculator(
            policy: bundle.core.strandRecovery,
            confidenceEngine: HelixConfidenceEngine(policy: bundle.confidence),
            explanationEngine: HelixExplanationEngine(policy: bundle.explanation),
            restingHrExplanationThresholds: bundle.explanation.signalThresholds.restingHr,
            hrvExplanationThresholds: bundle.explanation.signalThresholds.hrv
        )
        indexCalculator = HelixIndexCalculator(policy: bundle.core.helixIndex)
    }

    // MARK: - HRV Sensitivity (Coefficient: 220)
    //
    // Formula: hrv_score = clamp(50 + delta_ratio × 220, 0, 100)
    // delta_ratio = (today - baseline) / baseline

    func test_hrv_atBaseline_scoreIsNearFifty() {
        // delta_ratio = 0.0 → score = 50 + 0 × 220 = 50
        let result = calculator.calculate(
            todayHRV: 50.0,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: 50.0)
        )
        XCTAssertEqual(result.score, 50.0, accuracy: 2.0,
            "HRV equal to baseline should produce a score near 50.")
        XCTAssertFalse(result.primaryExplanation.isEmpty,
            "Strand primaryExplanation must be a recovery narrative, not empty.")
    }

    func test_hrv_tenPercentAboveBaseline_addsApproximately22Points() {
        // today=55, baseline=50 → delta_ratio=0.10 → score = 50 + 0.10×220 = 72
        let result = calculator.calculate(
            todayHRV: 55.0,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: 50.0)
        )
        XCTAssertEqual(result.score, 72.0, accuracy: 2.0,
            "HRV 10% above baseline should add ~22 points (sensitivity=220).")
    }

    func test_hrv_twentyPercentBelowBaseline_subtractsApproximately44Points() {
        // today=40, baseline=50 → delta_ratio=-0.20 → score = 50 - 44 = 6
        let result = calculator.calculate(
            todayHRV: 40.0,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: 50.0)
        )
        XCTAssertEqual(result.score, 6.0, accuracy: 2.0,
            "HRV 20% below baseline should subtract ~44 points.")
    }

    func test_hrv_extremeSpike_clampsAt100() {
        // 50% above → 50 + 0.50×220 = 160 → clamp to 100
        let result = calculator.calculate(
            todayHRV: 75.0,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: 50.0)
        )
        XCTAssertEqual(result.score, 100.0, accuracy: 0.1,
            "Score must be clamped at 100 regardless of HRV spike.")
    }

    func test_hrv_extremeCrash_clampsAtZero() {
        // 50% below → 50 - 0.50×220 = -60 → clamp to 0
        let result = calculator.calculate(
            todayHRV: 25.0,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: 50.0)
        )
        XCTAssertEqual(result.score, 0.0, accuracy: 0.1,
            "Score must be clamped at 0 regardless of HRV crash.")
    }

    // MARK: - HRV explanation keys (policy delta thresholds, not score buckets)

    func test_hrv_explanationKey_atNotableDropBoundary_matchesPolicy() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        let t = bundle.explanation.signalThresholds.hrv
        // delta_ratio = -notableDropPercent → hrv.notable_drop
        let baseline = 100.0
        let today = baseline * (1.0 - t.notableDropPercent)
        let result = calculator.calculate(
            todayHRV: today,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: baseline)
        )
        let hrvContribution = result.contributions.first { $0.signal == .hrv }
        XCTAssertEqual(hrvContribution?.explanation, "hrv.notable_drop",
            "At exactly policy notable drop %, key must be hrv.notable_drop.")
    }

    func test_hrv_explanationKey_atSignificantDropBoundary_matchesPolicy() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        let t = bundle.explanation.signalThresholds.hrv
        let baseline = 100.0
        let today = baseline * (1.0 - t.significantDropPercent)
        let result = calculator.calculate(
            todayHRV: today,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: baseline)
        )
        let hrvContribution = result.contributions.first { $0.signal == .hrv }
        XCTAssertEqual(hrvContribution?.explanation, "hrv.significant_drop")
    }

    func test_hrv_explanationKey_atStrongDropBoundary_matchesPolicy() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        let t = bundle.explanation.signalThresholds.hrv
        let baseline = 100.0
        let today = baseline * (1.0 - t.strongDropPercent)
        let result = calculator.calculate(
            todayHRV: today,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: baseline)
        )
        let hrvContribution = result.contributions.first { $0.signal == .hrv }
        XCTAssertEqual(hrvContribution?.explanation, "hrv.strong_drop")
    }

    // MARK: - Overnight HR Dip (Coefficient: 8)
    //
    // Formula: dip_score = clamp(dip_bpm × 8, 0, 100)
    // dip_bpm = resting_hr_baseline - min_overnight_hr

    func test_hrDip_12bpm_producesStrongScore() {
        // baseline RHR=60, min sleep HR=48 → dip=12 → score=12×8=96
        let result = calculator.calculate(
            todayHRV: nil,
            todayRHR: nil,
            minSleepHR: 48.0,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(rhr: 60.0)
        )
        XCTAssertEqual(result.score, 96.0, accuracy: 3.0,
            "A 12 bpm overnight dip should produce a score near 96.")
    }

    func test_hrDip_5bpm_producesPartialScore() {
        // baseline RHR=60, min sleep HR=55 → dip=5 → score=5×8=40
        let result = calculator.calculate(
            todayHRV: nil,
            todayRHR: nil,
            minSleepHR: 55.0,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(rhr: 60.0)
        )
        XCTAssertEqual(result.score, 40.0, accuracy: 3.0,
            "A 5 bpm overnight dip should produce a score near 40.")
    }

    func test_hrDip_exceedsCap_clampsAt100() {
        // baseline RHR=60, min sleep HR=45 → dip=15 → 15×8=120 → clamp to 100
        let result = calculator.calculate(
            todayHRV: nil,
            todayRHR: nil,
            minSleepHR: 45.0,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(rhr: 60.0)
        )
        XCTAssertEqual(result.score, 100.0, accuracy: 0.1,
            "HR dip score must be clamped at 100.")
    }

    // MARK: - Resting HR (Cost: 9 pts/bpm above baseline)

    func test_restingHR_atBaseline_producesHighScore() {
        // delta=0 → score = 100 - 0×9 = 100
        let result = calculator.calculate(
            todayHRV: nil,
            todayRHR: 52.0,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(rhr: 52.0)
        )
        XCTAssertEqual(result.score, 100.0, accuracy: 2.0,
            "RHR at baseline should produce a score near 100.")
    }

    func test_restingHR_5bpmAboveBaseline_costsApproximately45Points() {
        // delta=5 → score = 100 - 5×9 = 55
        let result = calculator.calculate(
            todayHRV: nil,
            todayRHR: 57.0,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(rhr: 52.0)
        )
        XCTAssertEqual(result.score, 55.0, accuracy: 3.0,
            "RHR 5 bpm above baseline costs ~45 points (cost_per_bpm=9).")
    }

    // MARK: - Missing Signals

    func test_allSignalsMissing_missingListContainsExpectedSignals() {
        let result = calculator.calculate(
            todayHRV: nil,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: [:]
        )
        XCTAssertTrue(result.missing.contains(.hrv))
        XCTAssertTrue(result.missing.contains(.restingHR))
        XCTAssertTrue(result.missing.contains(.overnightHRDip))
    }

    func test_presentSignals_notInMissingList() {
        let result = calculator.calculate(
            todayHRV: 48.0,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: 50.0)
        )
        XCTAssertFalse(result.missing.contains(.hrv),
            "HRV was provided — must not appear in missing list.")
    }

    // MARK: - Recovery Gate Ordering (Critical Invariant)
    //
    // SEVERE (score < 20, multiplier 0.55) must fire BEFORE
    // CRITICAL (score < 35, multiplier 0.75).
    //
    // A score of 15 satisfies both conditions. Correct: apply 0.55 (severe).
    // Wrong: if critical checked first, 0.75 would be applied to the worst state.

    func test_recoveryGate_scoreBelow20_appliesSevereMultiplier() {
        let result = indexCalculator.calculate(
            sleep:    makeStrand(.sleep,    score: 80.0),
            load:     makeStrand(.load,     score: 80.0),
            recovery: makeStrand(.recovery, score: 15.0)
        )
        XCTAssertTrue(result.recoveryGateApplied,
            "Recovery gate must fire when recovery score < 20.")
        XCTAssertEqual(result.recoveryGateLevel, .severe,
            "Score of 15 is below SEVERE threshold (20). Gate must return .severe, not .critical.")
    }

    func test_recoveryGate_scoreBetween20And35_appliesCriticalMultiplier() {
        let result = indexCalculator.calculate(
            sleep:    makeStrand(.sleep,    score: 80.0),
            load:     makeStrand(.load,     score: 80.0),
            recovery: makeStrand(.recovery, score: 28.0)
        )
        XCTAssertTrue(result.recoveryGateApplied)
        XCTAssertEqual(result.recoveryGateLevel, .critical,
            "Score of 28 is between 20 and 35. Gate must return .critical, not .severe.")
    }

    func test_recoveryGate_scoreAbove35_doesNotFire() {
        let result = indexCalculator.calculate(
            sleep:    makeStrand(.sleep,    score: 70.0),
            load:     makeStrand(.load,     score: 70.0),
            recovery: makeStrand(.recovery, score: 50.0)
        )
        XCTAssertFalse(result.recoveryGateApplied,
            "Recovery gate must NOT fire when recovery score >= 35.")
        XCTAssertNil(result.recoveryGateLevel)
    }

    func test_recoveryGate_severe_producesLowerIndexThanCritical() {
        // Identical setup except recovery: 15 (severe) vs 28 (critical).
        // Severe suppression (×0.55) must produce a lower index than critical (×0.75).
        let sleep = makeStrand(.sleep, score: 80.0)
        let load  = makeStrand(.load,  score: 80.0)

        let severeIndex   = indexCalculator.calculate(
            sleep: sleep, load: load, recovery: makeStrand(.recovery, score: 15.0))
        let criticalIndex = indexCalculator.calculate(
            sleep: sleep, load: load, recovery: makeStrand(.recovery, score: 28.0))

        XCTAssertLessThan(severeIndex.score, criticalIndex.score,
            "SEVERE gate (×0.55) must produce a lower Helix Index than CRITICAL (×0.75). " +
            "If equal or reversed, gate ordering is wrong.")
    }

    // MARK: - Helpers

    private func makeBaselines(
        hrv: Double? = nil,
        rhr: Double? = nil,
        rr:  Double? = nil
    ) -> [SignalIdentifier: PersonalBaseline] {
        var baselines = [SignalIdentifier: PersonalBaseline]()
        if let v = hrv {
            baselines[.hrv] = PersonalBaseline(
                signalName: "hrv", value: v, windowDays: 90,
                decayRate: 0.96, dataPointCount: 60,
                lastUpdated: Date(), stabilityStatus: .stable)
        }
        if let v = rhr {
            baselines[.restingHR] = PersonalBaseline(
                signalName: "resting_hr", value: v, windowDays: 90,
                decayRate: 0.94, dataPointCount: 60,
                lastUpdated: Date(), stabilityStatus: .stable)
        }
        if let v = rr {
            baselines[.overnightRespiratory] = PersonalBaseline(
                signalName: "respiratory_rate", value: v, windowDays: 90,
                decayRate: 0.94, dataPointCount: 60,
                lastUpdated: Date(), stabilityStatus: .stable)
        }
        return baselines
    }

    private func makeStrand(_ strand: HelixStrand, score: Double) -> StrandScore {
        StrandScore(
            strand: strand, score: score,
            componentSignals: [], missingSignals: [],
            confidence: .high, contributionBreakdown: [],
            primaryExplanation: "", calculatedAt: Date()
        )
    }
    func test_debug_singleHRV_redistributionCheck() {
        let result = calculator.calculate(
            todayHRV: 50.0,
            todayRHR: nil,
            minSleepHR: nil,
            overnightRR: nil,
            spo2Rolling7Night: nil,
            baselines: makeBaselines(hrv: 50.0)
        )
        XCTAssertEqual(result.missing.count, 3,
            "3 signals missing: got \(result.missing)")
        XCTAssertEqual(result.score, 50.0, accuracy: 2.0,
            "Score should be ~50. Got \(result.score). Missing: \(result.missing)")
    }
}
