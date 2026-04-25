// App/AppDependencies.swift
// Single place where all concrete dependencies are constructed and wired.
// HelixViewModel receives this container rather than constructing dependencies itself.
// Makes testing straightforward — swap in mock providers without touching ViewModel.
//
// ChatGPT audit: separating App/ wiring from engine logic keeps ViewModel clean.

import Foundation

@MainActor
class AppDependencies {

    let policyBundle:         HelixPolicyBundle
    let authManager:          HealthKitAuthorizationManager
    let sleepProvider:        SleepDataProvider
    let recoveryProvider:     RecoveryDataProvider
    let loadProvider:         LoadDataProvider
    let historyProvider:      HistoryDataProvider
    let baselineEngine:       HelixBaselineEngine
    let confidenceEngine:     HelixConfidenceEngine
    let normalisationEngine:  SignalNormalizationEngine
    let sleepCalc:            HelixSleepCalculator
    let loadCalc:             HelixLoadCalculator
    let recoveryCalc:         HelixRecoveryCalculator
    let indexCalc:            HelixIndexCalculator
    let explanationEngine:    HelixExplanationEngine
    let historyEngine:        HelixHistoryEngine
    let policyValidator:      HelixPolicyValidator.Type

    init() {
        // Policy must load before anything else. fatalError is intentional —
        // app cannot function with missing or corrupt policy files.
        let bundle: HelixPolicyBundle
        do {
            bundle = try HelixPolicyLoader.loadAll()
        } catch {
            fatalError("Policy load failed at startup: \(error.localizedDescription)")
        }
        self.policyBundle = bundle

        // Validate structure before first calculation
        do {
            try HelixPolicyValidator.validate(bundle: bundle)
        } catch {
            fatalError("Policy validation failed: \(error.localizedDescription)")
        }

        // HealthKit providers
        self.authManager      = HealthKitAuthorizationManager()
        self.sleepProvider    = SleepDataProvider()
        self.recoveryProvider = RecoveryDataProvider()
        self.loadProvider     = LoadDataProvider()
        self.historyProvider  = HistoryDataProvider()

        // Engines (order matters: confidence must exist before calculators)
        let confidence = HelixConfidenceEngine(policy: bundle.confidence)
        self.confidenceEngine    = confidence
        self.baselineEngine      = HelixBaselineEngine(
            policy: bundle.core,
            confidencePolicy: bundle.confidence
        )
        self.normalisationEngine = SignalNormalizationEngine(
            policy: bundle.core,
            confidencePolicy: bundle.confidence
        )
        self.sleepCalc           = HelixSleepCalculator(
            policy: bundle.core.strandSleep,
            confidenceEngine: confidence
        )
        self.loadCalc            = HelixLoadCalculator(
            policy: bundle.core.strandLoad,
            confidenceEngine: confidence
        )
        self.recoveryCalc        = HelixRecoveryCalculator(
            policy: bundle.core.strandRecovery,
            confidenceEngine: confidence
        )
        self.indexCalc           = HelixIndexCalculator(policy: bundle.core.helixIndex)
        self.explanationEngine   = HelixExplanationEngine(policy: bundle.explanation)
        self.historyEngine       = HelixHistoryEngine(policy: bundle.history)
        self.policyValidator     = HelixPolicyValidator.self
    }
}
