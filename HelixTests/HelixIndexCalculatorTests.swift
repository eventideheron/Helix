// HelixIndexCalculatorTests.swift
// HelixTests
//
// Tests HelixIndexCalculator end-to-end.
// All private methods (lowestConfidence, determinePosture) are tested
// indirectly through calculate() — the only public API.

import XCTest
@testable import Helix

final class HelixIndexCalculatorTests: XCTestCase {

    // MARK: - Setup

    var calculator: HelixIndexCalculator!
    var policy: IndexConfig!

    override func setUpWithError() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        calculator = HelixIndexCalculator(policy: bundle.core.helixIndex)
        policy = bundle.core.helixIndex
    }

    // MARK: - Interaction Terms
    //
    // sleep_boost = (sleep_score - 50) / sleepBoostDivisor   (divisor = 600)
    // load_cost   = (load_score  - 50) / loadCostDivisor     (divisor = 500)
    // adjusted_recovery = clamp(recovery + sleep_boost - load_cost, 0, 100)

    func test_excellentSleep_boostsAdjustedRecovery() {
        // sleep=90: boost = (90-50)/600 = +6.67 pts on adjusted_recovery
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 90.0),
            load:     makeStrand(.load,     score: 50.0),
            recovery: makeStrand(.recovery, score: 60.0)
        )
        XCTAssertGreaterThan(result.interactionTerms.sleepBoostApplied, 0.06,
            "Sleep score of 90 should boost adjusted recovery by ~6.7 pts.")
    }

    func test_highLoad_suppressesAdjustedRecovery() {
        // load=85: cost = (85-50)/500 = 7.0 pts suppression
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 50.0),
            load:     makeStrand(.load,     score: 85.0),
            recovery: makeStrand(.recovery, score: 60.0)
        )
        XCTAssertGreaterThan(result.interactionTerms.loadCostApplied, 0.06,
            "Load score of 85 should suppress adjusted recovery by ~7 pts.")
    }

    func test_belowMidpointSleep_producesNegativeBoost() {
        // sleep=30: boost = (30-50)/600 = -0.033 → negative (hurts recovery)
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 30.0),
            load:     makeStrand(.load,     score: 50.0),
            recovery: makeStrand(.recovery, score: 60.0)
        )
        XCTAssertLessThan(result.interactionTerms.sleepBoostApplied, 0,
            "Sleep score below 50 must produce a negative boost.")
    }

    // MARK: - Balance Penalty
    //
    // std_dev of [sleep, load, recovery]
    // penalty = min(maximumPenalty, std_dev × penaltyFactor)

    func test_balancePenalty_perfectBalance_producesNoPenalty() {
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 70.0),
            load:     makeStrand(.load,     score: 70.0),
            recovery: makeStrand(.recovery, score: 70.0)
        )
        XCTAssertEqual(result.balancePenalty, 0.0, accuracy: 0.01,
            "Equal strand scores must produce zero balance penalty.")
    }

    func test_balancePenalty_oneCollapsedStrand_producesNonZeroPenalty() {
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 90.0),
            load:     makeStrand(.load,     score: 90.0),
            recovery: makeStrand(.recovery, score: 10.0)
        )
        XCTAssertGreaterThan(result.balancePenalty, 0.0,
            "A collapsed strand must produce a non-zero balance penalty.")
    }

    func test_balancePenalty_doesNotExceedMaximum() {
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 100.0),
            load:     makeStrand(.load,     score: 0.0),
            recovery: makeStrand(.recovery, score: 0.0)
        )
        XCTAssertLessThanOrEqual(result.balancePenalty, policy.balancePenalty.maximumPenalty,
            "Balance penalty must never exceed maximumPenalty.")
    }

    func test_balancePenalty_balancedScoresOutperformImbalanced() {
        // Same average (70) but different variance.
        // Balanced (70/70/70): penalty = 0.
        // Imbalanced (100/70/40): non-zero penalty.
        let balanced = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 70.0),
            load:     makeStrand(.load,     score: 70.0),
            recovery: makeStrand(.recovery, score: 70.0)
        )
        let imbalanced = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 100.0),
            load:     makeStrand(.load,     score: 70.0),
            recovery: makeStrand(.recovery, score: 40.0)
        )
        XCTAssertGreaterThan(balanced.score, imbalanced.score,
            "Balanced strands with same average must outscore imbalanced strands " +
            "due to zero vs non-zero balance penalty.")
    }

    // MARK: - Posture Determination (tested through calculate())

    func test_posture_highScore_isPursue() {
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 90.0),
            load:     makeStrand(.load,     score: 80.0),
            recovery: makeStrand(.recovery, score: 90.0)
        )
        XCTAssertEqual(result.posture, .pursue,
            "High composite score should produce PURSUE posture.")
    }

    func test_posture_midScore_isModerate() {
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 65.0),
            load:     makeStrand(.load,     score: 65.0),
            recovery: makeStrand(.recovery, score: 65.0)
        )
        XCTAssertEqual(result.posture, .moderate,
            "Mid-range composite score should produce MODERATE posture.")
    }

    func test_posture_lowScore_isRestore() {
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 30.0),
            load:     makeStrand(.load,     score: 30.0),
            recovery: makeStrand(.recovery, score: 30.0)
        )
        XCTAssertEqual(result.posture, .restore,
            "Low composite score should produce RESTORE posture.")
    }

    // MARK: - Score Bounds

    func test_score_isAlwaysBetweenZeroAndOneHundred() {
        let cases: [(Double, Double, Double)] = [
            (100, 100, 100),
            (0,   0,   0),
            (100, 0,   0),
            (0,   100, 0),
            (0,   0,   100),
            (50,  50,  0),
        ]
        for (s, l, r) in cases {
            let result = calculator.calculate(
                sleep:    makeStrand(.sleep,    score: s),
                load:     makeStrand(.load,     score: l),
                recovery: makeStrand(.recovery, score: r)
            )
            XCTAssertGreaterThanOrEqual(result.score, 0.0,
                "Score must be ≥ 0. Got \(result.score) for (sleep:\(s), load:\(l), recovery:\(r))")
            XCTAssertLessThanOrEqual(result.score, 100.0,
                "Score must be ≤ 100. Got \(result.score) for (sleep:\(s), load:\(l), recovery:\(r))")
        }
    }

    // MARK: - Confidence Propagation

    func test_confidence_propagatesLowestStrandConfidence() {
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 70.0, confidence: .high),
            load:     makeStrand(.load,     score: 70.0, confidence: .low),
            recovery: makeStrand(.recovery, score: 70.0, confidence: .medium)
        )
        XCTAssertEqual(result.overallConfidence, .low,
            "Overall confidence must equal the lowest strand confidence.")
    }

    func test_confidence_allHigh_remainsHigh() {
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 70.0, confidence: .high),
            load:     makeStrand(.load,     score: 70.0, confidence: .high),
            recovery: makeStrand(.recovery, score: 70.0, confidence: .high)
        )
        XCTAssertEqual(result.overallConfidence, .high)
    }

    // MARK: - End-to-End Physiological Scenarios
    //
    // Feed recognizable physiological states and assert the score and posture
    // fall in defensible ranges. Adjust expected values when recalibrating coefficients.

    func test_scenario_peakReadiness() {
        // Excellent sleep, balanced load, strong recovery → PURSUE, score >= 80.
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 92.0),
            load:     makeStrand(.load,     score: 78.0),
            recovery: makeStrand(.recovery, score: 88.0)
        )
        XCTAssertEqual(result.posture, .pursue,
            "Peak readiness must produce PURSUE.")
        XCTAssertGreaterThanOrEqual(result.score, 80.0,
            "Peak readiness should score >= 80.")
    }

    func test_scenario_overtrained_poorSleep() {
        // Two weeks into training block with sleep debt and crashed HRV → RESTORE.
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 38.0),
            load:     makeStrand(.load,     score: 82.0),
            recovery: makeStrand(.recovery, score: 22.0)
        )
        XCTAssertEqual(result.posture, .restore,
            "Overtrained with poor sleep must produce RESTORE.")
        XCTAssertLessThan(result.score, 55.0,
            "Overtrained scenario should score well below 55.")
    }

    func test_scenario_deliberateRecoveryWeek() {
        // Strong sleep, strong recovery, low load (intentional deload) → not RESTORE.
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 88.0),
            load:     makeStrand(.load,     score: 42.0),
            recovery: makeStrand(.recovery, score: 85.0)
        )
        XCTAssertNotEqual(result.posture, .restore,
            "Deliberate recovery week with strong sleep and recovery must not produce RESTORE.")
    }

    func test_scenario_illnessOnset() {
        // Elevated RHR, crashed HRV, elevated overnight RR → SEVERE gate, RESTORE.
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 52.0),
            load:     makeStrand(.load,     score: 55.0),
            recovery: makeStrand(.recovery, score: 18.0)
        )
        XCTAssertEqual(result.recoveryGateLevel, .severe,
            "Recovery < 20 must trigger SEVERE gate.")
        XCTAssertEqual(result.posture, .restore,
            "Illness onset should produce RESTORE posture.")
    }

    func test_scenario_highLoadWellRecovered() {
        // Hard training week, good sleep, recovery holding → not RESTORE.
        let result = calculator.calculate(
            sleep:    makeStrand(.sleep,    score: 80.0),
            load:     makeStrand(.load,     score: 88.0),
            recovery: makeStrand(.recovery, score: 72.0)
        )
        XCTAssertNotEqual(result.posture, .restore,
            "Hard training with good sleep and recovery should not produce RESTORE.")
    }

    // MARK: - Helpers

    private func makeStrand(
        _ strand: HelixStrand,
        score: Double,
        confidence: ConfidenceLevel = .high
    ) -> StrandScore {
        StrandScore(
            strand: strand, score: score,
            componentSignals: [], missingSignals: [],
            confidence: confidence, contributionBreakdown: [],
            primaryExplanation: "", calculatedAt: Date()
        )
    }
}
