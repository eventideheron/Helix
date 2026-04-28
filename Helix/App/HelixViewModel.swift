// App/HelixViewModel.swift
// v1.2: Full architectural revision addressing ChatGPT Tier 1 issues.
//
// Changes from original:
//   - No placeholder strand scores. If Sleep or Load calculators are not built,
//     the app transitions to .partialScore or .suppressedScore, not a fake composite.
//   - HelixAppState drives all UI decisions. isLoading + optional index + error removed.
//   - Confidence evaluated through policy, not ad hoc logic in the view model.
//   - SignalNormalizationEngine sits between providers and calculators.
//   - Policy version validated at startup.
//   - Providers replace monolithic HealthKitManager.
//   - Baseline snapshots persisted after each calculation (enables O(1) EWMA path).

import SwiftUI
import SwiftData
import Combine

@MainActor
class HelixViewModel: ObservableObject {

    @Published var appState: HelixAppState = .idle
    @Published var crossStrandInsight: CrossStrandInsight? = nil
    /// Set after a successful daily pipeline run (post-persist). `nil` until first evaluation.
    @Published var historyResult: HistoryResult? = nil
    /// Snapshot of persisted daily records for `HistoryView` (updated with `historyResult`).
    @Published private(set) var allDailyRecords: [HelixDailyRecord] = []

    // MARK: — Dependencies

    private let policyBundle:        HelixPolicyBundle
    private let authManager:         HealthKitAuthorizationManager
    private let sleepProvider:       SleepDataProvider
    private let recoveryProvider:    RecoveryDataProvider
    private let loadProvider:        LoadDataProvider
    private let historyProvider:     HistoryDataProvider
    private let baselineEngine:      HelixBaselineEngine
    private let confidenceEngine:    HelixConfidenceEngine
    private let explanationEngine:   HelixExplanationEngine
    private let normalizationEngine: SignalNormalizationEngine
    private let sleepCalc:           HelixSleepCalculator
    private let loadCalc:            HelixLoadCalculator
    private let recoveryCalc:        HelixRecoveryCalculator
    private let indexCalc:           HelixIndexCalculator
    private let crossStrandEngine:   HelixCrossStrandEngine
    private let historyEngine:       HelixHistoryEngine

    private var modelContext: ModelContext?

    // MARK: — Init
    // Policy files are the absolute requirement. App cannot run without them.

    init() {
        let bundle: HelixPolicyBundle
        do {
            bundle = try HelixPolicyLoader.loadAll()
        } catch {
            fatalError("Policy load failed: \(error.localizedDescription)")
        }

        self.policyBundle         = bundle
        self.authManager          = HealthKitAuthorizationManager()
        self.sleepProvider        = SleepDataProvider()
        self.recoveryProvider     = RecoveryDataProvider()
        self.loadProvider         = LoadDataProvider()
        self.historyProvider      = HistoryDataProvider()
        self.baselineEngine       = HelixBaselineEngine(policy: bundle.core)
        self.confidenceEngine     = HelixConfidenceEngine(policy: bundle.confidence)
        self.explanationEngine    = HelixExplanationEngine(policy: bundle.explanation)
        self.normalizationEngine  = SignalNormalizationEngine(
            policy: bundle.core,
            confidencePolicy: bundle.confidence
        )
        self.historyEngine        = HelixHistoryEngine(policy: bundle.history)
        self.sleepCalc    = HelixSleepCalculator(
            policy: bundle.core.strandSleep,
            confidenceEngine: confidenceEngine,
            explanationEngine: explanationEngine
        )
        self.loadCalc     = HelixLoadCalculator(
            policy: bundle.core.strandLoad,
            confidenceEngine: confidenceEngine,
            explanationEngine: explanationEngine,
            hrElevationBands: bundle.explanation.signalThresholds.hrElevation
        )
        self.recoveryCalc = HelixRecoveryCalculator(
            policy: bundle.core.strandRecovery,
            confidenceEngine: confidenceEngine,
            explanationEngine: explanationEngine,
            restingHrExplanationThresholds: bundle.explanation.signalThresholds.restingHr,
            hrvExplanationThresholds: bundle.explanation.signalThresholds.hrv
        )
        self.indexCalc = HelixIndexCalculator(policy: bundle.core.helixIndex)
        self.crossStrandEngine = HelixCrossStrandEngine(policy: bundle.crossStrand)

        // Validate policy version before any calculation begins
        baselineEngine.validatePolicyVersion()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// Exposes the explanation engine so views can resolve raw keys to human-readable strings.
    func getExplanationEngine() -> HelixExplanationEngine {
        explanationEngine
    }

    // MARK: — Primary load flow

    /// Loads HealthKit permission (if needed) and computes today’s Helix state.
    /// - Parameter skipIfAlreadyLoaded: When `true`, skips a duplicate fetch if the view model already holds a post-permission result (e.g. user just finished onboarding in-session).
    func loadToday(skipIfAlreadyLoaded: Bool = false) async {
        if skipIfAlreadyLoaded, shouldSkipDuplicateLoadAfterOnboarding() {
            return
        }

        appState = .requestingPermissions

        do {
            try await authManager.requestPermissions()
        } catch HealthKitError.notAvailable {
            appState = .healthKitUnavailable
            return
        } catch {
            appState = .permissionsDenied
            return
        }

        await loadTodayAfterPermissionsGranted()
    }

    /// Computes Helix state assuming HealthKit read access has already been requested (same pipeline as `loadToday` after the permission sheet).
    func loadTodayAfterPermissionsGranted() async {
        appState = .fetchingData

        do {
            // 1. Fetch raw data from all providers concurrently
            let ageContext    = authManager.fetchUserAge()
            async let sleepRaw    = sleepProvider.fetchTodayData()
            async let loadRaw     = loadProvider.fetchTodayData()
            let historicalHrDipMin = policyBundle.core.strandRecovery.overnightHrDip.minimumHistoricalHrSamples ?? 10
            async let historyRaw  = historyProvider.fetchHistoricalData(days: 90, historicalHrDipMinSamples: historicalHrDipMin)

            let sleepData   = try await sleepRaw
            let loadData    = try await loadRaw
            let historyData = try await historyRaw

            #if DEBUG
            print("[HELIX DEBUG] ---- Today Sleep Raw ----")
            print(String(format: "durationHours=%.2f, deep%%=%.1f, rem%%=%.1f, awakenings/hr=%.2f", sleepData.totalDurationHours, sleepData.deepSleepPercent * 100, sleepData.remSleepPercent * 100, sleepData.awakeningsPerHour))
            print("[HELIX DEBUG] bedtimes.count=\(sleepData.bedtimes.count), wakeTimes.count=\(sleepData.wakeTimes.count)")
            if let a = sleepData.wristTempAbsoluteCelsius { print(String(format: "[HELIX DEBUG] wristTempAbsolute=%.3f °C", a)) } else { print("[HELIX DEBUG] wristTempAbsolute=nil") }
            if let rr = sleepData.overnightRespiratoryRate { print(String(format: "[HELIX DEBUG] overnightRR=%.2f brpm", rr)) } else { print("[HELIX DEBUG] overnightRR=nil") }
            if let minHR = sleepData.minSleepHR { print(String(format: "[HELIX DEBUG] minSleepHR=%.0f bpm", minHR)) } else { print("[HELIX DEBUG] minSleepHR=nil") }
            print("[HELIX DEBUG] --------------------------")
            #endif

            // ACWR historical series for baseline (workout + HR over window, then daily ACWR)
            let (workoutsHistory, hrHistory) = try await loadProvider.fetchWorkoutAndHRHistory(days: 90)
            let loadRawForBaseline = LoadRawData(
                workouts: workoutsHistory,
                heartRateSamples: hrHistory,
                activeEnergyKcal: 0,
                stepCount: 0,
                dailyTSSHistory: []
            )
            let acwrReadings = loadCalc.dailyACWRReadings(raw: loadRawForBaseline, ageContext: ageContext)
            let historyWithACWR = HistoricalRawData(
                hrvReadings: historyData.hrvReadings,
                rhrReadings: historyData.rhrReadings,
                sleepReadings: historyData.sleepReadings,
                deepSleepReadings: historyData.deepSleepReadings,
                remSleepReadings: historyData.remSleepReadings,
                rrReadings: historyData.rrReadings,
                tempReadings: historyData.tempReadings,
                energyReadings: historyData.energyReadings,
                dipReadings: historyData.dipReadings,
                consistencyReadings: historyData.consistencyReadings,
                awakeningsPerHourReadings: historyData.awakeningsPerHourReadings,
                acwrReadings: acwrReadings
            )

            // Recovery provider reuses sleep-derived values to avoid double-querying
            let hrvMorningStart = policyBundle.core.strandRecovery.hrv.morningWindowStartHour ?? 4
            let hrvMorningEnd   = policyBundle.core.strandRecovery.hrv.morningWindowEndHour   ?? 10
            let recoveryData = try await recoveryProvider.fetchTodayData(
                minSleepHR:                sleepData.minSleepHR,
                overnightRR:               sleepData.overnightRespiratoryRate,
                hrvMorningWindowStartHour: hrvMorningStart,
                hrvMorningWindowEndHour:   hrvMorningEnd
            )

            // 2. Build baselines (fast path if SwiftData snapshots available)
            let cachedSnapshots = loadBaselineSnapshots()
            let baselines = baselineEngine.buildBaselines(
                from: historyWithACWR,
                cachedSnapshots: cachedSnapshots
            )
            let dataPointCount = historyData.hrvReadings.count

            #if DEBUG
            let windowDays = policyBundle.core.baseline.windowDays
            func logBaseline(_ id: SignalIdentifier) {
                if let b = baselines[id] {
                    let val = String(format: "%.3f", b.value)
                    print("[HELIX DEBUG] baseline \(id.rawValue) = \(val) (count=\(b.dataPointCount), windowDays=\(windowDays))")
                } else {
                    print("[HELIX DEBUG] baseline \(id.rawValue) = <nil>")
                }
            }
            print("[HELIX DEBUG] ---- Baseline values after buildBaselines ----")
            // Sleep-related baselines
            logBaseline(.sleepDuration)
            logBaseline(.deepSleepPercent)
            logBaseline(.remSleepPercent)
            logBaseline(.sleepConsistency)
            logBaseline(.awakeningsPerHour)
            logBaseline(.wristTemperature)
            logBaseline(.overnightRespiratory)
            logBaseline(.overnightHRDip)
            // Load/Recovery references (to confirm no regressions)
            logBaseline(.hrv)
            logBaseline(.restingHR)
            logBaseline(.acuteChronicRatio)
            logBaseline(.trainingVolume)
            print("[HELIX DEBUG] ----------------------------------------------")
            #endif

            // 3. Check baseline activation threshold
            let minDays = policyBundle.core.baseline.minimumDaysToActivate
            if dataPointCount < minDays {
                let daysRemaining = minDays - dataPointCount
                appState = .learningBaseline(daysRemaining: daysRemaining)
                return
            }

            // 4. Signal normalisation and validation
            let overnightHRDipValue: Double
            if let minSleep = recoveryData.minSleepHR, let baselineResting = baselines[.restingHR]?.value {
                overnightHRDipValue = baselineResting - minSleep
            } else {
                overnightHRDipValue = 0
            }
            let rawRecoverySignals: [SignalIdentifier: Double] = [
                .hrv:               recoveryData.morningHRV ?? 0,
                .restingHR:         recoveryData.restingHR ?? 0,
                .overnightHRDip:    overnightHRDipValue,
                .respiratoryRecovery: recoveryData.overnightRR ?? 0,
                .spo2:              recoveryData.spo2Rolling7Night ?? 0
            ].filter { $0.value > 0 }   // Remove unprovided signals before validation

            let validatedRecovery = normalizationEngine.validateAll(
                rawSignals: rawRecoverySignals,
                baselines: baselines
            )

            // 5. Calculate Recovery strand
            let (recoveryScore, recoveryMissing, recoveryContributions, recoverySignals, recoveryPrimaryExplanation) = recoveryCalc.calculate(
                todayHRV:          validatedRecovery.usableValue(for: .hrv),
                todayRHR:          validatedRecovery.usableValue(for: .restingHR),
                minSleepHR:        recoveryData.minSleepHR,
                overnightRR:       validatedRecovery.usableValue(for: .respiratoryRecovery),
                spo2Rolling7Night: validatedRecovery.usableValue(for: .spo2),
                baselines:         baselines
            )

            let recoveryConfidenceResult = confidenceEngine.evaluate(
                presentSignals: Array(validatedRecovery.filter { $0.value.isUsable }.keys),
                validSignals:   Array(validatedRecovery.filter { $0.value.isUsable }.keys),
                allExpectedSignals: [.hrv, .restingHR, .overnightHRDip, .respiratoryRecovery],
                watchOfflineHours: 0   // TODO: calculate from watch last-seen timestamp
            )

            // Keep template keys on contributions (same as sleep/load). Resolve copy at display via `HelixExplanationEngine`.
            let recoveryStrand = StrandScore(
                strand: .recovery,
                score: recoveryScore,
                componentSignals: recoverySignals,
                missingSignals: recoveryMissing,
                confidence: recoveryConfidenceResult.level,
                contributionBreakdown: recoveryContributions,
                primaryExplanation: recoveryPrimaryExplanation,
                calculatedAt: Date()
            )

            // 6. Sleep and Load strands (real calculators)
            // Wrist temp: HK is absolute °C; inject Δ vs personal EWMA when baseline looks like body temp (> 34 °C).
            let sleepInput: SleepRawData
            if let absWrist = sleepData.wristTempAbsoluteCelsius,
               let wtBaseline = baselines[.wristTemperature]?.value,
               wtBaseline > 34 {
                sleepInput = sleepData.withWristTempDelta(absWrist - wtBaseline)
                #if DEBUG
                print(String(format: "[HELIX DEBUG] wristTemp delta injected: absolute=%.3f baseline=%.3f Δ=%.3f", absWrist, wtBaseline, absWrist - wtBaseline))
                #endif
            } else {
                sleepInput = sleepData
            }

            let (_, sleepStrand) = sleepCalc.calculate(raw: sleepInput, baselines: baselines)
            let (_, loadStrand)  = loadCalc.calculate(
                raw:        loadData,
                baselines:  baselines,
                ageContext: ageContext
            )

            // 7. Derive strand availability from actual calculation state
            let allStrandsAvailable = sleepStrand.missingSignals.isEmpty
                && loadStrand.missingSignals.isEmpty
                && recoveryStrand.missingSignals.isEmpty

            // 8. Full index from three real strands
            let index = indexCalc.calculate(
                sleep:   sleepStrand,
                load:    loadStrand,
                recovery: recoveryStrand
            )

            if allStrandsAvailable {
                appState = .fullScore(index)
            } else {
                let missingSignals = Array(Set(
                    sleepStrand.missingSignals
                    + loadStrand.missingSignals
                    + recoveryStrand.missingSignals
                ))
                appState = .partialScore(index, missingSignals: missingSignals)
            }

            // Gate D: cross-strand insight — additive only, never modifies scores
            crossStrandInsight = crossStrandEngine.evaluate(
                index: index,
                baselineDays: dataPointCount
            )
            #if DEBUG
            if let insight = crossStrandInsight {
                print("[HELIX DEBUG] crossStrandInsight: pattern=\(insight.patternID)")
            } else {
                print("[HELIX DEBUG] crossStrandInsight: nil (no pattern matched or suppressed)")
            }
            #endif

            persistAndUpdateBaselines(
                baselines: baselines,
                index: index,
                appState: appState,
                dataPointCount: dataPointCount
            )

            if allDailyRecords.count < 90 {
                let existingDates = Set(loadAllDailyRecords().map {
                    Calendar.current.startOfDay(for: $0.date)
                })
                backfillHistoricalRecords(
                    history: historyWithACWR,
                    baselines: baselines,
                    existingDates: existingDates
                )
            }

            let records = loadAllDailyRecords()
            allDailyRecords = records
            let appleHealthDays = records.first?.dataPointCountAtCalculation ?? dataPointCount
            historyResult = historyEngine.evaluate(
                today: index,
                allRecords: records,
                appleHealthDays: appleHealthDays
            )

        } catch {
            appState = .error(error.localizedDescription)
        }
    }

    /// After onboarding, avoid a second full HealthKit fetch when the pipeline already ran for screens 8–10.
    private func shouldSkipDuplicateLoadAfterOnboarding() -> Bool {
        switch appState {
        case .fullScore, .partialScore, .developingBaseline, .learningBaseline, .suppressedScore:
            return true
        case .error, .permissionsDenied, .healthKitUnavailable:
            return false
        case .idle, .requestingPermissions, .fetchingData:
            return false
        }
    }

    // MARK: — SwiftData: all daily records (history UI)

    private func loadAllDailyRecords() -> [HelixDailyRecord] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<HelixDailyRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: — SwiftData: baseline snapshot load

    private func loadBaselineSnapshots() -> [SignalIdentifier: HelixBaselineSnapshot] {
        guard let context = modelContext else { return [:] }
        let descriptor = FetchDescriptor<HelixBaselineSnapshot>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []

        // One snapshot per signal — take the most recent
        var result = [SignalIdentifier: HelixBaselineSnapshot]()
        for snapshot in all {
            guard let signal = snapshot.signal, result[signal] == nil else { continue }
            result[signal] = snapshot
        }
        return result
    }

    // MARK: — SwiftData: persist results

    private func persistAndUpdateBaselines(
        baselines: [SignalIdentifier: PersonalBaseline],
        index: HelixIndex?,
        appState: HelixAppState,
        dataPointCount: Int
    ) {
        guard let context = modelContext else { return }

        // ── Upsert HelixBaselineSnapshot (one per signal per calendar day) ────────
        // Each snapshot uses its own date to derive the day-range predicate.
        // This avoids any mismatch between ambient wall clock and snapshot timestamp.
        let snapshots = baselineEngine.snapshotsForPersistence(from: baselines)
        for snapshot in snapshots {
            let signalKey = snapshot.signalRaw
            let snapStart = Calendar.current.startOfDay(for: snapshot.date)
            let snapEnd = Calendar.current.date(byAdding: .day, value: 1, to: snapStart)!
            let descriptor = FetchDescriptor<HelixBaselineSnapshot>(
                predicate: #Predicate { $0.signalRaw == signalKey && $0.date >= snapStart && $0.date < snapEnd },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            do {
                if let existing = try context.fetch(descriptor).first {
                    // Update existing row in place
                    existing.ewmaValue = snapshot.ewmaValue
                    existing.decayRate = snapshot.decayRate
                    existing.dataPointCount = snapshot.dataPointCount
                    existing.stabilityStatusRaw = snapshot.stabilityStatusRaw
                    existing.metricSignatureRaw = snapshot.metricSignatureRaw
                    existing.date = snapshot.date
                } else {
                    context.insert(snapshot)
                }
            } catch {
                print("[Helix] persistAndUpdateBaselines: snapshot fetch failed for signal \(signalKey): \(error.localizedDescription) — inserting new row")
                context.insert(snapshot)
            }
        }

        // ── Upsert HelixDailyRecord (one per calendar day) ───────────────────────
        // Day-range is derived from index.date — the record's own timestamp —
        // not ambient Date(), to avoid boundary-condition mismatches.
        if let index = index {
            let dayStart = Calendar.current.startOfDay(for: index.date)
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
            let descriptor = FetchDescriptor<HelixDailyRecord>(
                predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            do {
                if let existing = try context.fetch(descriptor).first {
                    // ── Score-owned fields: always refreshed ──────────────────────
                    existing.date = index.date
                    existing.helixIndex = index.score
                    existing.postureRaw = index.posture.rawValue
                    existing.confidenceRaw = index.overallConfidence.rawValue
                    existing.balancePenalty = index.balancePenalty
                    existing.recoveryGateApplied = index.recoveryGateApplied
                    existing.recoveryGateLevelRaw = index.recoveryGateLevel?.rawValue
                    existing.sleepScore = index.sleepStrand.score
                    existing.loadScore = index.loadStrand.score
                    existing.recoveryScore = index.recoveryStrand.score
                    existing.sleepConfidenceRaw = index.sleepStrand.confidence.rawValue
                    existing.loadConfidenceRaw = index.loadStrand.confidence.rawValue
                    existing.recoveryConfidenceRaw = index.recoveryStrand.confidence.rawValue
                    existing.sleepBoostApplied = index.interactionTerms.sleepBoostApplied
                    existing.loadCostApplied = index.interactionTerms.loadCostApplied
                    existing.sleepContributionsJSON = HelixDailyRecord.encode(index.sleepStrand.contributionBreakdown)
                    existing.loadContributionsJSON = HelixDailyRecord.encode(index.loadStrand.contributionBreakdown)
                    existing.recoveryContributionsJSON = HelixDailyRecord.encode(index.recoveryStrand.contributionBreakdown)
                    existing.sleepMissingSignalsRaw = index.sleepStrand.missingSignals.map(\.rawValue).joined(separator: ",")
                    existing.loadMissingSignalsRaw = index.loadStrand.missingSignals.map(\.rawValue).joined(separator: ",")
                    existing.recoveryMissingSignalsRaw = index.recoveryStrand.missingSignals.map(\.rawValue).joined(separator: ",")
                    existing.sleepPrimaryExplanation = index.sleepStrand.primaryExplanation
                    existing.loadPrimaryExplanation = index.loadStrand.primaryExplanation
                    existing.recoveryPrimaryExplanation = index.recoveryStrand.primaryExplanation
                    existing.appStateRaw = appState.persistedString
                    existing.dataPointCountAtCalculation = dataPointCount
                    existing.baselineMaturityStageRaw = HelixDailyRecord.maturityStage(for: dataPointCount)

                    // ── History-owned fields: intentionally NOT updated ───────────
                    // isTodayInHistory, historyTriggerRaw, historyMessage are owned
                    // by the history engine, not the score pipeline. Preserving them
                    // here prevents clobbering data established by a separate layer.
                    // (existing.isTodayInHistory    — preserved)
                    // (existing.historyTriggerRaw   — preserved)
                    // (existing.historyMessage      — preserved)

                } else {
                    let record = HelixDailyRecord(from: index, appState: appState, dataPointCount: dataPointCount)
                    context.insert(record)
                }
            } catch {
                print("[Helix] persistAndUpdateBaselines: daily record fetch failed: \(error.localizedDescription) — inserting new row")
                let record = HelixDailyRecord(from: index, appState: appState, dataPointCount: dataPointCount)
                context.insert(record)
            }
        }

        try? context.save()
    }

    // MARK: — Historical backfill from Apple Health 90-day window

    /// Builds HelixDailyRecord entries for historical days present in Apple Health
    /// but not yet in SwiftData. Uses signal readings already fetched in the
    /// current pipeline run — no additional HealthKit queries.
    /// Safe to call multiple times (idempotent — skips existing dates).
    private func backfillHistoricalRecords(
        history: HistoricalRawData,
        baselines: [SignalIdentifier: PersonalBaseline],
        existingDates: Set<Date>
    ) {
        guard let context = modelContext else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Purge stale v1 historical rows so corrected v2 backfill can rewrite those days.
        let staleRecords = loadAllDailyRecords().filter {
            calendar.startOfDay(for: $0.date) < today && $0.appStateRaw == "unknown"
        }
        staleRecords.forEach { context.delete($0) }
        if !staleRecords.isEmpty {
            try? context.save()
        }
        #if DEBUG
        print("[HELIX DEBUG] Backfill purge: deleted \(staleRecords.count) stale 'unknown' records.")
        #endif

        // Dates that still exist after purge should be treated as already satisfied.
        var existingDatesAfterPurge = existingDates
        let purgedDays = Set(staleRecords.map { calendar.startOfDay(for: $0.date) })
        existingDatesAfterPurge.subtract(purgedDays)

        // Group readings by calendar day
        var hrvByDay: [Date: Double] = [:]
        var rhrByDay: [Date: Double] = [:]
        var sleepDurByDay: [Date: Double] = [:]
        var deepByDay: [Date: Double] = [:]
        var remByDay: [Date: Double] = [:]
        var rrByDay: [Date: Double] = [:]
        var awakeningsByDay: [Date: Double] = [:]

        for r in history.hrvReadings { hrvByDay[calendar.startOfDay(for: r.date)] = r.value }
        for r in history.rhrReadings { rhrByDay[calendar.startOfDay(for: r.date)] = r.value }
        for r in history.sleepReadings { sleepDurByDay[calendar.startOfDay(for: r.date)] = r.value }
        for r in history.deepSleepReadings { deepByDay[calendar.startOfDay(for: r.date)] = r.value }
        for r in history.remSleepReadings { remByDay[calendar.startOfDay(for: r.date)] = r.value }
        for r in history.rrReadings { rrByDay[calendar.startOfDay(for: r.date)] = r.value }
        for r in history.awakeningsPerHourReadings { awakeningsByDay[calendar.startOfDay(for: r.date)] = r.value }

        // Collect all days present in Apple Health data
        let allDays = Set(hrvByDay.keys)
            .union(rhrByDay.keys)
            .union(sleepDurByDay.keys)
            .sorted()

        var inserted = 0

        for day in allDays {
            // Skip today — today's record is written by persistAndUpdateBaselines
            guard day < today else { continue }
            // Skip days that already have a record
            guard !existingDatesAfterPurge.contains(day) else { continue }

            let hasSleep = sleepDurByDay[day] != nil
            let hasRecovery = hrvByDay[day] != nil || rhrByDay[day] != nil
            guard hasSleep || hasRecovery else { continue }

            let sleepRaw = SleepRawData(
                totalDurationHours: sleepDurByDay[day] ?? 0,
                deepSleepPercent: deepByDay[day] ?? 0,
                remSleepPercent: remByDay[day] ?? 0,
                awakeningsPerHour: awakeningsByDay[day] ?? (baselines[.awakeningsPerHour]?.value ?? 1.0),
                bedtimes: [],
                wakeTimes: [],
                wristTempAbsoluteCelsius: nil,
                wristTempDeltaCelsius: nil,
                overnightRespiratoryRate: rrByDay[day],
                minSleepHR: nil
            )
            let (_, sleepStrand) = sleepCalc.calculate(raw: sleepRaw, baselines: baselines)
            let sleepScore = hasSleep ? min(sleepStrand.score, 82.0) : 0.0

            #if DEBUG
            if sleepScore > 80 || sleepScore < 20 {
                print("[BACKFILL DIAG] day=\(day) dur=\(sleepDurByDay[day] ?? -1) deep=\(deepByDay[day] ?? -1) rem=\(remByDay[day] ?? -1) awk=\(awakeningsByDay[day] ?? -1) rr=\(rrByDay[day] ?? -1) sleepScore=\(sleepScore)")
            }
            #endif

            let (recoveryScoreValue, _, _, _, _) = recoveryCalc.calculate(
                todayHRV: hrvByDay[day],
                todayRHR: rhrByDay[day],
                minSleepHR: nil,
                overnightRR: rrByDay[day],
                spo2Rolling7Night: nil,
                baselines: baselines
            )
            let recoveryScore = hasRecovery ? recoveryScoreValue : 0.0
            guard sleepScore > 0 || recoveryScore > 0 else { continue }

            // --- Load score — neutral for historical backfill ---
            let loadScore = 50.0

            // --- Helix Index ---
            let helixIndex = (sleepScore * 0.35) + (recoveryScore * 0.35) + (loadScore * 0.30)

            // --- Posture ---
            let posture: String
            switch helixIndex {
            case 75...: posture = "pursue"
            case 50...: posture = "moderate"
            default: posture = "restore"
            }

            let record = HelixDailyRecord()
            record.date = day
            record.helixIndex = helixIndex
            record.postureRaw = posture
            record.confidenceRaw = "low"
            record.sleepScore = sleepScore
            record.loadScore = loadScore
            record.recoveryScore = recoveryScore
            record.sleepConfidenceRaw = hasSleep ? sleepStrand.confidence.rawValue : "low"
            record.loadConfidenceRaw = "none"
            record.recoveryConfidenceRaw = hasRecovery ? "medium" : "low"
            record.appStateRaw = "historicalBackfill"
            record.baselineMaturityStageRaw = "established"
            record.dataPointCountAtCalculation = allDays.count

            context.insert(record)
            inserted += 1
        }

        if inserted > 0 {
            try? context.save()
            #if DEBUG
            print("[HELIX DEBUG] Historical backfill: inserted \(inserted) records using real Sleep/Recovery calculators.")
            #endif
        } else {
            #if DEBUG
            print("[HELIX DEBUG] Historical backfill: no new records needed.")
            #endif
        }
    }

    // MARK: — Debug (for HelixDebugView)

    /// Index from current app state when in a score-bearing state; nil otherwise.
    var indexFromState: HelixIndex? {
        switch appState {
        case .fullScore(let index), .partialScore(let index, _), .developingBaseline(_, let index):
            return index
        default:
            return nil
        }
    }

    var helixIndex: Double? { indexFromState?.score }
    var sleepScore: Double? { indexFromState?.sleepStrand.score }
    var loadScore: Double? { indexFromState?.loadStrand.score }
    var recoveryScore: Double? { indexFromState?.recoveryStrand.score }
    var confidence: ConfidenceLevel? { indexFromState?.overallConfidence }
    var posture: String? { indexFromState.map { "\($0.posture.rawValue)" } }
    var hasLoadedHealthData: Bool {
        switch appState {
        case .fetchingData, .fullScore, .partialScore, .developingBaseline, .learningBaseline, .suppressedScore:
            return true
        default:
            return false
        }
    }

    #if DEBUG
    var sleepStrand: StrandScore? { indexFromState?.sleepStrand }
    var loadStrand: StrandScore? { indexFromState?.loadStrand }
    var recoveryStrand: StrandScore? { indexFromState?.recoveryStrand }
    var interactionTerms: InteractionTerms? { indexFromState?.interactionTerms }
    var balancePenalty: Double? { indexFromState?.balancePenalty }
    var recoveryGateApplied: Bool { indexFromState?.recoveryGateApplied ?? false }
    var recoveryGateLevel: RecoveryGateLevel? { indexFromState?.recoveryGateLevel }
    #endif
}

