// History/HelixHistoryEngine.swift
// Longitudinal pattern detection, Today In History triggers, trend detection, milestones.
// Reads entirely from helix_history_policy.v1.1.json.
// Requires minimum 90 days of HelixDailyRecord data for basic history.
// Requires minimum 365 days for seasonal detection.

import Foundation
import SwiftData

struct HistoryResult {
    let todayInHistoryMessage: String?
    let triggerType:           String?
    let trendArrow:            TrendDirection?
    let milestoneMessage:      String?
    /// Apple Health HRV depth from the latest pipeline run (`dataPointCountAtCalculation`); not SwiftData row count.
    let appleHealthDays:       Int
    /// From `seasonal_outputs.message_modes` when classification is provisional or confirmed.
    let seasonalContextLine:   String?
    let seasonalWarning:       String?
}

enum TrendDirection { case up, flat, down }

class HelixHistoryEngine {

    private let policy: HelixHistoryPolicy

    init(policy: HelixHistoryPolicy) {
        self.policy = policy
    }

    // MARK: — Primary API

    func evaluate(
        today:            HelixIndex,
        allRecords:       [HelixDailyRecord],
        appleHealthDays:  Int
    ) -> HistoryResult {

        let activation = policy.activationRequirements
        let recordCount = allRecords.count

        guard recordCount >= activation.minimumDaysForBasicHistory else {
            return HistoryResult(
                todayInHistoryMessage: nil,
                triggerType: nil,
                trendArrow: trendArrow(records: allRecords, strand: .sleep), // available from day 1
                milestoneMessage: milestoneMessage(recordCount: recordCount, appleHealthDays: appleHealthDays),
                appleHealthDays: appleHealthDays,
                seasonalContextLine: nil,
                seasonalWarning: nil
            )
        }

        let todayInHistory  = evaluateTodayInHistory(today: today, records: allRecords)
        let trend           = trendArrow(records: allRecords, strand: nil)
        let milestone       = milestoneMessage(recordCount: recordCount, appleHealthDays: appleHealthDays)
        let seasonal = evaluateSeasonalOutput(records: allRecords)

        return HistoryResult(
            todayInHistoryMessage: todayInHistory?.message,
            triggerType:           todayInHistory?.type,
            trendArrow:            trend,
            milestoneMessage:      milestone,
            appleHealthDays:       appleHealthDays,
            seasonalContextLine:   seasonal?.context,
            seasonalWarning:       seasonal?.warning
        )
    }

    // MARK: — Today In History

    private typealias TriggerMatch = (message: String, type: String)

    private func evaluateTodayInHistory(
        today:   HelixIndex,
        records: [HelixDailyRecord]
    ) -> TriggerMatch? {

        // Personal record — top 95th percentile in last 365 days
        let lookback365 = records.filter {
            $0.date >= Calendar.current.date(byAdding: .day, value: -365, to: Date())!
        }
        let scores365 = lookback365.map(\.helixIndex).sorted()
        if !scores365.isEmpty {
            let p95 = percentile(scores365, 0.95)
            if today.score >= p95 {
                let days = lookback365.count
                return ("Your highest Helix Index in \(days) days.", "personal_record")
            }
        }

        // Streak milestone
        let streak = currentStreak(records: records)
        let milestones = [7, 14, 21, 30, 60, 90]
        if milestones.contains(streak) {
            return ("\(streak)-day streak of strong Helix scores.", "streak_milestone")
        }

        // HRV baseline improvement — 10% over 90 days
        let lookback90 = records.filter {
            $0.date >= Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        }
        if lookback90.count >= 30 {
            let oldAvg = lookback90.prefix(30).map(\.recoveryScore).reduce(0, +) / 30.0
            let newAvg = lookback90.suffix(30).map(\.recoveryScore).reduce(0, +) / 30.0
            if oldAvg > 0 {
                let improvement = (newAvg - oldAvg) / oldAvg
                if improvement >= 0.10 {
                    let pct = Int(improvement * 100)
                    return ("Your Recovery baseline has improved \(pct)% over the past 90 days.", "baseline_improvement")
                }
            }
        }

        // Strand record — top 95th percentile in last 180 days
        let lookback180 = records.filter {
            $0.date >= Calendar.current.date(byAdding: .day, value: -180, to: Date())!
        }
        let strandChecks: [(score: Double, name: String, allScores: [Double])] = [
            (today.sleepStrand.score,    "Sleep",    lookback180.map(\.sleepScore)),
            (today.loadStrand.score,     "Load",     lookback180.map(\.loadScore)),
            (today.recoveryStrand.score, "Recovery", lookback180.map(\.recoveryScore))
        ]
        for check in strandChecks {
            let sorted = check.allScores.sorted()
            if !sorted.isEmpty {
                let p95 = percentile(sorted, 0.95)
                if check.score >= p95 {
                    let days = lookback180.count
                    return ("Your strongest \(check.name) score in \(days) days.", "strand_record")
                }
            }
        }

        return nil
    }

    // MARK: — Streak calculation
    // Counts consecutive days with posture PURSUE or MODERATE

    private func currentStreak(records: [HelixDailyRecord]) -> Int {
        let sorted = records.sorted { $0.date > $1.date }
        var streak = 0
        for record in sorted {
            if record.posture == .pursue || record.posture == .moderate {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    // MARK: — Trend detection

    func trendArrow(records: [HelixDailyRecord], strand: HelixStrand?) -> TrendDirection {
        let shortWindow = policy.trendDetection.shortTrendDays
        let cutoff      = Calendar.current.date(byAdding: .day, value: -shortWindow, to: Date())!
        let recent      = records.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }

        guard recent.count >= 3 else { return .flat }

        let scores: [Double]
        switch strand {
        case .sleep:    scores = recent.map(\.sleepScore)
        case .load:     scores = recent.map(\.loadScore)
        case .recovery: scores = recent.map(\.recoveryScore)
        default:        scores = recent.map(\.helixIndex)
        }

        // Apply 3-day weighted moving average per policy
        let smoothed = weightedMovingAverage(scores, windowSize: 3)
        guard let first = smoothed.first, let last = smoothed.last, first > 0 else { return .flat }

        let change = (last - first) / first
        let upThreshold   = 0.05
        let downThreshold = 0.05

        if change > upThreshold   { return .up }
        if change < -downThreshold { return .down }
        return .flat
    }

    private func weightedMovingAverage(_ values: [Double], windowSize: Int) -> [Double] {
        guard values.count >= windowSize else { return values }
        var result: [Double] = []
        for i in (windowSize - 1)..<values.count {
            let window  = Array(values[(i - windowSize + 1)...i])
            let weights = (1...windowSize).map(Double.init)
            let sum     = zip(window, weights).map(*).reduce(0, +)
            let wSum    = weights.reduce(0, +)
            result.append(sum / wSum)
        }
        return result
    }

    // MARK: — Milestones

    private func milestoneMessage(recordCount: Int, appleHealthDays: Int) -> String? {
        let stages = policy.milestones.baselineMaturityStages
        let milestoneDays = [30, 60, 90, 180, 365]

        // Milestone markers use record count (genuine Helix history milestones)
        if milestoneDays.contains(recordCount) {
            let confidence = recordCount >= 90 ? "well-calibrated" : "developing"
            return "\(recordCount) days of Helix data. Your baseline is now \(confidence)."
        }

        // Maturity messaging uses Apple Health depth, not Helix row count
        switch appleHealthDays {
        case 0..<14:
            return stages.learning.message
                .replacingOccurrences(of: "{days_remaining}", with: "\(recordCount)")
        case 14..<90:
            return stages.developing.message
        default:
            return nil
        }
    }

    // MARK: — Seasonal detection (prior-year anchor; interpretation only — no score mutation)

    private func evaluateSeasonalOutput(records: [HelixDailyRecord]) -> (context: String?, warning: String?)? {
        let activation = policy.activationRequirements
        let uniqueDays = Set(records.map { Calendar.current.startOfDay(for: $0.date) }).count
        guard uniqueDays >= activation.minimumDaysForSeasonalDetection else { return nil }
        guard policy.seasonalDetection.enabled else { return nil }

        let outputs = policy.seasonalOutputs
        guard outputs.allowWarningMessages else { return nil }

        let result = SeasonalLookbackBuilder.build(policy: policy, records: records)
        guard result.sleepDeclineDetected || result.recoverySuppressionDetected else { return nil }

        var context: String?
        if outputs.allowExplanatoryContext {
            switch result.classification {
            case .confirmed:
                context = outputs.messageModes.confirmed
            case .provisional:
                context = outputs.messageModes.provisional
            case .none:
                context = nil
            }
        }

        var lines: [String] = []
        if result.sleepDeclineDetected {
            lines.append(
                "Your sleep scores are lower now than in this seasonal window from the prior year."
            )
        }
        if result.recoverySuppressionDetected {
            lines.append(
                "Recovery tends to be lower for you in this period versus the same window last year."
            )
        }
        guard !lines.isEmpty else { return nil }
        return (context, lines.joined(separator: "\n"))
    }

    // MARK: — Percentile utility

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[Swift.min(index, sorted.count - 1)]
    }
}
