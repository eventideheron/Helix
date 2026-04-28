// HealthKitProvidersHelpers.swift
// Extracted private helpers for HealthKitProviders to meet 300-line guideline.
// Same module; no change to public API or semantics.

import HealthKit
import Foundation

/// Circular clock timing SD (minutes, noon-aligned). Must stay aligned with `HelixSleepCalculator.standardDeviationMinutes`.
/// Minimum staged sleep (core/deep/REM/unspecified) for a night to contribute to **consistency** history only.
/// Matches `HelixSleepCalculator`’s 4h gate for staged-sleep scoring components (policy-driven default in strand; not duplicated in JSON here).
private let helixConsistencyHistoryMinStageHours: Double = 4.0
/// Merged staged total cannot exceed plausible primary-night sleep.
private let helixConsistencyMaxStageHours: Double = 14.0
private let helixConsistencyMaxBedWakeSpanHours: Double = 16.0
private let helixConsistencyStageVsSpanSlackHours: Double = 0.75

// MARK: — Merged intervals (sleep history / consistency admission)

private struct HelixMergedInterval: Comparable, Equatable {
    let start: Date
    let end: Date
    static func < (lhs: HelixMergedInterval, rhs: HelixMergedInterval) -> Bool {
        lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
    }
}

private func mergeIntervals(_ intervals: [HelixMergedInterval]) -> [HelixMergedInterval] {
    guard !intervals.isEmpty else { return [] }
    let sorted = intervals.sorted()
    var out: [HelixMergedInterval] = []
    var cur = sorted[0]
    for i in 1..<sorted.count {
        let n = sorted[i]
        if n.start <= cur.end {
            cur = HelixMergedInterval(start: cur.start, end: max(cur.end, n.end))
        } else {
            out.append(cur)
            cur = n
        }
    }
    out.append(cur)
    return out
}

private func totalMergedHours(_ intervals: [HelixMergedInterval]) -> Double {
    intervals.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600.0
}

private func isStagedSleepValue(_ value: Int) -> Bool {
    switch value {
    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
         HKCategoryValueSleepAnalysis.asleepREM.rawValue,
         HKCategoryValueSleepAnalysis.asleepCore.rawValue,
         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
        return true
    default:
        return false
    }
}

/// Merged union of staged segments (no double-counting overlaps).
private func mergedStagedSleepHours(in samples: [HKCategorySample]) -> Double {
    let iv = samples.filter { isStagedSleepValue($0.value) }
        .map { HelixMergedInterval(start: $0.startDate, end: $0.endDate) }
    return totalMergedHours(mergeIntervals(iv))
}

/// Deep / REM hours on merged intervals (separate merges per stage type).
private func mergedStageTypeHours(in samples: [HKCategorySample], value: Int) -> Double {
    let iv = samples.filter { $0.value == value }
        .map { HelixMergedInterval(start: $0.startDate, end: $0.endDate) }
    return totalMergedHours(mergeIntervals(iv))
}

/// Merged inBed hours only.
private func mergedInBedHours(in samples: [HKCategorySample]) -> Double {
    let iv = samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
        .map { HelixMergedInterval(start: $0.startDate, end: $0.endDate) }
    return totalMergedHours(mergeIntervals(iv))
}

/// Non-awake segments merged; bedtime / wake are bounds of the envelope; span is wall-clock length (gaps included in [bed,wake]).
private func mergedEnvelopeBedWakeSpan(from samples: [HKCategorySample]) -> (bed: Date?, wake: Date?, spanHours: Double) {
    let parts = samples.filter { $0.value != HKCategoryValueSleepAnalysis.awake.rawValue }
        .map { HelixMergedInterval(start: $0.startDate, end: $0.endDate) }
    guard !parts.isEmpty else { return (nil, nil, 0) }
    let merged = mergeIntervals(parts)
    guard let bed = merged.map(\.start).min(), let wake = merged.map(\.end).max() else { return (nil, nil, 0) }
    let span = wake.timeIntervalSince(bed) / 3600.0
    return (bed, wake, span)
}

/// Full `SleepRawData` rollups from samples using merged intervals (fetchSleepHistory / parse).
private func mergedSleepRollup(from samples: [HKCategorySample]) -> (
    stageTot: Double,
    deep: Double,
    rem: Double,
    inBedTot: Double,
    awakenings: Int,
    tot: Double
) {
    let stageTot = mergedStagedSleepHours(in: samples)
    let deep = mergedStageTypeHours(in: samples, value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue)
    let rem = mergedStageTypeHours(in: samples, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue)
    let inBedTot = mergedInBedHours(in: samples)
    let awakenings = samples.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }.count
    let tot = stageTot > 0 ? stageTot : inBedTot
    return (stageTot, deep, rem, inBedTot, awakenings, tot)
}

private func consistencyHistoryNightAcceptance(
    stageTotHours: Double,
    bedtime: Date?,
    wakeTime: Date?
) -> (accepted: Bool, reason: String) {
    if stageTotHours < helixConsistencyHistoryMinStageHours {
        return (false, "stageTot_lt_4h")
    }
    if stageTotHours > helixConsistencyMaxStageHours {
        return (false, "stageTot_gt_14h")
    }
    guard let bed = bedtime, let wake = wakeTime else {
        if bedtime == nil { return (false, "missing_bedtime") }
        return (false, "missing_wake")
    }
    let spanHours = wake.timeIntervalSince(bed) / 3600.0
    if spanHours < 1.0 {
        return (false, "bed_wake_span_lt_1h")
    }
    if spanHours > helixConsistencyMaxBedWakeSpanHours {
        return (false, "bed_wake_span_gt_16h")
    }
    if stageTotHours > spanHours + helixConsistencyStageVsSpanSlackHours {
        return (false, "stageTot_gt_span")
    }
    return (true, "ok")
}

private func helixTimingStandardDeviationMinutes(dates: [Date]) -> Double {
    guard dates.count > 1 else { return 0 }
    let calendar = Calendar.current
    let minutesSinceNoon = dates.map { date -> Double in
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minutesFromMidnight = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        let minutesFromNoon = minutesFromMidnight - 720
        return minutesFromNoon < 0 ? minutesFromNoon + 1440 : minutesFromNoon
    }
    let mean = minutesSinceNoon.reduce(0, +) / Double(minutesSinceNoon.count)
    let variance = minutesSinceNoon.map { pow($0 - mean, 2) }.reduce(0, +) / Double(minutesSinceNoon.count)
    return variance.squareRoot()
}

// MARK: — Sleep session isolation (Plan G)
// Multi-wearable / overlapping sessions: cluster by gap, prefer staged sleep (not inBed-only), take most recent cluster.

private let helixSleepSessionGapSeconds: TimeInterval = 90 * 60

private func isolatePrimarySleepSessionImpl(from samples: [HKCategorySample]) -> [HKCategorySample] {
    guard !samples.isEmpty else { return [] }

    // Prefer Apple-origin samples first; fallback to all when no Apple-origin samples exist.
    // Handles observed HealthKit sources such as:
    // - com.apple.NanoTimeKit.*
    // - com.apple.health.watch*
    // - com.apple.health.<UUID-like suffix>
    let watchSamples = samples.filter { s in
        let bid = s.sourceRevision.source.bundleIdentifier
        if bid.hasPrefix("com.apple.NanoTimeKit") { return true }
        if bid.hasPrefix("com.apple.health.watch") { return true }
        if bid.hasPrefix("com.apple.health.") { return true }
        return false
    }
    #if DEBUG
    let bundleIDs = Set(samples.map { $0.sourceRevision.source.bundleIdentifier })
    print("[HELIX DEBUG] isolatePrimarySession: sources=\(bundleIDs) watchCount=\(watchSamples.count) total=\(samples.count)")
    #endif
    let candidates = watchSamples.isEmpty ? samples : watchSamples

    let sorted = candidates.sorted { $0.startDate < $1.startDate }
    var clusters: [[HKCategorySample]] = []
    var chunk: [HKCategorySample] = []
    for s in sorted {
        if let last = chunk.last, s.startDate.timeIntervalSince(last.endDate) > helixSleepSessionGapSeconds {
            clusters.append(chunk)
            chunk = [s]
        } else {
            chunk.append(s)
        }
    }
    if !chunk.isEmpty { clusters.append(chunk) }

    func hasStagedSleep(_ c: [HKCategorySample]) -> Bool {
        c.contains { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue }
    }
    let preferred = clusters.filter(hasStagedSleep)
    let pool = preferred.isEmpty ? clusters : preferred
    let maxEnd: ([HKCategorySample]) -> Date = { $0.map(\.endDate).max() ?? .distantPast }
    guard let best = pool.max(by: { maxEnd($0) < maxEnd($1) }) else { return [] }
    return best
}

// MARK: — Consistency history: dominant overnight session (separate from Plan G isolation for duration/deep/REM/dip)

/// Reject consistency candidates whose staged sleep is far below the best same-night cluster (fragment guard).
private let helixConsistencyDominanceFraction: Double = 0.7

private func clusterSleepSessionsByGap(from samples: [HKCategorySample], gapSeconds: TimeInterval) -> [[HKCategorySample]] {
    guard !samples.isEmpty else { return [] }
    let sorted = samples.sorted { $0.startDate < $1.startDate }
    var clusters: [[HKCategorySample]] = []
    var chunk: [HKCategorySample] = []
    for s in sorted {
        if let last = chunk.last, s.startDate.timeIntervalSince(last.endDate) > gapSeconds {
            clusters.append(chunk)
            chunk = [s]
        } else {
            chunk.append(s)
        }
    }
    if !chunk.isEmpty { clusters.append(chunk) }
    return clusters
}

/// Overlap of merged session intervals with ~evening→afternoon window for this wake anchor day (8pm prior → 2pm wake day).
private func overnightOverlapHoursMerged(cluster: [HKCategorySample], wakeAnchorDay: Date, calendar: Calendar) -> Double {
    let intervals = cluster.map { HelixMergedInterval(start: $0.startDate, end: $0.endDate) }
    let merged = mergeIntervals(intervals)
    let dayStart = calendar.startOfDay(for: wakeAnchorDay)
    guard let windowStart = calendar.date(byAdding: .hour, value: -4, to: dayStart),
          let windowEnd = calendar.date(byAdding: .hour, value: 14, to: dayStart) else { return 0 }
    var sumSeconds: TimeInterval = 0
    for m in merged {
        let overlapStart = max(m.start, windowStart)
        let overlapEnd = min(m.end, windowEnd)
        sumSeconds += max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
    return sumSeconds / 3600.0
}

private func appleTieBreakScore(_ cluster: [HKCategorySample]) -> Int {
    cluster.contains { s in
        let bid = s.sourceRevision.source.bundleIdentifier
        return bid.hasPrefix("com.apple.NanoTimeKit") || bid.hasPrefix("com.apple.health.")
    } ? 1 : 0
}

private func stagedSegmentCount(_ cluster: [HKCategorySample]) -> Int {
    cluster.filter {
        [HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
         HKCategoryValueSleepAnalysis.asleepREM.rawValue,
         HKCategoryValueSleepAnalysis.asleepCore.rawValue,
         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue].contains($0.value)
    }.count
}

private func selectConsistencyDominantSession(
    from nightRaw: [HKCategorySample],
    wakeAnchorDay: Date,
    calendar: Calendar
) -> (samples: [HKCategorySample], selectionLog: String) {
    let clusters = clusterSleepSessionsByGap(from: nightRaw, gapSeconds: helixSleepSessionGapSeconds)
    guard !clusters.isEmpty else { return ([], "no_clusters") }

    struct Scored {
        let cluster: [HKCategorySample]
        let staged: Double
        let overlap: Double
        let spanHours: Double
        let stageSegCount: Int
        let apple: Int
    }

    func prefers(_ a: Scored, _ b: Scored) -> Bool {
        if abs(a.staged - b.staged) > 1e-9 { return a.staged > b.staged }
        if abs(a.overlap - b.overlap) > 1e-9 { return a.overlap > b.overlap }
        if abs(a.spanHours - b.spanHours) > 1e-9 { return a.spanHours < b.spanHours }
        if a.stageSegCount != b.stageSegCount { return a.stageSegCount > b.stageSegCount }
        return a.apple > b.apple
    }

    var scored: [Scored] = []
    for c in clusters {
        let staged = mergedStagedSleepHours(in: c)
        let ov = overnightOverlapHoursMerged(cluster: c, wakeAnchorDay: wakeAnchorDay, calendar: calendar)
        let (_, _, span) = mergedEnvelopeBedWakeSpan(from: c)
        scored.append(Scored(
            cluster: c,
            staged: staged,
            overlap: ov,
            spanHours: span,
            stageSegCount: stagedSegmentCount(c),
            apple: appleTieBreakScore(c)
        ))
    }

    let maxStaged = scored.map(\.staged).max() ?? 0
    let viable = scored.filter { $0.staged >= maxStaged * helixConsistencyDominanceFraction - 1e-9 }
    let viablePool = viable.isEmpty ? scored : viable

    func acceptable(_ s: Scored) -> Bool {
        let (bed, wake, _) = mergedEnvelopeBedWakeSpan(from: s.cluster)
        return consistencyHistoryNightAcceptance(
            stageTotHours: s.staged,
            bedtime: bed,
            wakeTime: wake
        ).accepted
    }

    var pool = viablePool.filter(acceptable)
    if pool.isEmpty {
        pool = scored.filter(acceptable)
    }
    guard !pool.isEmpty else {
        return ([], "no_acceptable_cluster merged_metrics")
    }

    let best = pool.reduce(pool[0]) { prefers($1, $0) ? $1 : $0 }

    let candStr = scored.map { s -> String in
        let tag = s.staged < maxStaged * helixConsistencyDominanceFraction - 1e-9 ? "sub" : "ok"
        let acc = acceptable(s) ? "acc" : "rej"
        return String(format: "st=%.2f ov=%.2f sp=%.2f %@ %@ ap=%d", s.staged, s.overlap, s.spanHours, tag, acc, s.apple)
    }.joined(separator: " | ")
    let log = String(
        format: "clusters=%d maxSt=%.2f [%@] pick st=%.2f ov=%.2f sp=%.2f ap=%d",
        clusters.count,
        maxStaged,
        candStr,
        best.staged,
        best.overlap,
        best.spanHours,
        best.apple
    )
    return (best.cluster, log)
}


private func isolateSleepSessionsPerNightImpl(from samples: [HKCategorySample]) -> [HKCategorySample] {
    let calendar = Calendar.current
    var byNight = [DateComponents: [HKCategorySample]]()
    for s in samples {
        let key = calendar.dateComponents([.year, .month, .day], from: s.endDate)
        byNight[key, default: []].append(s)
    }
    var flat: [HKCategorySample] = []
    for (_, nightSamples) in byNight.sorted(by: { ($0.key.date ?? .distantPast) < ($1.key.date ?? .distantPast) }) {
        flat.append(contentsOf: isolatePrimarySleepSessionImpl(from: nightSamples))
    }
    return flat
}

// MARK: — SleepDataProvider helpers

extension SleepDataProvider {

    /// Plan G: single primary sleep session from multi-source overlapping samples (4h gap clustering).
    func isolatePrimarySession(from samples: [HKCategorySample]) -> [HKCategorySample] {
        isolatePrimarySleepSessionImpl(from: samples)
    }

    /// Plan G: one primary session per calendar wake day (endDate key), flattened for consistency extraction.
    func isolateSessionsPerNight(from samples: [HKCategorySample]) -> [HKCategorySample] {
        isolateSleepSessionsPerNightImpl(from: samples)
    }

    func parse(
        samples: [HKCategorySample],
        bedtimes: [Date],
        wakeTimes: [Date],
        wristTempDelta: Double?,
        overnightRR: Double?,
        minSleepHR: Double?
    ) -> SleepRawData {
        // Merged non-overlapping intervals for stage / deep / REM / inBed (no HK overlap inflation).
        let roll = mergedSleepRollup(from: samples)
        _ = roll.stageTot
        let deep = roll.deep
        let rem = roll.rem
        _ = roll.inBedTot
        let awakenings = roll.awakenings
        let total = roll.tot

        // HK stores absolute °C; delta vs personal baseline is applied in ViewModel after `buildBaselines`.
        return SleepRawData(
            totalDurationHours:       total,
            deepSleepPercent:         total > 0 ? deep / total : 0,
            remSleepPercent:          total > 0 ? rem  / total : 0,
            awakeningsPerHour:        total > 0 ? Double(awakenings) / total : 0,
            bedtimes:                 bedtimes,
            wakeTimes:                wakeTimes,
            wristTempAbsoluteCelsius: wristTempDelta,
            wristTempDeltaCelsius:    nil,
            overnightRespiratoryRate: overnightRR,
            minSleepHR:               minSleepHR
        )
    }

    func extractBedtimeWakePairs(from samples: [HKCategorySample]) -> ([Date], [Date]) {
        let calendar = Calendar.current
        var byNight = [DateComponents: [HKCategorySample]]()
        for s in samples {
            let key = calendar.dateComponents([.year, .month, .day], from: s.endDate)
            byNight[key, default: []].append(s)
        }
        var beds: [Date] = [], wakes: [Date] = []
        for (_, nightSamples) in byNight.sorted(by: { ($0.key.date ?? .distantPast) < ($1.key.date ?? .distantPast) }) {
            let (b, w, _) = mergedEnvelopeBedWakeSpan(from: nightSamples)
            if let bed = b, let wake = w {
                beds.append(bed)
                wakes.append(wake)
            }
        }
        return (beds, wakes)
    }

    func fetchMinHeartRateDuringSleep(sleepSamples: [HKCategorySample]) async throws -> Double? {
        guard let start = sleepSamples.map({ $0.startDate }).min(),
              let end   = sleepSamples.map({ $0.endDate }).max(),
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)
        else { return nil }

        let unit    = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: hrType,
                                  predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        guard samples.count >= 60 else { return nil }  // Policy: minimum_hr_samples_required
        return samples.map { $0.quantity.doubleValue(for: unit) }.min()
    }

    func fetchOvernightAverage(type id: HKQuantityTypeIdentifier, sleepSamples: [HKCategorySample], unit: HKUnit) async throws -> Double? {
        guard let start   = sleepSamples.map({ $0.startDate }).min(),
              let end     = sleepSamples.map({ $0.endDate }).max(),
              let qType   = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: qType, predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        guard !samples.isEmpty else { return nil }
        let vals = samples.map { $0.quantity.doubleValue(for: unit) }
        return vals.reduce(0, +) / Double(vals.count)
    }

    func fetchMostRecentQuantity(type id: HKQuantityTypeIdentifier, withinHours h: Int, unit: HKUnit) async throws -> Double? {
        guard let qType = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.date(byAdding: .hour, value: -h, to: Date())!
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: qType, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                                  limit: 1, sortDescriptors: [sort]) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKQuantitySample])?.first?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    func fetchCategorySamples(type: HKCategoryType, start: Date, end: Date) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
    }
}

// MARK: — RecoveryDataProvider helpers

extension RecoveryDataProvider {

    /// Prioritises an HRV sample from the overnight/morning window (startHour–endHour local time today).
    /// Falls back to the most recent sample within the past 24 hours when no morning sample is present,
    /// or when the morning window has not yet started (e.g. app opened before startHour).
    func fetchMorningWindowHRV(startHour: Int, endHour: Int, unit: HKUnit) async throws -> Double? {
        guard let qType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let calendar  = Calendar.current
        let now       = Date()
        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .hour, value: startHour, to: todayStart),
              let windowEnd   = calendar.date(byAdding: .hour, value: endHour,   to: todayStart),
              windowStart < now else {
            // Morning window hasn't opened yet — fall back immediately.
            #if DEBUG
            print("[HELIX DEBUG] fetchMorningWindowHRV: window not yet open — falling back to withinHours:24")
            #endif
            return try await fetchMostRecent(type: .heartRateVariabilitySDNN, withinHours: 24, unit: unit)
        }
        let clampedEnd = min(windowEnd, now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let morningHRV: Double? = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: qType,
                                  predicate: HKQuery.predicateForSamples(withStart: windowStart, end: clampedEnd),
                                  limit: 1, sortDescriptors: [sort]) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKQuantitySample])?.first?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
        #if DEBUG
        if let v = morningHRV {
            print(String(format: "[HELIX DEBUG] fetchMorningWindowHRV: morning window hit %.1f ms (window %02d:00–%02d:00)", v, startHour, endHour))
        } else {
            print("[HELIX DEBUG] fetchMorningWindowHRV: no morning sample — falling back to withinHours:24")
        }
        #endif
        if let v = morningHRV { return v }
        return try await fetchMostRecent(type: .heartRateVariabilitySDNN, withinHours: 24, unit: unit)
    }

    func fetchSpO2RollingAverage(nights: Int) async throws -> Double? {
        guard let spo2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else { return nil }
        let start   = Calendar.current.date(byAdding: .day, value: -nights, to: Date())!
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: spo2Type, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        guard !samples.isEmpty else { return nil }
        // HealthKit SpO2 is fraction 0.0–1.0; normalisation engine converts to percentage
        let vals = samples.map { $0.quantity.doubleValue(for: .percent()) }
        return vals.reduce(0, +) / Double(vals.count)   // Returned as fraction; normalised downstream
    }

    func fetchMostRecent(type id: HKQuantityTypeIdentifier, withinHours h: Int, unit: HKUnit) async throws -> Double? {
        guard let qType = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.date(byAdding: .hour, value: -h, to: Date())!
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: qType, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                                  limit: 1, sortDescriptors: [sort]) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKQuantitySample])?.first?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }
}

// MARK: — LoadDataProvider helpers

extension LoadDataProvider {

    func fetchWorkouts(predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    func fetchHRDuringWorkouts(_ workouts: [HKWorkout]) async throws -> [HKQuantitySample] {
        guard !workouts.isEmpty, let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        var all: [HKQuantitySample] = []
        for w in workouts {
            let pred = HKQuery.predicateForSamples(withStart: w.startDate, end: w.endDate)
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
                let q = HKSampleQuery(sampleType: hrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, e in
                    if let e = e { cont.resume(throwing: e); return }
                    cont.resume(returning: (r as? [HKQuantitySample]) ?? [])
                }
                store.execute(q)
            }
            all.append(contentsOf: samples)
        }
        return all
    }

    func fetchStatSum(type id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async throws -> Double {
        guard let qType = HKObjectType.quantityType(forIdentifier: id) else { return 0 }
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: qType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, s, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: s?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    /// Fetches workouts and HR samples for the past `days` and returns proxy types for baseline ACWR computation.
    func fetchWorkoutAndHRHistory(days: Int) async throws -> (workouts: [HKWorkoutProxy], heartRateSamples: [HKSampleProxy]) {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let workoutsHK = try await fetchWorkouts(predicate: pred)
        let hrSamplesHK = try await fetchHRDuringWorkouts(workoutsHK)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let workouts = workoutsHK.map { w in
            HKWorkoutProxy(startDate: w.startDate, endDate: w.endDate, duration: w.duration, activityType: w.workoutActivityType.rawValue)
        }
        let samples = hrSamplesHK.map { s in
            HKSampleProxy(value: s.quantity.doubleValue(for: bpm), startDate: s.startDate, endDate: s.endDate)
        }
        return (workouts, samples)
    }
}

// MARK: — HistoryDataProvider helpers

extension HistoryDataProvider {

    /// Aggregates per-sample quantity history into one reading per calendar day (sum of values that day).
    /// Used for active energy so baseline EWMA has one value per day.
    func aggregateQuantityHistoryByDay(_ readings: [(value: Double, date: Date)]) -> [(value: Double, date: Date)] {
        let calendar = Calendar.current
        var byDay: [Date: Double] = [:]
        for r in readings {
            let day = calendar.startOfDay(for: r.date)
            byDay[day, default: 0] += r.value
        }
        return byDay.sorted { $0.key < $1.key }.map { (value: $0.value, date: $0.key) }
    }

    func fetchQuantityHistory(type id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async throws -> [(value: Double, date: Date)] {
        guard let qType = HKObjectType.quantityType(forIdentifier: id) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: qType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKQuantitySample])?.map { ($0.quantity.doubleValue(for: unit), $0.startDate) } ?? [])
            }
            store.execute(q)
        }
    }

    /// Historical dip series only: minimum sample count from policy (`minimum_historical_hr_samples`); today’s path remains 60 in `fetchMinHeartRateDuringSleep`.
    /// Drops HR samples above 90 bpm before `min()` to reduce artifact spikes.
    private func minHistoricalOvernightHRFromSamples(
        hrSamples: [HKQuantitySample],
        unit bpm: HKUnit,
        minimumCount: Int
    ) -> Double? {
        let artifactCapBpm = 90.0
        let rawCount = hrSamples.count
        let vals = hrSamples.map { $0.quantity.doubleValue(for: bpm) }.filter { $0 <= artifactCapBpm }
        #if DEBUG
        print("[HELIX DEBUG] minHistoricalOvernightHR: raw=\(rawCount) after≤90bpm=\(vals.count) need≥\(minimumCount) pass=\(vals.count >= minimumCount)")
        #endif
        guard vals.count >= minimumCount else { return nil }
        return vals.min()
    }

    /// Plan G: same primary-session rule as `SleepDataProvider` for per-night HR window.
    func isolatePrimarySession(from samples: [HKCategorySample]) -> [HKCategorySample] {
        isolatePrimarySleepSessionImpl(from: samples)
    }

    func fetchSleepHistory(days: Int, historicalMinHrSamples: Int) async throws -> (
        duration: [(value: Double, date: Date)],
        deepPercent: [(value: Double, date: Date)],
        remPercent: [(value: Double, date: Date)],
        hrDips: [(value: Double, date: Date)],
        consistencyReadings: [(value: Double, date: Date)],
        awakeningsPerHourReadings: [(value: Double, date: Date)]
    ) {
        let start     = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, e in
                if let e = e { cont.resume(throwing: e); return }
                cont.resume(returning: (r as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        #if DEBUG
        let distinctValues = Set(samples.map(\.value))
        print("[Helix] fetchSleepHistory HK sleep sample distinct values (full set, count=\(distinctValues.count)): \(distinctValues.sorted())")
        #endif
        #if DEBUG
        print("[HELIX DEBUG] fetchSleepHistory samples.count=\(samples.count)")
        #endif

        let calendar = Calendar.current
        var byNight = [DateComponents: [HKCategorySample]]()
        for s in samples {
            let key = calendar.dateComponents([.year, .month, .day], from: s.endDate)
            byNight[key, default: []].append(s)
        }

        var durations: [(Double, Date)] = [], deeps: [(Double, Date)] = []
        var rems: [(Double, Date)] = [], dips: [(Double, Date)] = []
        var consistency: [(Double, Date)] = [], awakeningsPerHour: [(Double, Date)] = []
        var nightData: [(date: Date, bedtime: Date?, wakeTime: Date?, stageTotHours: Double, totHours: Double, awakeningsCount: Int)] = []
        let bpm = HKUnit.count().unitDivided(by: .minute())

        for (comp, nightRaw) in byNight.sorted(by: { ($0.key.date ?? .distantPast) < ($1.key.date ?? .distantPast) }) {
            guard let date = calendar.date(from: comp) else { continue }
            // Plan G isolation: duration, deep/REM %, awakenings, overnight HR dip (unchanged).
            let nights = isolatePrimarySession(from: nightRaw)
            let (pickedConsistency, consistencySelectionLog) = selectConsistencyDominantSession(
                from: nightRaw,
                wakeAnchorDay: date,
                calendar: calendar
            )
            let consistencySamples = pickedConsistency.isEmpty ? nights : pickedConsistency

            let metricsRoll = mergedSleepRollup(from: nights)
            let deep = metricsRoll.deep
            let rem = metricsRoll.rem
            let awakeningsCount = metricsRoll.awakenings
            let tot = metricsRoll.tot

            // Rolling consistency: merged staged + merged envelope bed/wake from dominant session.
            let cStageTot = mergedStagedSleepHours(in: consistencySamples)
            let consistencyEnv = mergedEnvelopeBedWakeSpan(from: consistencySamples)
            let bedtime = consistencyEnv.bed
            let wakeTime = consistencyEnv.wake
            #if DEBUG
            let nightStageTot = metricsRoll.stageTot
            let nightInBedTot = metricsRoll.inBedTot
            let cSpan = consistencyEnv.spanHours
            let (consistencyAccepted, consistencyReason) = consistencyHistoryNightAcceptance(
                stageTotHours: cStageTot,
                bedtime: bedtime,
                wakeTime: wakeTime
            )
            let tf = DateFormatter()
            tf.locale = Locale(identifier: "en_US_POSIX")
            tf.timeStyle = .short
            tf.dateStyle = .none
            let bedStr = bedtime.map { tf.string(from: $0) } ?? "nil"
            let wakeStr = wakeTime.map { tf.string(from: $0) } ?? "nil"
            print("[HELIX DEBUG] historicalNight date=\(date) metrics isolated=\(nights.count) mergedSt=\(String(format: "%.2f", nightStageTot))h mergedInBed=\(String(format: "%.2f", nightInBedTot))h span=\(String(format: "%.2f", cSpan))h | \(consistencySelectionLog)")
            print("[HELIX DEBUG] consistencyNight date=\(date) mergedStageTot=\(String(format: "%.2f", cStageTot))h bed=\(bedStr) wake=\(wakeStr) accepted=\(consistencyAccepted) reason=\(consistencyReason)")
            #endif
            nightData.append((date: date, bedtime: bedtime, wakeTime: wakeTime, stageTotHours: cStageTot, totHours: tot, awakeningsCount: awakeningsCount))
            if tot >= 2.0 {
                durations.append((tot, date))
                deeps.append((deep / tot, date))
                rems.append((rem / tot, date))
                awakeningsPerHour.append((Double(awakeningsCount) / tot, date))
            }
            // HR dip for this night
            if let sleepStart = nights.map({ $0.startDate }).min(),
               let sleepEnd   = nights.map({ $0.endDate }).max(),
               let hrType     = HKObjectType.quantityType(forIdentifier: .heartRate) {
                let hrSamples: [HKQuantitySample] = (try? await withCheckedThrowingContinuation { cont in
                    let q = HKSampleQuery(sampleType: hrType, predicate: HKQuery.predicateForSamples(withStart: sleepStart, end: sleepEnd),
                                          limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, e in
                        if let e = e { cont.resume(throwing: e); return }
                        cont.resume(returning: (r as? [HKQuantitySample]) ?? [])
                    }
                    store.execute(q)
                }) ?? []
                if let minHR = minHistoricalOvernightHRFromSamples(
                    hrSamples: hrSamples,
                    unit: bpm,
                    minimumCount: historicalMinHrSamples
                ) {
                    dips.append((minHR, date))
                }
            }
        }
        // Bedtime SD + wake SD over rolling 7-night window, **consistency-eligible nights only** (duration/deep/REM/dip/awakenings unchanged above).
        let windowSize = 7
        for i in 0..<nightData.count {
            let startIdx = max(0, i - windowSize + 1)
            let slice = nightData[startIdx...i]
            let eligible = slice.filter {
                consistencyHistoryNightAcceptance(
                    stageTotHours: $0.stageTotHours,
                    bedtime: $0.bedtime,
                    wakeTime: $0.wakeTime
                ).accepted
            }
            let bedDates = eligible.compactMap { $0.bedtime }
            if bedDates.isEmpty { continue }
            let wakeDates = eligible.compactMap { $0.wakeTime }
            let combined = helixTimingStandardDeviationMinutes(dates: bedDates)
                + helixTimingStandardDeviationMinutes(dates: wakeDates)
            let endDate = nightData[i].date
            if bedDates.count >= 2 {
                consistency.append((combined, endDate))
                #if DEBUG
                print("[HELIX DEBUG] consistencyReading end=\(endDate) value=\(String(format: "%.2f", combined)) eligibleNights=\(eligible.count)/\(slice.count)")
                #endif
            } else if bedDates.count == 1 {
                consistency.append((0, endDate))
                #if DEBUG
                print("[HELIX DEBUG] consistencyReading end=\(endDate) value=0.00 eligibleNights=1/\(slice.count)")
                #endif
            }
        }
        let sortedDurations = durations.sorted { $0.1 < $1.1 }
        let sortedDeeps = deeps.sorted { $0.1 < $1.1 }
        let sortedRems = rems.sorted { $0.1 < $1.1 }
        let sortedDips = dips.sorted { $0.1 < $1.1 }
        let sortedConsistency = consistency.sorted { $0.1 < $1.1 }
        let sortedAwakenings = awakeningsPerHour.sorted { $0.1 < $1.1 }
        #if DEBUG
        let firstConsistency = sortedConsistency.first.map { "\($0.0) @ \($0.1)" } ?? "<none>"
        let firstDip = sortedDips.first.map { "\($0.0) @ \($0.1)" } ?? "<none>"
        let firstAwakening = sortedAwakenings.first.map { "\($0.0) @ \($0.1)" } ?? "<none>"
        print("[HELIX DEBUG] boundary-1 fetchSleepHistory return counts: consistency=\(sortedConsistency.count) dipMinHR=\(sortedDips.count) awakenings=\(sortedAwakenings.count)")
        print("[HELIX DEBUG] boundary-1 first samples: consistency=\(firstConsistency) dipMinHR=\(firstDip) awakenings=\(firstAwakening)")
        if sortedConsistency.isEmpty { print("[HELIX DEBUG][WARN] boundary-1 consistencyReadings empty at fetchSleepHistory return") }
        if sortedDips.isEmpty { print("[HELIX DEBUG][WARN] boundary-1 hrDips empty at fetchSleepHistory return") }
        if sortedAwakenings.isEmpty { print("[HELIX DEBUG][WARN] boundary-1 awakeningsPerHourReadings empty at fetchSleepHistory return") }
        #endif
        return (sortedDurations, sortedDeeps, sortedRems, sortedDips, sortedConsistency, sortedAwakenings)
    }
}

