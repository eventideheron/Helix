// Providers/HealthKitProviders.swift
// ChatGPT audit item #5: "Split HealthKitManager into focused provider components."
//
// The monolithic HealthKitManager was responsible for permissions, sleep parsing,
// load queries, recovery queries, history queries, and all unit conversions.
// Split into:
//   HealthKitAuthorizationManager  — permissions only
//   SleepDataProvider              — sleep session + staging + consistency
//   RecoveryDataProvider           — HRV, resting HR, overnight HR dip, SpO2, RR
//   LoadDataProvider               — workouts, HR during workouts, energy, steps
//   HistoryDataProvider            — 90-day signal history for baseline computation
//
// Each provider is independently testable and independently mockable.
// HelixViewModel composes them; nothing calls HealthKitManager directly.

import HealthKit
import Foundation

// MARK: — Authorization

class HealthKitAuthorizationManager {

    let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    static let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN, .restingHeartRate, .heartRate,
            .respiratoryRate, .oxygenSaturation, .appleSleepingWristTemperature,
            .activeEnergyBurned, .stepCount, .vo2Max
        ]
        quantityIdentifiers.compactMap {
            HKObjectType.quantityType(forIdentifier: $0)
        }.forEach { types.insert($0) }

        if let sleepType  = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleepType) }
        if let dobType    = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dobType) }
        types.insert(HKObjectType.workoutType())
        return types
    }()

    func requestPermissions() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func fetchUserAge() -> LoadCalculationContext {
        do {
            let components = try store.dateOfBirthComponents()
            guard let dob = components.date else { return .fallback }
            let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year
            return LoadCalculationContext(userAge: Double(age ?? 30), ageIsEstimated: age == nil)
        } catch {
            return .fallback
        }
    }
}

// MARK: — Sleep Data Provider

class SleepDataProvider {

    let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    func fetchTodayData() async throws -> SleepRawData {
        let now   = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: now)!
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let todayRaw = try await fetchCategorySamples(type: sleepType, start: start, end: now)
        var todaySamples = isolatePrimarySession(from: todayRaw)
        let overflowGapSeconds: TimeInterval = 60 * 60
        if sleepSamplesDurationHours(todaySamples) > 14.0 {
            #if DEBUG
            print("[HELIX DEBUG] fetchTodayData: overflow (>14h isolated duration) — re-clustering with 1h gap, most-recent cluster")
            #endif
            todaySamples = reclusterSleepSamplesTakingMostRecent(todaySamples, gapSeconds: overflowGapSeconds)
        }
        #if DEBUG
        print("[HELIX DEBUG] fetchTodayData: allSamples=\(todayRaw.count) → primarySession=\(todaySamples.count)")
        #endif

        // 7-night consistency window — isolate one primary session per night before bedtime pairs
        let sevenNightStart = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let historicRaw = try await fetchCategorySamples(type: sleepType, start: sevenNightStart, end: now)
        let historicIsolated = isolateSessionsPerNight(from: historicRaw)
        let (bedtimes, wakeTimes) = extractBedtimeWakePairs(from: historicIsolated)

        let minSleepHR      = try await fetchMinHeartRateDuringSleep(sleepSamples: todaySamples)
        let wristTemp       = try await fetchMostRecentQuantity(type: .appleSleepingWristTemperature, withinHours: 12, unit: .degreeCelsius())
        let overnightRR     = try await fetchOvernightAverage(type: .respiratoryRate, sleepSamples: todaySamples, unit: HKUnit.count().unitDivided(by: .minute()))

        return parse(
            samples: todaySamples,
            bedtimes: bedtimes,
            wakeTimes: wakeTimes,
            wristTempDelta: wristTemp,
            overnightRR: overnightRR,
            minSleepHR: minSleepHR
        )
    }

    /// Matches `parse(samples:...)` total duration logic for overflow guard only.
    private func sleepSamplesDurationHours(_ samples: [HKCategorySample]) -> Double {
        var stageTot = 0.0, inBedTot = 0.0
        for s in samples {
            let h = s.endDate.timeIntervalSince(s.startDate) / 3600.0
            switch s.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                 HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                 HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                stageTot += h
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                inBedTot += h
            default:
                break
            }
        }
        return stageTot > 0 ? stageTot : inBedTot
    }

    /// Post–session-isolation guard: tighter gap clustering; mirrors staged-sleep preference + most-recent end from Plan G.
    private func reclusterSleepSamplesTakingMostRecent(_ samples: [HKCategorySample], gapSeconds: TimeInterval) -> [HKCategorySample] {
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
        func hasStagedSleep(_ c: [HKCategorySample]) -> Bool {
            c.contains { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue }
        }
        let preferred = clusters.filter(hasStagedSleep)
        let pool = preferred.isEmpty ? clusters : preferred
        let maxEnd: ([HKCategorySample]) -> Date = { $0.map(\.endDate).max() ?? .distantPast }
        return pool.max(by: { maxEnd($0) < maxEnd($1) }) ?? []
    }
}

// MARK: — Recovery Data Provider

class RecoveryDataProvider {

    let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    func fetchTodayData(minSleepHR: Double?, overnightRR: Double?, hrvMorningWindowStartHour: Int, hrvMorningWindowEndHour: Int) async throws -> RecoveryRawData {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let ms  = HKUnit.secondUnit(with: .milli)

        let resolvedHRV = try await fetchMorningWindowHRV(startHour: hrvMorningWindowStartHour, endHour: hrvMorningWindowEndHour, unit: ms)
        #if DEBUG
        print("[HELIX DEBUG] morningHRV = \(String(describing: resolvedHRV))")
        #endif
        async let rhr     = fetchMostRecent(type: .restingHeartRate,          withinHours: 12, unit: bpm)
        async let spo2    = fetchSpO2RollingAverage(nights: 7)

        return RecoveryRawData(
            morningHRV:        resolvedHRV,
            restingHR:         try await rhr,
            minSleepHR:        minSleepHR,     // Provided by SleepDataProvider
            overnightRR:       overnightRR,     // Provided by SleepDataProvider
            spo2Rolling7Night: try await spo2
        )
    }
}

// MARK: — Load Data Provider

class LoadDataProvider {

    let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    func fetchTodayData() async throws -> LoadRawData {
        let now   = Date()
        // 28 days to cover chronic ACWR window
        let start = Calendar.current.date(byAdding: .day, value: -28, to: now)!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: now)
        let bpm   = HKUnit.count().unitDivided(by: .minute())

        async let workouts = fetchWorkouts(predicate: pred)
        async let energy   = fetchStatSum(type: .activeEnergyBurned, unit: .kilocalorie(), predicate: pred)
        async let steps    = fetchStatSum(type: .stepCount, unit: .count(), predicate: pred)

        let resolvedWorkouts = try await workouts
        let hrSamples = try await fetchHRDuringWorkouts(resolvedWorkouts)

        let workoutProxies = resolvedWorkouts.map { w in
            HKWorkoutProxy(
                startDate: w.startDate,
                endDate: w.endDate,
                duration: w.duration,
                activityType: w.workoutActivityType.rawValue
            )
        }
        let hrProxies = hrSamples.map { s in
            HKSampleProxy(
                value: s.quantity.doubleValue(for: bpm),
                startDate: s.startDate,
                endDate: s.endDate
            )
        }

        return LoadRawData(
            workouts:          workoutProxies,
            heartRateSamples:  hrProxies,
            activeEnergyKcal:  try await energy,
            stepCount:         try await steps,
            dailyTSSHistory:   []   // Computed by HelixLoadCalculator with age context
        )
    }
}

// MARK: — History Data Provider

class HistoryDataProvider {

    let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    /// - Parameter historicalHrDipMinSamples: Policy `strand_recovery.overnight_hr_dip.minimum_historical_hr_samples` (historical min-HR path only).
    func fetchHistoricalData(days: Int, historicalHrDipMinSamples: Int) async throws -> HistoricalRawData {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let bpm   = HKUnit.count().unitDivided(by: .minute())
        let ms    = HKUnit.secondUnit(with: .milli)

        async let hrv    = fetchQuantityHistory(type: .heartRateVariabilitySDNN, unit: ms, from: start)
        async let rhr    = fetchQuantityHistory(type: .restingHeartRate, unit: bpm, from: start)
        async let rr     = fetchQuantityHistory(type: .respiratoryRate, unit: bpm, from: start)
        async let temp   = fetchQuantityHistory(type: .appleSleepingWristTemperature, unit: .degreeCelsius(), from: start)
        async let energy = fetchQuantityHistory(type: .activeEnergyBurned, unit: .kilocalorie(), from: start)
        async let sleep  = fetchSleepHistory(days: days, historicalMinHrSamples: historicalHrDipMinSamples)

        let (duration, deep, rem, minHRs, consistencyReadings, awakeningsPerHourReadings) = try await sleep
        let rhrSeries = try await rhr
        let tempSeries = try await temp

        // Map resting HR readings by day for dip computation
        let calendar = Calendar.current
        var rhrByDay: [Date: Double] = [:]
        for (value, date) in rhrSeries {
            let day = calendar.startOfDay(for: date)
            rhrByDay[day] = value
        }

        // Compute nightly HR dips: restingHR (wake-day aligned) - minSleepHR (night)
        let computedDips: [(value: Double, date: Date)] = minHRs.compactMap { (minHR, date) in
            let day = calendar.startOfDay(for: date)
            guard let rhrValue = resolveRestingHRForSleepNight(wakeDay: date, rhrByDay: rhrByDay, calendar: calendar) else { return nil }
            let dip = rhrValue - minHR
            return dip >= 0 ? (value: dip, date: day) : nil
        }
        #if DEBUG
        print("[HELIX DEBUG] boundary-2 fetchHistoricalData handoff counts: consistency=\(consistencyReadings.count) awakenings=\(awakeningsPerHourReadings.count) computedDips=\(computedDips.count)")
        if !minHRs.isEmpty && computedDips.isEmpty {
            let firstMin = minHRs.first.map { "\($0.value) @ \($0.date)" } ?? "<none>"
            let rhrDays = rhrByDay.keys.count
            print("[HELIX DEBUG][WARN] boundary-2 computedDips empty despite minHRs=\(minHRs.count). firstMinHR=\(firstMin), rhrDays=\(rhrDays) (check day-alignment/fallback path)")
        }
        #endif

        let energyRaw = try await energy
        let energyReadings = aggregateQuantityHistoryByDay(energyRaw)
        #if DEBUG
        print("[HELIX DEBUG] sleepHistory counts — duration: \(duration.count), deep: \(deep.count), rem: \(rem.count), dips(minHR raw): \(minHRs.count), consistency: \(consistencyReadings.count), awakenings: \(awakeningsPerHourReadings.count)")
        print("[HELIX DEBUG] computed nightly HR dips (RHR - minHR): \(computedDips.count)")
        let sample = Array(duration.prefix(3)).map { "\($0.value)h @ \($0.date)" }
        print("[HELIX DEBUG] duration sample (prefix 3): \(sample)")
        print("[HELIX DEBUG] historical wrist temperature readings: \(tempSeries.count)")
        #endif

        return HistoricalRawData(
            hrvReadings:       try await hrv,
            rhrReadings:       rhrSeries,
            sleepReadings:     duration,
            deepSleepReadings: deep,
            remSleepReadings:  rem,
            rrReadings:        try await rr,
            tempReadings:      tempSeries,
            energyReadings:    energyReadings,
            dipReadings:       computedDips,
            consistencyReadings:       consistencyReadings,
            awakeningsPerHourReadings: awakeningsPerHourReadings,
            acwrReadings:              []
        )
    }
}

extension HistoryDataProvider {

    /// RHR for a sleep night’s wake calendar day, with small-day fallback when HealthKit posts resting HR on adjacent days.
    fileprivate func resolveRestingHRForSleepNight(wakeDay: Date, rhrByDay: [Date: Double], calendar: Calendar) -> Double? {
        let day0 = calendar.startOfDay(for: wakeDay)
        if let v = rhrByDay[day0] { return v }
        for offset in [-1, 1, -2, 2] {
            guard let adjacent = calendar.date(byAdding: .day, value: offset, to: day0) else { continue }
            let key = calendar.startOfDay(for: adjacent)
            if let v = rhrByDay[key] { return v }
        }
        return nil
    }
}

// MARK: — Shared error type

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case dataUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:           return "HealthKit is not available on this device."
        case .dataUnavailable(let s): return "No data available for \(s)."
        }
    }
}

