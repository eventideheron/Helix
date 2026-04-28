// ConfidenceEngineTests.swift
// HelixTests
//
// Tests HelixConfidenceEngine: signal availability evaluation via
// evaluate(presentSignals:validSignals:allExpectedSignals:watchOfflineHours:)
// and proportional weight redistribution via redistributedWeights().
//
// The redistribution logic is one of the subtler parts of the engine —
// missing weight is distributed proportionally (not evenly), preserving
// the relative importance structure of remaining signals.

import XCTest
@testable import Helix

final class ConfidenceEngineTests: XCTestCase {

    // MARK: - Setup

    var engine: HelixConfidenceEngine!

    override func setUpWithError() throws {
        let bundle = try HelixPolicyLoader.loadAll()
        engine = HelixConfidenceEngine(policy: bundle.confidence)
    }

    // MARK: - Confidence Level Evaluation

    func test_allPrimarySignalsPresent_producesHighConfidence() {
        let all = primarySignals
        let result = engine.evaluate(
            presentSignals: all,
            validSignals: all,
            allExpectedSignals: all
        )
        XCTAssertEqual(result.level, .high,
            "All primary signals present and valid must produce HIGH confidence.")
        XCTAssertTrue(result.missingSignals.isEmpty,
            "No signals should be missing when all are present.")
    }

    func test_onePrimarySignalMissing_producesMediumOrLowerConfidence() {
        // HRV absent: not in presentSignals
        let present = primarySignals.filter { $0 != .hrv }
        let result = engine.evaluate(
            presentSignals: present,
            validSignals: present,
            allExpectedSignals: primarySignals
        )
        XCTAssertNotEqual(result.level, .high,
            "One missing primary signal must reduce confidence below HIGH.")
    }

    func test_twoPrimarySignalsMissing_producesMediumConfidence() {
        let present = primarySignals.filter { $0 != .hrv && $0 != .overnightHRDip }
        let result = engine.evaluate(
            presentSignals: present,
            validSignals: present,
            allExpectedSignals: primarySignals
        )
        XCTAssertEqual(result.level, .medium,
            "Two missing primary signals must produce LOW confidence.")
    }

    func test_signalPresentButInvalid_countsAsMissing() {
        // HRV is present but not valid (e.g. corrupted reading)
        let present = primarySignals              // HRV in present list
        let valid   = primarySignals.filter { $0 != .hrv }  // HRV NOT in valid list
        let result = engine.evaluate(
            presentSignals: present,
            validSignals: valid,
            allExpectedSignals: primarySignals
        )
        XCTAssertTrue(result.missingSignals.contains(.hrv),
            "A signal that is present but not valid must appear in missingSignals.")
    }

    func test_missingSignals_areReportedInResult() {
        let present = primarySignals.filter { $0 != .hrv && $0 != .sleepDuration }
        let result = engine.evaluate(
            presentSignals: present,
            validSignals: present,
            allExpectedSignals: primarySignals
        )
        XCTAssertTrue(result.missingSignals.contains(.hrv))
        XCTAssertTrue(result.missingSignals.contains(.sleepDuration))
        XCTAssertFalse(result.missingSignals.contains(.restingHR),
            "restingHR was provided — must not appear in missing list.")
    }

    func test_suppressScore_isFalse_whenSignalsArePresent() {
        let result = engine.evaluate(
            presentSignals: primarySignals,
            validSignals: primarySignals,
            allExpectedSignals: primarySignals
        )
        XCTAssertFalse(result.suppressScore,
            "Score must not be suppressed when all signals are present.")
    }

    func test_watchOffline_exceedingThreshold_suppressesScore() {
        // Watch offline hours exceeding the policy threshold should trigger suppression.
        let result = engine.evaluate(
            presentSignals: primarySignals,
            validSignals: primarySignals,
            allExpectedSignals: primarySignals,
            watchOfflineHours: 48.0   // well above any reasonable threshold
        )
        XCTAssertTrue(result.suppressScore,
            "Watch offline for 48 hours must suppress the score.")
        XCTAssertNotNil(result.suppressionReason,
            "Suppressed score must include a suppressionReason.")
    }

    func test_explanationKey_isNonEmpty() {
        let result = engine.evaluate(
            presentSignals: primarySignals,
            validSignals: primarySignals,
            allExpectedSignals: primarySignals
        )
        XCTAssertFalse(result.explanationKey.isEmpty,
            "ConfidenceResult must always include a non-empty explanationKey.")
    }

    /// Recovery strand expects four signals; with `minimum_signals_present_percent` = 0.80,
    /// `ceil(4 × 0.80) = 4` → 4/4 present yields HIGH. The `medium_confidence_full_signals` branch
    /// (missing.isEmpty under medium tier) is unreachable when all signals are present under this model.
    func test_fourSignalsAllPresent_producesHighConfidence() {
        let all: [SignalIdentifier] = [.hrv, .restingHR, .overnightHRDip, .respiratoryRecovery]
        let result = engine.evaluate(
            presentSignals: all,
            validSignals: all,
            allExpectedSignals: all
        )
        XCTAssertEqual(result.level, .high)
        XCTAssertTrue(result.missingSignals.isEmpty)
        XCTAssertEqual(result.explanationKey, "high")
    }

    /// 3/4 expected signals: MEDIUM tier coverage (presentCount below high threshold, at or above medium minimum).
    /// Missing non-primary `.respiratoryRecovery` → `missingExplanationKey` fallthrough → `"medium"`.
    func test_threeOfFourSignalsPresent_producesMediumConfidence() {
        let all: [SignalIdentifier] = [.hrv, .restingHR, .overnightHRDip, .respiratoryRecovery]
        let present: [SignalIdentifier] = [.hrv, .restingHR, .overnightHRDip]
        let result = engine.evaluate(
            presentSignals: present,
            validSignals: present,
            allExpectedSignals: all
        )
        XCTAssertEqual(result.level, .medium)
        XCTAssertEqual(result.missingSignals, [.respiratoryRecovery])
        XCTAssertEqual(result.explanationKey, "medium")
    }

    // MARK: - Proportional Weight Redistribution
    //
    // Core invariant: redistributed weights must still sum to 1.0.
    // Missing weight is distributed proportionally — not evenly —
    // preserving the relative importance of remaining signals.

    func test_redistribution_noMissingSignals_weightsUnchanged() {
        let original: [SignalIdentifier: Double] = [
            .hrv: 0.35, .restingHR: 0.25, .overnightHRDip: 0.25, .overnightRespiratory: 0.15
        ]
        let adjusted = engine.redistributedWeights(
            originalWeights: original,
            missingSignals: []
        )
        for (signal, weight) in original {
            XCTAssertEqual(adjusted[signal]!, weight, accuracy: 0.001,
                "No missing signals: weight for \(signal) must be unchanged.")
        }
    }

    func test_redistribution_missingOneSignal_totalSumsToOne() {
        let original: [SignalIdentifier: Double] = [
            .hrv: 0.35, .restingHR: 0.25, .overnightHRDip: 0.25, .overnightRespiratory: 0.15
        ]
        let adjusted = engine.redistributedWeights(
            originalWeights: original,
            missingSignals: [.hrv]
        )
        let total = adjusted.values.reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 0.001,
            "Redistributed weights must sum to 1.0 after removing HRV.")
    }

    func test_redistribution_missingTwoSignals_totalSumsToOne() {
        let original: [SignalIdentifier: Double] = [
            .hrv: 0.35, .restingHR: 0.25, .overnightHRDip: 0.25, .overnightRespiratory: 0.15
        ]
        let adjusted = engine.redistributedWeights(
            originalWeights: original,
            missingSignals: [.hrv, .overnightHRDip]
        )
        let total = adjusted.values.reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 0.001,
            "Redistributed weights must sum to 1.0 after removing two signals.")
    }

    func test_redistribution_missingSignal_isRemovedFromResult() {
        let original: [SignalIdentifier: Double] = [
            .hrv: 0.35, .restingHR: 0.25, .overnightHRDip: 0.25, .overnightRespiratory: 0.15
        ]
        let adjusted = engine.redistributedWeights(
            originalWeights: original,
            missingSignals: [.hrv]
        )
        XCTAssertNil(adjusted[.hrv],
            "HRV must not appear in redistributed weights when it is missing.")
    }

    func test_redistribution_isProportionalNotEven() {
        // Original: restingHR=0.25, overnightHRDip=0.25, respiratory=0.15
        // HRV (0.35) is missing. Remaining total = 0.65.
        //
        // Proportional redistribution:
        //   restingHR    += 0.35 × (0.25/0.65) ≈ 0.1346  → new ≈ 0.3846
        //   overnightDip += 0.35 × (0.25/0.65) ≈ 0.1346  → new ≈ 0.3846
        //   respiratory  += 0.35 × (0.15/0.65) ≈ 0.0808  → new ≈ 0.2308
        //
        // Even distribution would give each +0.35/3 = +0.1167.
        // Proportional preserves restingHR ≈ overnightDip >> respiratory.
        let original: [SignalIdentifier: Double] = [
            .hrv: 0.35, .restingHR: 0.25, .overnightHRDip: 0.25, .overnightRespiratory: 0.15
        ]
        let adjusted = engine.redistributedWeights(
            originalWeights: original,
            missingSignals: [.hrv]
        )

        // Signals with equal original weights must receive equal redistributed weight
        XCTAssertEqual(adjusted[.restingHR]!, adjusted[.overnightHRDip]!, accuracy: 0.001,
            "Signals with equal original weights must receive equal redistributed weight.")

        // restingHR must receive more than respiratory
        XCTAssertGreaterThan(adjusted[.restingHR]!, adjusted[.overnightRespiratory]!,
            "Proportional redistribution: restingHR (higher original weight) must " +
            "receive more redistributed weight than respiratory.")

        // Verify approximate values
        XCTAssertEqual(adjusted[.restingHR]!, 0.3846, accuracy: 0.005)
        XCTAssertEqual(adjusted[.overnightRespiratory]!, 0.2308, accuracy: 0.005)
    }

    func test_redistribution_allSignalsMissing_returnsEmpty() {
        let original: [SignalIdentifier: Double] = [
            .hrv: 0.35, .restingHR: 0.65
        ]
        let adjusted = engine.redistributedWeights(
            originalWeights: original,
            missingSignals: [.hrv, .restingHR]
        )
        XCTAssertTrue(adjusted.isEmpty,
            "All signals missing: redistributed weights must be empty.")
    }

    // MARK: - compositeConfidence

    func test_compositeConfidence_allHigh_remainsHigh() {
        let result = engine.compositeConfidence(sleep: .high, load: .high, recovery: .high)
        XCTAssertEqual(result, .high)
    }

    
    func test_compositeConfidence_anyLow_returnsLow() {
        let result = engine.compositeConfidence(sleep: .high, load: .medium, recovery: .low)
        XCTAssertEqual(result, .low)
        
    }
    
    func test_compositeConfidence_mixedHighMedium_returnsMedium() {
        let result = engine.compositeConfidence(sleep: .high, load: .medium, recovery: .high)
        XCTAssertEqual(result, .medium)
    }

    // MARK: - Helpers

    private var primarySignals: [SignalIdentifier] {
        [.hrv, .restingHR, .sleepDuration, .deepSleepPercent, .overnightHRDip]
    }
}
