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

@MainActor
class HelixViewModel: ObservableObject {

    @Published var appState: HelixAppState = .idle

    // MARK: — Dependencies

    private let policyBundle:        HelixPolicyBundle
    private let authManager:         HealthKitAuthorizationManager
    private let sleepProvider:       SleepDataProvider
    private let recoveryProvider:    RecoveryDataProvider
    private let loadProvider:        LoadDataProvider
    private let historyProvider:     HistoryDataProvider
    private let baselineEngine:      HelixBaselineEngine
    private let confidenceEngine:    HelixConfidenceEngine
    private let normalizationEngine: SignalNormalizationEngine
    private let recoveryCalc:        HelixRecoveryCalculator
    private let indexCalc:           HelixIndexCalculator

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
        self.normalizationEngine  = SignalNormalizationEngine(
            policy: bundle.core,
            confidencePolicy: bundle.confidence
        )
        self.recoveryCalc = HelixRecoveryCalculator(
            policy: bundle.core.strandRecovery,
            confidenceEngine: confidenceEngine
        )
        self.indexCalc = HelixIndexCalculator(policy: bundle.core.helixIndex)

        // Validate policy version before any calculation begins
        baselineEngine.validatePolicyVersion()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: — Primary load flow

    func loadToday() async {
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

        appState = .fetchingData

        do {
            // 1. Fetch raw data from all providers concurrently
            let ageContext    = authManager.fetchUserAge()
            async let sleepRaw    = sleepProvider.fetchTodayData()
            async let loadRaw     = loadProvider.fetchTodayData()
            async let historyRaw  = historyProvider.fetchHistoricalData(days: 90)

            let sleepData   = try await sleepRaw
            let loadData    = try await loadRaw
            let historyData = try await historyRaw

            // Recovery provider reuses sleep-derived values to avoid double-querying
            let recoveryData = try await recoveryProvider.fetchTodayData(
                minSleepHR:  sleepData.minSleepHR,
                overnightRR: sleepData.overnightRespiratoryRate
            )

            // 2. Build baselines (fast path if SwiftData snapshots available)
            let cachedSnapshots = loadBaselineSnapshots()
            let baselines = baselineEngine.buildBaselines(
                from: historyData,
                cachedSnapshots: cachedSnapshots
            )
            let dataPointCount = historyData.hrvReadings.count

            // 3. Check baseline activation threshold
            let minDays = policyBundle.core.baseline.minimumDaysToActivate
            if dataPointCount < minDays {
                let daysRemaining = minDays - dataPointCount
                appState = .learningBaseline(daysRemaining: daysRemaining)
                return
            }

            // 4. Signal normalisation and validation
            let rawRecoverySignals: [SignalIdentifier: Double] = [
                .hrv:               recoveryData.morningHRV ?? 0,
                .restingHR:         recoveryData.restingHR ?? 0,
                .overnightHRDip:    recoveryData.minSleepHR.map { baselines[.restingHR]?.value.map { $0 - $1 } ?? 0 } ?? 0,
                .respiratoryRecovery: recoveryData.overnightRR ?? 0,
                .spo2:              recoveryData.spo2Rolling7Night ?? 0
            ].filter { $0.value > 0 }   // Remove unprovided signals before validation

            let validatedRecovery = normalizationEngine.validateAll(
                rawSignals: rawRecoverySignals,
                baselines: baselines
            )

            // 5. Calculate Recovery strand
            let (recoveryScore, recoveryMissing) = recoveryCalc.calculate(
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

            let recoveryStrand = StrandScore(
                strand: .recovery,
                score: recoveryScore,
                componentSignals: [],
                missingSignals: recoveryMissing,
                confidence: recoveryConfidenceResult.level,
                contributionBreakdown: [],
                primaryExplanation: recoveryConfidenceResult.explanationKey,
                calculatedAt: Date()
            )

            // 6. Sleep and Load strands
            // These calculators are not yet built. Per ChatGPT recommendation,
            // we do NOT inject placeholder scores. Instead:
            //   - If only recovery is available, reflect that in appState.
            //   - The index is NOT calculated from placeholder scores.
            //
            // TODO: Implement HelixSleepCalculator and HelixLoadCalculator.
            // When both are available, replace the guard below with real calculations
            // and call indexCalc.calculate(sleep:load:recovery:).

            let allStrandsAvailable = false  // Set to true when all three calculators exist

            if !allStrandsAvailable {
                let missingSt: [SignalIdentifier] = [
                    .sleepDuration, .deepSleepPercent, .remSleepPercent,
                    .acuteChronicRatio, .trainingVolume
                ]
                appState = .partialScore(
                    // Partial index using recovery only — clearly marked as such in UI
                    HelixIndex(
                        score: recoveryScore,
                        posture: .moderate,
                        sleepStrand: StrandScore(
                            strand: .sleep, score: 0, componentSignals: [],
                            missingSignals: [.sleepDuration, .deepSleepPercent, .remSleepPercent,
                                             .awakeningsPerHour, .sleepConsistency],
                            confidence: .low, contributionBreakdown: [],
                            primaryExplanation: "Sleep calculator not yet implemented.",
                            calculatedAt: Date()
                        ),
                        loadStrand: StrandScore(
                            strand: .load, score: 0, componentSignals: [],
                            missingSignals: [.acuteChronicRatio, .trainingVolume, .trainingIntensity],
                            confidence: .low, contributionBreakdown: [],
                            primaryExplanation: "Load calculator not yet implemented.",
                            calculatedAt: Date()
                        ),
                        recoveryStrand: recoveryStrand,
                        overallConfidence: .low,
                        balancePenalty: 0,
                        recoveryGateApplied: false,
                        recoveryGateLevel: nil,
                        interactionTerms: InteractionTerms(
                            sleepBoostApplied: 0, loadCostApplied: 0, netInteractionEffect: 0),
                        date: Date()
                    ),
                    missingSignals: missingSt
                )

                // Still persist what we have
                persistAndUpdateBaselines(
                    baselines: baselines,
                    index: nil,
                    appState: appState,
                    dataPointCount: dataPointCount
                )
                return
            }

            // 7. Full index calculation (reached when all three strands available)
            // let sleepStrand = ...
            // let loadStrand = ...
            // let index = indexCalc.calculate(sleep: sleepStrand, load: loadStrand, recovery: recoveryStrand)
            // appState = recoveryMissing.isEmpty ? .fullScore(index) : .partialScore(index, missingSignals: recoveryMissing)

        } catch {
            appState = .error(error.localizedDescription)
        }
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

        // Persist baseline snapshots for next-day O(1) EWMA
        let snapshots = baselineEngine.snapshotsForPersistence(from: baselines)
        snapshots.forEach { context.insert($0) }

        // Persist daily record if we have a composite index
        if let index = index {
            let record = HelixDailyRecord(from: index, appState: appState, dataPointCount: dataPointCount)
            context.insert(record)
        }

        try? context.save()
    }
}
