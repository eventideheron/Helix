// SeasonalLookbackBuilder.swift
// Prior-year anchored seasonal window (policy-driven). Interpretation only — no scoring mutation.

import Foundation

enum SeasonalClassification: String, Equatable {
    case none
    case provisional
    case confirmed
}

struct SeasonalLookbackResult: Equatable {
    let isEligible: Bool
    let classification: SeasonalClassification
    let anchorDate: Date?
    let windowStart: Date?
    let windowEnd: Date?
    let matchedSampleCount: Int
    let correlation: Double?
    let sleepDeclineDetected: Bool
    let recoverySuppressionDetected: Bool
}

enum SeasonalLookbackBuilder {

    /// Builds a prior-year anchored lookback. `referenceDate` is typically "today" for UI; tests may fix it.
    static func build(
        policy: HelixHistoryPolicy,
        records: [HelixDailyRecord],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> SeasonalLookbackResult {

        let uniqueDays = Set(records.map { calendar.startOfDay(for: $0.date) }).count
        let minSeasonal = policy.activationRequirements.minimumDaysForSeasonalDetection
        let isEligible = uniqueDays >= minSeasonal

        guard policy.seasonalDetection.enabled else {
            return SeasonalLookbackResult(
                isEligible: isEligible,
                classification: .none,
                anchorDate: nil,
                windowStart: nil,
                windowEnd: nil,
                matchedSampleCount: 0,
                correlation: nil,
                sleepDeclineDetected: false,
                recoverySuppressionDetected: false
            )
        }

        let cfg = policy.seasonalDetection
        let anchorDaysAgo = cfg.comparisonAnchorDaysAgo
        guard let anchorMidnight = calendar.date(byAdding: .day, value: -anchorDaysAgo, to: referenceDate) else {
            return emptyResult(isEligible: isEligible)
        }
        let startOfAnchor = calendar.startOfDay(for: anchorMidnight)

        let before = cfg.comparisonWindowDaysBeforeAnchor
        let after = cfg.comparisonWindowDaysAfterAnchor
        guard let rawWindowStart = calendar.date(byAdding: .day, value: -before, to: startOfAnchor),
              let rawWindowEnd = calendar.date(byAdding: .day, value: after, to: startOfAnchor) else {
            return emptyResult(isEligible: isEligible)
        }
        let windowStart = calendar.startOfDay(for: rawWindowStart)
        let windowEnd = calendar.startOfDay(for: rawWindowEnd)

        let inWindow = records.filter {
            let d = calendar.startOfDay(for: $0.date)
            return d >= windowStart && d <= windowEnd
        }

        let maxDistance = Double(max(before, after))
        func distanceWeight(from recordDay: Date, to anchorDay: Date) -> Double {
            let d = abs(calendar.dateComponents([.day], from: anchorDay, to: recordDay).day ?? 0)
            let dd = min(Double(d), maxDistance)
            let exact = cfg.exactAnchorDayWeight
            let edge = cfg.edgeOfWindowWeight
            return exact - (exact - edge) * (dd / maxDistance)
        }

        var weightSum = 0.0
        var weightedSleep = 0.0
        var weightedRecovery = 0.0
        for r in inWindow {
            let w = distanceWeight(from: calendar.startOfDay(for: r.date), to: startOfAnchor)
            weightSum += w
            weightedSleep += r.sleepScore * w
            weightedRecovery += r.recoveryScore * w
        }

        guard weightSum > 0, inWindow.count >= cfg.minimumDaysInWindow else {
            return SeasonalLookbackResult(
                isEligible: isEligible,
                classification: .none,
                anchorDate: startOfAnchor,
                windowStart: windowStart,
                windowEnd: windowEnd,
                matchedSampleCount: inWindow.count,
                correlation: nil,
                sleepDeclineDetected: false,
                recoverySuppressionDetected: false
            )
        }

        let histSleep = weightedSleep / weightSum
        let histRecovery = weightedRecovery / weightSum

        let smoothDays = cfg.currentSmoothingWindowDays
        let refDay = calendar.startOfDay(for: referenceDate)
        guard let smoothStart = calendar.date(byAdding: .day, value: -(smoothDays - 1), to: refDay) else {
            return emptyResult(isEligible: isEligible)
        }
        let smoothStartDay = calendar.startOfDay(for: smoothStart)
        let smoothRecords = records.filter {
            let d = calendar.startOfDay(for: $0.date)
            return d >= smoothStartDay && d <= refDay
        }
        let byDay = Dictionary(grouping: smoothRecords) { calendar.startOfDay(for: $0.date) }
        let sortedDays = byDay.keys.sorted()
        let lastDays = Array(sortedDays.suffix(smoothDays))
        var curSleep = 0.0
        var curRecovery = 0.0
        var nSmooth = 0
        for day in lastDays {
            if let rec = byDay[day]?.last {
                curSleep += rec.sleepScore
                curRecovery += rec.recoveryScore
                nSmooth += 1
            }
        }
        guard nSmooth > 0 else {
            return SeasonalLookbackResult(
                isEligible: isEligible,
                classification: .none,
                anchorDate: startOfAnchor,
                windowStart: windowStart,
                windowEnd: windowEnd,
                matchedSampleCount: inWindow.count,
                correlation: nil,
                sleepDeclineDetected: false,
                recoverySuppressionDetected: false
            )
        }
        let curSleepAvg = curSleep / Double(nSmooth)
        let curRecoveryAvg = curRecovery / Double(nSmooth)

        let sleepDecline = histSleep - curSleepAvg > cfg.sleepDeclineThresholdPoints
        let recoverySupp = histRecovery - curRecoveryAvg > cfg.recoverySuppressionThresholdPoints

        let sortedRecords = records.sorted { $0.date < $1.date }
        let spanDays: Int = {
            guard let first = sortedRecords.first?.date, let last = sortedRecords.last?.date else { return 0 }
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last)).day ?? 0
        }()

        let pairs = pairedSleepScores(
            records: records,
            calendar: calendar,
            anchorCenter: startOfAnchor,
            currentCenter: refDay,
            offsetRange: before...after
        )
        let correlation = pearsonCorrelation(pairs: pairs)

        let hasSignal = sleepDecline || recoverySupp

        let pc = cfg.patternConfirmation
        let cls = cfg.classification
        let minSpanForConfirmed = max(730, pc.minimumYears * 365 - 1)
        let corrOK = (correlation ?? 0) >= pc.minimumCorrelation
        let enoughPairs = pairs.count >= max(5, pc.minimumRepeatObservations)

        let confirmedRule = cls.confirmedAfterSecondYear
            && spanDays >= minSpanForConfirmed
            && corrOK
            && enoughPairs

        let classification: SeasonalClassification
        if !isEligible || !hasSignal {
            classification = .none
        } else if confirmedRule {
            classification = .confirmed
        } else if cls.provisionalAfterFirstYear {
            classification = .provisional
        } else {
            classification = .none
        }

        return SeasonalLookbackResult(
            isEligible: isEligible,
            classification: classification,
            anchorDate: startOfAnchor,
            windowStart: windowStart,
            windowEnd: windowEnd,
            matchedSampleCount: inWindow.count,
            correlation: correlation,
            sleepDeclineDetected: sleepDecline,
            recoverySuppressionDetected: recoverySupp
        )
    }

    private static func emptyResult(isEligible: Bool) -> SeasonalLookbackResult {
        SeasonalLookbackResult(
            isEligible: isEligible,
            classification: .none,
            anchorDate: nil,
            windowStart: nil,
            windowEnd: nil,
            matchedSampleCount: 0,
            correlation: nil,
            sleepDeclineDetected: false,
            recoverySuppressionDetected: false
        )
    }

    /// Pairs sleep scores at `anchorCenter + offset` and `currentCenter + offset` when both days exist and current ≤ reference.
    private static func pairedSleepScores(
        records: [HelixDailyRecord],
        calendar: Calendar,
        anchorCenter: Date,
        currentCenter: Date,
        offsetRange: ClosedRange<Int>
    ) -> [(Double, Double)] {
        var pairs: [(Double, Double)] = []
        let anchor0 = calendar.startOfDay(for: anchorCenter)
        let current0 = calendar.startOfDay(for: currentCenter)
        for o in offsetRange {
            guard let dA = calendar.date(byAdding: .day, value: o, to: anchor0),
                  let dC = calendar.date(byAdding: .day, value: o, to: current0) else { continue }
            if dC > current0 { continue }
            guard let ra = records.first(where: { calendar.isDate($0.date, inSameDayAs: dA) }),
                  let rc = records.first(where: { calendar.isDate($0.date, inSameDayAs: dC) }) else { continue }
            pairs.append((ra.sleepScore, rc.sleepScore))
        }
        return pairs
    }

    private static func pearsonCorrelation(pairs: [(Double, Double)]) -> Double? {
        guard pairs.count >= 5 else { return nil }
        let n = Double(pairs.count)
        let meanX = pairs.map(\.0).reduce(0, +) / n
        let meanY = pairs.map(\.1).reduce(0, +) / n
        var num = 0.0, denX = 0.0, denY = 0.0
        for p in pairs {
            let dx = p.0 - meanX
            let dy = p.1 - meanY
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        let d = sqrt(denX) * sqrt(denY)
        guard d > 0 else { return nil }
        return num / d
    }
}
