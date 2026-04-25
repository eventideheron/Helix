// Engine/HelixBaselineEngine.swift
// Calculates personal EWMA baselines for all tracked signals.
//
// Two computation paths:
//   Fast path  — O(1) iterative EWMA using yesterday's cached SwiftData snapshot.
//                Used on all normal daily launches.
//   Slow path  — O(n) full 90-day historical scan. Used on first launch or after
//                a data gap exceeding iterativeGapDayThreshold (default: 7 days).
//   Medium path — iterative loop over a short gap (2–7 days). Bridges the
//                 two extremes without a full rescan.
//
// JSON key alignment: SignalIdentifier rawValues must match helix_policy decay_rates
// keys. A mismatch causes silent fallback to defaultDecayRate. The validate() call
// on startup catches this.

import Foundation

class HelixBaselineEngine {

    private let policy: HelixCorePolicy

    // Maximum gap (days) before we abandon iterative update and do a full rescan.
    private let iterativeGapDayThreshold = 7

    // Fallback decay rate when a signal key is absent from the policy JSON.
    // This should never fire after fixing the key alignment issue.
    private let defaultDecayRate = 0.94

    init(policy: HelixCorePolicy) {
        self.policy = policy
    }

    // MARK: — Version check
    // Call once at startup from HelixViewModel.init().
    // Prevents silent drift if policy files are updated without updating Swift models.
    func validatePolicyVersion(expected: String = "1.1") {
        guard policy.policyVersion == expected else {
            fatalError(
                """
                Policy version mismatch. Expected \(expected), \
                found \(policy.policyVersion). \
                Update HelixCorePolicy structs or bump the expected version string.
                """
            )
        }
    }

    // MARK: — Signal map
    // Single source of truth: (SignalIdentifier, HistoricalRawData keypath).
    // Adding a new signal requires only one entry here.
    private func signalMap(
        from history: HistoricalRawData
    ) -> [(SignalIdentifier, [(value: Double, date: Date)])] {
        [
            (.hrv,                  history.hrvReadings),
            (.restingHR,            history.rhrReadings),
            (.sleepDuration,        history.sleepReadings),
            (.deepSleepPercent,     history.deepSleepReadings),
            (.remSleepPercent,      history.remSleepReadings),
            (.overnightRespiratory, history.rrReadings),
            (.wristTemperature,     history.tempReadings),
            (.overnightHRDip,       history.dipReadings)
        ]
    }

    // MARK: — Build baselines (primary API)
    // Pass cachedSnapshots from SwiftData fetch. Pass nil or empty dict on first launch.
    func buildBaselines(
        from history: HistoricalRawData,
        cachedSnapshots: [SignalIdentifier: HelixBaselineSnapshot] = [:]
    ) -> [SignalIdentifier: PersonalBaseline] {

        var baselines = [SignalIdentifier: PersonalBaseline]()
        let rates = policy.baseline.decayRates

        for (signal, readings) in signalMap(from: history) {
            // rawValue matches the JSON key — enforced by SignalIdentifier definition.
            let decayRate = rates[signal.rawValue] ?? defaultDecayRate

            let ewmaValue = resolveEWMA(
                signal: signal,
                readings: readings,
                decayRate: decayRate,
                cachedSnapshots: cachedSnapshots
            )

            baselines[signal] = PersonalBaseline(
                signalName: signal.rawValue,
                value: ewmaValue,
                windowDays: policy.baseline.windowDays,
                decayRate: decayRate,
                dataPointCount: readings.count,
                lastUpdated: Date(),
                stabilityStatus: .stable
            )
        }

        return baselines
    }

    // MARK: — EWMA resolution (three paths)
    private func resolveEWMA(
        signal: SignalIdentifier,
        readings: [(value: Double, date: Date)],
        decayRate: Double,
        cachedSnapshots: [SignalIdentifier: HelixBaselineSnapshot]
    ) -> Double {

        guard let cached = cachedSnapshots[signal] else {
            // No cache — first launch slow path
            return calculateBaseline(readings: readings, decayRate: decayRate)
        }

        let today = Calendar.current.startOfDay(for: Date())
        let cachedDay = Calendar.current.startOfDay(for: cached.date)
        let gapDays = Calendar.current.dateComponents(
            [.day], from: cachedDay, to: today
        ).day ?? 0

        switch gapDays {
        case 0:
            // Cache is from today — return as-is (shouldn't normally happen, but safe)
            return cached.ewmaValue

        case 1:
            // Fast path: O(1) iterative update with today's most recent reading
            guard let todayReading = readings.last else {
                return cached.ewmaValue
            }
            return updateBaselineIteratively(
                todayValue: todayReading.value,
                yesterdayBaseline: cached.ewmaValue,
                decayRate: decayRate
            )

        case 2...iterativeGapDayThreshold:
            // Medium path: iterate over the gap days
            let gapReadings = readings.filter {
                $0.date >= cachedDay
            }.sorted { $0.date < $1.date }

            var runningBaseline = cached.ewmaValue
            for reading in gapReadings {
                runningBaseline = updateBaselineIteratively(
                    todayValue: reading.value,
                    yesterdayBaseline: runningBaseline,
                    decayRate: decayRate
                )
            }
            return runningBaseline

        default:
            // Gap too large — fall back to full 90-day scan
            return calculateBaseline(readings: readings, decayRate: decayRate)
        }
    }

    // MARK: — Iterative EWMA formula
    // EWMA_today = (value_today × (1 - α)) + (EWMA_yesterday × α)
    // where α = decayRate.
    func updateBaselineIteratively(
        todayValue: Double,
        yesterdayBaseline: Double,
        decayRate: Double
    ) -> Double {
        (todayValue * (1.0 - decayRate)) + (yesterdayBaseline * decayRate)
    }

    // MARK: — Full 90-day scan (slow path)
    func calculateBaseline(
        readings: [(value: Double, date: Date)],
        decayRate: Double
    ) -> Double {
        let windowDays = policy.baseline.windowDays
        let today = Date()
        var weightedSum = 0.0
        var weightTotal = 0.0

        for reading in readings {
            let daysAgo = Calendar.current.dateComponents(
                [.day], from: reading.date, to: today
            ).day ?? 0
            guard daysAgo <= windowDays else { continue }
            let weight = pow(decayRate, Double(daysAgo))
            weightedSum += reading.value * weight
            weightTotal += weight
        }

        return weightTotal > 0 ? weightedSum / weightTotal : 0
    }

    // MARK: — Snapshot for persistence
    // Call after buildBaselines. Persist the returned snapshots to SwiftData.
    func snapshotsForPersistence(
        from baselines: [SignalIdentifier: PersonalBaseline]
    ) -> [HelixBaselineSnapshot] {
        baselines.compactMap { (signal, baseline) in
            HelixBaselineSnapshot(
                date: Date(),
                signal: signal,
                ewmaValue: baseline.value,
                decayRate: baseline.decayRate,
                dataPointCount: baseline.dataPointCount,
                stabilityStatus: baseline.stabilityStatus
            )
        }
    }

    // MARK: — Validation ranges
    func validate(value: Double, for key: String) -> Bool {
        guard let range = policy.validationRanges[key] else { return true }
        return range.contains(value)
    }
}
