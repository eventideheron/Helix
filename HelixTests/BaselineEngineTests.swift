// BaselineEngineTests.swift
// HelixTests
//
// Tests the EWMA baseline calculation in HelixBaselineEngine.
// All expected values are hand-calculated from the formula in METHODOLOGY.md:
//
//   weight_i  = decayRate ^ daysAgo_i
//   baseline  = Σ(reading_i × weight_i) / Σ(weight_i)
//
// A regression in the engine math produces an immediate, unambiguous failure.

import XCTest
@testable import Helix

final class BaselineEngineTests: XCTestCase {

    // MARK: - Setup

    var engine: HelixBaselineEngine!

    override func setUpWithError() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        engine = HelixBaselineEngine(policy: bundle.core)
    }

    // MARK: - Single Reading

    func test_singleReading_returnsItsOwnValue() {
        // One reading: baseline must equal that reading regardless of weight.
        let readings: [(value: Double, date: Date)] = [
            (value: 55.0, date: daysAgo(0))
        ]
        let result = engine.calculateBaseline(readings: readings, decayRate: 0.96)
        XCTAssertEqual(result, 55.0, accuracy: 0.01)
    }

    // MARK: - Two Readings — Hand-Calculated EWMA

    func test_twoReadings_ewmaFavorsMoreRecent() {
        // today=60, yesterday=40, decay=0.96
        // w_today     = 0.96^0 = 1.000
        // w_yesterday = 0.96^1 = 0.960
        // baseline = (60×1.0 + 40×0.96) / (1.0 + 0.96)
        //          = (60 + 38.4) / 1.96
        //          = 98.4 / 1.96 ≈ 50.20
        let readings: [(value: Double, date: Date)] = [
            (value: 60.0, date: daysAgo(0)),
            (value: 40.0, date: daysAgo(1))
        ]
        let result = engine.calculateBaseline(readings: readings, decayRate: 0.96)
        XCTAssertEqual(result, 50.20, accuracy: 0.05)
    }

    func test_twoReadings_orderMatters() {
        // Same values reversed: today=40, yesterday=60
        // baseline = (40×1.0 + 60×0.96) / 1.96 ≈ 49.80
        // Must differ from the above — recent data must influence more.
        let readings: [(value: Double, date: Date)] = [
            (value: 40.0, date: daysAgo(0)),
            (value: 60.0, date: daysAgo(1))
        ]
        let result = engine.calculateBaseline(readings: readings, decayRate: 0.96)
        XCTAssertEqual(result, 49.80, accuracy: 0.05)

        // Confirm the two are different — guards against accidentally computing a simple mean.
        let readingsFlipped: [(value: Double, date: Date)] = [
            (value: 60.0, date: daysAgo(0)),
            (value: 40.0, date: daysAgo(1))
        ]
        let flipped = engine.calculateBaseline(readings: readingsFlipped, decayRate: 0.96)
        XCTAssertNotEqual(result, flipped,
            "EWMA must weight recent readings more heavily — order must change the result.")
    }

    // MARK: - Decay Rate Effect

    func test_lowerDecayRate_makesOldReadingsLessRelevant() {
        // today=80, 30 days ago=20.
        // High decay (0.96): 30-day weight = 0.96^30 ≈ 0.294 — still meaningful.
        // Low decay  (0.88): 30-day weight = 0.88^30 ≈ 0.021 — nearly irrelevant.
        // High-decay baseline is pulled more toward 20 → lower than low-decay baseline.
        let readings: [(value: Double, date: Date)] = [
            (value: 80.0, date: daysAgo(0)),
            (value: 20.0, date: daysAgo(30))
        ]
        let highDecay = engine.calculateBaseline(readings: readings, decayRate: 0.96)
        let lowDecay  = engine.calculateBaseline(readings: readings, decayRate: 0.88)

        XCTAssertLessThan(highDecay, lowDecay,
            "High decay (0.96) gives old readings more weight, pulling baseline lower. " +
            "Low decay (0.88) ignores old readings more aggressively.")
    }

    // MARK: - Window Exclusion

    func test_readingsOutsideWindow_areExcluded() {
        // Reading from day 91 must be ignored (window = 90 days).
        // If included, it would pull baseline away from the recent reading.
        let readings: [(value: Double, date: Date)] = [
            (value: 60.0, date: daysAgo(0)),
            (value: 10.0, date: daysAgo(91))   // outside 90-day window
        ]
        let result = engine.calculateBaseline(readings: readings, decayRate: 0.96)
        XCTAssertEqual(result, 60.0, accuracy: 0.01,
            "Readings older than windowDays (90) must be excluded from EWMA.")
    }

    // MARK: - Empty Input

    func test_emptyReadings_returnsZero() {
        let result = engine.calculateBaseline(readings: [], decayRate: 0.96)
        XCTAssertEqual(result, 0.0,
            "Empty readings must return 0.")
    }

    // MARK: - Known Policy Values

    func test_hrvDecayRate_isCorrectValue() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        let rate = bundle.core.baseline.decayRates["hrv"]
        XCTAssertEqual(rate!, 0.96, accuracy: 0.001,
            "HRV decay rate should be 0.96 per methodology.")
    }

    func test_acuteTrainingLoadDecayRate_isCorrectValue() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        let rate = bundle.core.baseline.decayRates["acute_training_load"]
        XCTAssertEqual(rate!, 0.88, accuracy: 0.001,
            "Acute training load decays fastest (0.88) — recent load is what matters.")
    }

    func test_knownDecayRateKeys_allPresentInPolicy() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        let rates = bundle.core.baseline.decayRates
        let expectedKeys = [
            "hrv", "resting_hr", "sleep_duration",
            "deep_sleep_percent", "rem_sleep_percent",
            "respiratory_rate", "wrist_temperature",
            "overnight_hr_dip"
        ]
        for key in expectedKeys {
            XCTAssertNotNil(rates[key],
                "Expected decay rate key '\(key)' is missing from policy file.")
        }
    }

    // MARK: - Iterative Update Formula

    func test_iterativeUpdate_handCalculatedValue() {
        // yesterday baseline=50, today value=60, decay=0.94
        // new = 60 × (1 - 0.94) + 50 × 0.94
        //     = 60 × 0.06 + 47
        //     = 3.6 + 47 = 50.6
        let result = engine.updateBaselineIteratively(
            todayValue: 60,
            yesterdayBaseline: 50,
            decayRate: 0.94
        )
        XCTAssertEqual(result, 50.6, accuracy: 0.01)
    }

    func test_iterativeUpdate_atBaseline_returnsBaseline() {
        // today == yesterday baseline → result should equal baseline
        let result = engine.updateBaselineIteratively(
            todayValue: 55,
            yesterdayBaseline: 55,
            decayRate: 0.94
        )
        XCTAssertEqual(result, 55.0, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }
}
