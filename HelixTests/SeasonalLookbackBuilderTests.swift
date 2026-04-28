// SeasonalLookbackBuilderTests.swift
// Unit tests for prior-year anchored seasonal lookback (policy-driven).

import XCTest
@testable import Helix

final class SeasonalLookbackBuilderTests: XCTestCase {

    private var policy: HelixHistoryPolicy!

    override func setUpWithError() throws {
        policy = try HelixPolicyLoader.load(filename: "helix_history_policy", as: HelixHistoryPolicy.self)
    }

    func test_historyPolicyDecodesAtVersion12() {
        XCTAssertEqual(policy.policyVersion, "1.3")
        XCTAssertEqual(policy.baselineRelationship.scoringBaselineWindowDays, 90)
        XCTAssertFalse(policy.baselineRelationship.seasonalLayerAffectsScoring)
    }

    func test_eligibility_requires365UniqueDays() throws {
        let cal = Calendar(identifier: .gregorian)
        var ref = DateComponents(calendar: cal, year: 2026, month: 6, day: 15).date!
        var records: [HelixDailyRecord] = []
        for i in 0..<364 {
            let r = HelixDailyRecord()
            r.date = cal.date(byAdding: .day, value: -i, to: ref)!
            r.sleepScore = 80
            r.recoveryScore = 80
            records.append(r)
        }
        let u = Set(records.map { cal.startOfDay(for: $0.date) }).count
        XCTAssertEqual(u, 364)
        let result = SeasonalLookbackBuilder.build(policy: policy, records: records, referenceDate: ref, calendar: cal)
        XCTAssertFalse(result.isEligible)

        let r365 = HelixDailyRecord()
        r365.date = cal.date(byAdding: .day, value: -364, to: ref)!
        r365.sleepScore = 80
        r365.recoveryScore = 80
        records.append(r365)
        let result2 = SeasonalLookbackBuilder.build(policy: policy, records: records, referenceDate: ref, calendar: cal)
        XCTAssertTrue(result2.isEligible)
    }

    /// Anchor is **t − 365** calendar days (prior-year window), not a rolling day-of-year bucket alone.
    func test_anchorDateIsReferenceMinusPolicyAnchorDays() {
        let cal = Calendar(identifier: .gregorian)
        let ref = DateComponents(calendar: cal, year: 2026, month: 6, day: 15).date!
        var records: [HelixDailyRecord] = []
        for i in 0..<400 {
            let r = HelixDailyRecord()
            r.date = cal.date(byAdding: .day, value: -i, to: ref)!
            r.sleepScore = 80
            r.recoveryScore = 80
            records.append(r)
        }
        let result = SeasonalLookbackBuilder.build(policy: policy, records: records, referenceDate: ref, calendar: cal)
        let expected = cal.startOfDay(
            for: cal.date(byAdding: .day, value: -policy.seasonalDetection.comparisonAnchorDaysAgo, to: ref)!
        )
        XCTAssertEqual(result.anchorDate, expected)
        XCTAssertGreaterThanOrEqual(result.matchedSampleCount, policy.seasonalDetection.minimumDaysInWindow)
    }

    func test_nonInterference_recordsUnchanged() {
        let cal = Calendar(identifier: .gregorian)
        let ref = DateComponents(calendar: cal, year: 2026, month: 3, day: 30).date!
        var records: [HelixDailyRecord] = []
        for i in 0..<400 {
            let r = HelixDailyRecord()
            r.date = cal.date(byAdding: .day, value: -i, to: ref)!
            r.sleepScore = Double(60 + (i % 5))
            r.recoveryScore = 70
            records.append(r)
        }
        let before = records.map { "\($0.date.timeIntervalSince1970),\($0.sleepScore),\($0.recoveryScore)" }
        _ = SeasonalLookbackBuilder.build(policy: policy, records: records, referenceDate: ref, calendar: cal)
        let after = records.map { "\($0.date.timeIntervalSince1970),\($0.sleepScore),\($0.recoveryScore)" }
        XCTAssertEqual(before, after)
    }
}
