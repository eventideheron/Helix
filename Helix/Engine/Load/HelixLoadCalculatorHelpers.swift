// HelixLoadCalculatorHelpers.swift
// Extracted private helpers for HelixLoadCalculator to meet 300-line guideline.
// Same module; no change to public API or scoring semantics.

import Foundation

// MARK: — HR elevation (temporal window)

/// Which workout HR sample pool feeds **hrElevation** (recent strain, not a long pooled archive).
enum HrElevationSourceMode: String {
    case today = "today"
    case last7Days = "last_7_days"
    case noneRecent = "none_recent"
}

extension HelixLoadCalculator {

    /// Minimum HR samples required to treat a window as meaningful; otherwise fall back or neutral.
    private static let hrElevationMinSamples = 3

    /// HR samples whose `startDate` lies inside any of given workouts' `[startDate, endDate]`.
    func heartRateSamplesInWorkouts(_ samples: [HKSampleProxy], workouts: [HKWorkoutProxy]) -> [HKSampleProxy] {
        samples.filter { sample in
            workouts.contains { w in
                sample.startDate >= w.startDate && sample.startDate <= w.endDate
            }
        }
    }

    /// Workouts overlapping the local calendar day of `reference`.
    func workoutsOverlappingCalendarDay(_ workouts: [HKWorkoutProxy], day: Date, calendar: Calendar) -> [HKWorkoutProxy] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return workouts.filter { $0.endDate > dayStart && $0.startDate < dayEnd }
    }

    /// Workouts that overlap `[windowStart, now]`.
    func workoutsOverlappingWindow(_ workouts: [HKWorkoutProxy], windowStart: Date, now: Date) -> [HKWorkoutProxy] {
        workouts.filter { $0.endDate > windowStart && $0.startDate <= now }
    }

    /// **Rule 1:** today’s workouts + enough HR samples → **today**. **Rule 2:** else last 7 days with enough samples → **last_7_days**. **Rule 3:** else **none_recent** (neutral score in calculator).
    func selectHrElevationWorkoutHRSamples(
        workouts: [HKWorkoutProxy],
        hrSamples: [HKSampleProxy],
        now: Date,
        calendar: Calendar = .current
    ) -> (samples: [HKSampleProxy], mode: HrElevationSourceMode) {
        let minN = Self.hrElevationMinSamples
        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -7, to: todayStart) else {
            return ([], .noneRecent)
        }

        let workoutsToday = workoutsOverlappingCalendarDay(workouts, day: now, calendar: calendar)
        let samplesToday = heartRateSamplesInWorkouts(hrSamples, workouts: workoutsToday)

        if !workoutsToday.isEmpty, samplesToday.count >= minN {
            return (samplesToday, .today)
        }

        let workouts7d = workoutsOverlappingWindow(workouts, windowStart: windowStart, now: now)
        let samples7d = heartRateSamplesInWorkouts(hrSamples, workouts: workouts7d)

        if samples7d.count >= minN {
            return (samples7d, .last7Days)
        }

        return ([], .noneRecent)
    }
}


extension HelixLoadCalculator {

    func computeDailyTSS(
        workouts:   [HKWorkoutProxy],
        hrSamples:  [HKSampleProxy],
        ageContext: LoadCalculationContext,
        energyKcal: Double
    ) -> [(tss: Double, date: Date)] {

        let maxHR       = ageContext.maxHeartRate
        let multipliers = policy.heartRateZones.zoneStressMultipliers
        let zones       = zoneThresholds(maxHR: maxHR)
        let calendar    = Calendar.current

        // Group HR samples by workout
        var byWorkout = [Date: [(Double, Date)]]()
        for workout in workouts {
            let wSamples = hrSamples.filter {
                $0.startDate >= workout.startDate && $0.startDate <= workout.endDate
            }
            let key = calendar.startOfDay(for: workout.startDate)
            byWorkout[key, default: []].append(contentsOf: wSamples.map { ($0.value, $0.startDate) })
        }

        // Compute TSS per day
        var tssHistory: [(tss: Double, date: Date)] = []

        for (day, daySamples) in byWorkout {
            var tss = 0.0
            for i in 0..<daySamples.count {
                let hr         = daySamples[i].0
                let zone       = heartRateZone(hr: hr, zones: zones)
                let multiplier: Double = multipliers["zone_\(zone)"] ?? 1.0
                // Minutes between this sample and next (or 1 min for last sample)
                let minutes: Double
                if i < daySamples.count - 1 {
                    minutes = daySamples[i + 1].1.timeIntervalSince(daySamples[i].1) / 60.0
                } else {
                    minutes = 1.0
                }
                tss += max(0, min(minutes, 5.0)) * multiplier  // Cap interval at 5 min to handle gaps
            }
            tssHistory.append((tss: tss, date: day))
        }

        // NEAT contribution for days without workouts
        let workoutDays = Set(tssHistory.map { $0.date })
        let neatTSS = energyKcal * policy.heartRateZones.neatEnergyMultiplier
        let today = calendar.startOfDay(for: Date())
        if !workoutDays.contains(today) && neatTSS > 0 {
            tssHistory.append((tss: neatTSS, date: today))
        }

        return tssHistory.sorted { $0.date < $1.date }
    }

    func zoneThresholds(maxHR: Double) -> [(low: Double, high: Double)] {
        return [
            (0.50 * maxHR, 0.60 * maxHR),
            (0.60 * maxHR, 0.70 * maxHR),
            (0.70 * maxHR, 0.80 * maxHR),
            (0.80 * maxHR, 0.90 * maxHR),
            (0.90 * maxHR, maxHR)
        ]
    }

    func heartRateZone(hr: Double, zones: [(low: Double, high: Double)]) -> Int {
        for (i, zone) in zones.enumerated() {
            if hr >= zone.low && hr < zone.high { return i + 1 }
        }
        return hr < zones[0].low ? 1 : 5
    }

    func ewmaLoad(dailyTSS: [(tss: Double, date: Date)], windowDays: Int, decay: Double) -> Double {
        ewmaLoadAsOf(dailyTSS: dailyTSS, asOf: Date(), windowDays: windowDays, decay: decay)
    }

    /// EWMA of daily TSS as of a given reference date (for historical ACWR series).
    func ewmaLoadAsOf(dailyTSS: [(tss: Double, date: Date)], asOf referenceDate: Date, windowDays: Int, decay: Double) -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: referenceDate)!
        let relevant = dailyTSS.filter { $0.date >= cutoff && $0.date <= referenceDate }
        guard !relevant.isEmpty else { return 0 }
        var weightedSum = 0.0, weightTotal = 0.0
        for entry in relevant {
            let daysAgo = Calendar.current.dateComponents([.day], from: entry.date, to: referenceDate).day ?? 0
            let weight  = pow(decay, Double(daysAgo))
            weightedSum += entry.tss * weight
            weightTotal += weight
        }
        return weightTotal > 0 ? weightedSum / weightTotal : 0
    }

    func acwrScore(acwr: Double) -> Double {
        let bands = policy.acwrScoring
        switch acwr {
        case ..<bands.undertrainingCeiling:
            // Undertraining — score linearly from 40 to 60 as acwr approaches optimal_low
            let progress = acwr / bands.undertrainingCeiling
            return (40.0 + progress * 20.0).clampedToHelixScore()
        case bands.undertrainingCeiling..<bands.optimalLow:
            // Transitional — 60 to 80
            let range    = bands.optimalLow - bands.undertrainingCeiling
            let progress = (acwr - bands.undertrainingCeiling) / range
            return (60.0 + progress * 20.0).clampedToHelixScore()
        case bands.optimalLow...bands.optimalHigh:
            // Optimal — 80 to 100
            return 90.0
        case bands.optimalHigh..<bands.cautionCeiling:
            // Caution — 50 to 80 (declining as load rises)
            let range    = bands.cautionCeiling - bands.optimalHigh
            let excess   = acwr - bands.optimalHigh
            return (80.0 - (excess / range) * 30.0).clampedToHelixScore()
        default:
            // Excessive — below 50, declining further
            let excess = acwr - bands.cautionCeiling
            return (50.0 - excess * 20.0).clampedToHelixScore()
        }
    }

    func acuteLoadScore(acuteLoad: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 50.0 }
        let ratio = acuteLoad / baseline
        // Near baseline = 80, progressive decay outward
        return (80.0 - abs(ratio - 1.0) * 40.0).clampedToHelixScore()
    }

    func loadExplanationKey(for signal: SignalIdentifier, acwr: Double, score: Double) -> String {
        if signal == .acuteChronicRatio {
            if acwr > policy.acwrScoring.cautionCeiling { return "acwr.very_high" }
            if acwr > policy.acwrScoring.optimalHigh    { return "acwr.high" }
            if acwr < policy.acwrScoring.undertrainingCeiling { return "acwr.low" }
            return "acwr.optimal"
        }
        return signal.explanationKey
    }

    /// Strand headline key only (`strand_load.*`) — resolve with `HelixExplanationEngine.explanation(fromKey:)` at the call site. ACWR signal cards still use `acwr.*` via `loadExplanationKey`.
    func primaryLoadExplanationKey(acwr: Double) -> String {
        if acwr > policy.acwrScoring.cautionCeiling { return "strand_load.very_high" }
        if acwr > policy.acwrScoring.optimalHigh { return "strand_load.high" }
        if acwr < policy.acwrScoring.undertrainingCeiling { return "strand_load.low" }
        return "strand_load.optimal"
    }

    /// Returns one ACWR value per day for baseline seeding (historical series).
    func dailyACWRReadings(raw: LoadRawData, ageContext: LoadCalculationContext) -> [(value: Double, date: Date)] {
        let dailyTSS = computeDailyTSS(
            workouts:   raw.workouts,
            hrSamples:  raw.heartRateSamples,
            ageContext: ageContext,
            energyKcal: raw.activeEnergyKcal
        )
        let ac = policy.acuteChronic
        var result: [(value: Double, date: Date)] = []
        for entry in dailyTSS {
            let acute   = ewmaLoadAsOf(dailyTSS: dailyTSS, asOf: entry.date, windowDays: ac.acuteWindowDays,   decay: ac.acuteDecay)
            let chronic = ewmaLoadAsOf(dailyTSS: dailyTSS, asOf: entry.date, windowDays: ac.chronicWindowDays, decay: ac.chronicDecay)
            let acwr    = chronic > 0 ? acute / chronic : 1.0
            result.append((acwr, entry.date))
        }
        return result.sorted { $0.1 < $1.1 }
    }
}
