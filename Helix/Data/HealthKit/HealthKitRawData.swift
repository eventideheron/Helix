// Data/HealthKit/HealthKitRawData.swift
// Raw data container types that flow from HealthKit providers into the normalisation engine.
// These are data-transfer objects — they carry unvalidated, unscored HealthKit values.
// They are intentionally kept in Data/ rather than Domain/ because they are shaped
// by HealthKit's API, not by Helix's domain concepts.
//
// Flow: HealthKitProviders → HelixRawData → SignalNormalizationEngine → ValidatedSignal
//       → Strand calculators → StrandScore → HelixIndexCalculator → HelixIndex
//
// Note: HelixDomainModels.swift previously contained these structs alongside domain types.
// They now live here per ChatGPT's recommendation to separate data-layer shapes from
// domain value types. If you see duplicate definitions, this file is authoritative.

import Foundation

// MARK: — Top-level container

struct HelixRawData {
    let sleep:     SleepRawData
    let load:      LoadRawData
    let recovery:  RecoveryRawData
    let history:   HistoricalRawData
    let fetchedAt: Date
}

// MARK: — Sleep

struct SleepRawData {
    let totalDurationHours:       Double
    let deepSleepPercent:         Double   // 0–1 fraction
    let remSleepPercent:          Double   // 0–1 fraction
    let awakeningsPerHour:        Double
    let bedtimes:                 [Date]   // Last N nights per consistency window
    let wakeTimes:                [Date]   // Last N nights per consistency window
    /// HealthKit `appleSleepingWristTemperature` sample value (absolute °C), when available.
    let wristTempAbsoluteCelsius: Double?
    /// Δ°C vs personal baseline; set by ViewModel after `buildBaselines` when baseline is seeded (absolute mean > 34 °C).
    let wristTempDeltaCelsius:    Double?
    let overnightRespiratoryRate: Double?  // nil if < minimum overnight readings
    let minSleepHR:               Double?  // nil if < 60 overnight HR samples

    /// Copy with injected wrist delta (provider leaves delta nil until baseline is known).
    func withWristTempDelta(_ delta: Double?) -> SleepRawData {
        SleepRawData(
            totalDurationHours: totalDurationHours,
            deepSleepPercent: deepSleepPercent,
            remSleepPercent: remSleepPercent,
            awakeningsPerHour: awakeningsPerHour,
            bedtimes: bedtimes,
            wakeTimes: wakeTimes,
            wristTempAbsoluteCelsius: wristTempAbsoluteCelsius,
            wristTempDeltaCelsius: delta,
            overnightRespiratoryRate: overnightRespiratoryRate,
            minSleepHR: minSleepHR
        )
    }
}

// MARK: — Load

struct LoadRawData {
    let workouts:         [HKWorkoutProxy]
    let heartRateSamples: [HKSampleProxy]
    let activeEnergyKcal: Double
    let stepCount:        Double
    let dailyTSSHistory:  [(tss: Double, date: Date)]
}

// MARK: — Recovery

struct RecoveryRawData {
    let morningHRV:        Double?  // SDNN in ms, within 2 hrs of waking
    let restingHR:         Double?  // bpm, morning resting state
    let minSleepHR:        Double?  // bpm — minimum during sleep window
    let overnightRR:       Double?  // brpm — overnight respiratory rate
    let spo2Rolling7Night: Double?  // percentage (0–100) — already converted from fraction
}

// MARK: — Historical (for baseline computation)

struct HistoricalRawData {
    let hrvReadings:       [(value: Double, date: Date)]
    let rhrReadings:       [(value: Double, date: Date)]
    let sleepReadings:     [(value: Double, date: Date)]  // duration in hours
    let deepSleepReadings: [(value: Double, date: Date)]  // fraction 0–1
    let remSleepReadings:  [(value: Double, date: Date)]  // fraction 0–1
    let rrReadings:        [(value: Double, date: Date)]  // brpm
    let tempReadings:      [(value: Double, date: Date)]  // delta °C from personal baseline
    let energyReadings:    [(value: Double, date: Date)]  // kcal
    let dipReadings:       [(value: Double, date: Date)]  // bpm dip
    /// Bedtime SD + wake SD (minutes, circular clock), 7-night rolling series; **only nights with ≥4h staged sleep,
    /// bed+wake span ≥1h, and non-nil bed/wake** contribute — same units as `HelixSleepCalculator` / `HelixSignal(.sleepConsistency)`.
    /// Duration / deep / REM / dip / awakenings series may include other nights.
    let consistencyReadings:       [(value: Double, date: Date)]
    let awakeningsPerHourReadings:  [(value: Double, date: Date)]
    let acwrReadings:               [(value: Double, date: Date)]
}

// MARK: — HealthKit proxy types
// Thin value types so Domain/ and Engine/ layers have no direct HealthKit dependency.
// Provider classes populate these; calculators consume them.

struct HKWorkoutProxy {
    let startDate:    Date
    let endDate:      Date
    let duration:     TimeInterval      // seconds
    let activityType: UInt              // HKWorkoutActivityType.rawValue
}

struct HKSampleProxy {
    let value:     Double
    let startDate: Date
    let endDate:   Date
}
