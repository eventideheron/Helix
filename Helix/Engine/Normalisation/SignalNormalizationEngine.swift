// Engine/SignalNormalizationEngine.swift
// Sits between HealthKit raw data and strand calculators.
//
// ChatGPT audit item #6: "Add a normalization/validation layer between HealthKit and engines."
// Without this layer, calculators receive unvalidated raw values and have no way to
// distinguish a legitimate 200ms HRV from a sensor glitch.
//
// Responsibilities:
//   1. Map HealthKit units into app-native units (SpO2 fraction → percentage, etc.)
//   2. Apply policy validation ranges
//   3. Detect anomalies per policy anomaly_detection thresholds
//   4. Return ValidatedSignal for each input, with isUsable, isAnomaly, and reason
//
// Engines should only operate on ValidatedSignal.value and should check isUsable
// before including a signal in calculation.

import Foundation

struct ValidatedSignal {
    let identifier: SignalIdentifier
    let rawValue: Double          // As received from HealthKit (unconverted)
    let value: Double             // Normalised app-native value
    let isUsable: Bool            // False if outside validation range or flagged anomaly
    let isAnomaly: Bool           // True if spike detection fired
    let exclusionReason: ExclusionReason?
    let timestamp: Date
}

enum ExclusionReason: String {
    case outsideValidationRange
    case anomalySpike
    case missingBaseline
    case insufficientSamples
}

class SignalNormalizationEngine {

    private let policy: HelixCorePolicy
    private let confidencePolicy: HelixConfidencePolicy

    init(policy: HelixCorePolicy, confidencePolicy: HelixConfidencePolicy) {
        self.policy           = policy
        self.confidencePolicy = confidencePolicy
    }

    // MARK: — Primary API

    /// Validate and normalise a single raw HealthKit value.
    func validate(
        _ rawValue: Double,
        for signal: SignalIdentifier,
        baseline: Double?,
        timestamp: Date = Date()
    ) -> ValidatedSignal {

        // Step 1: Unit normalisation
        let value = normalise(rawValue, for: signal)

        // Step 2: Validation range check
        if let rangeKey = signal.validationRangeKey,
           let range = policy.validationRanges[rangeKey],
           !range.contains(value) {
            return ValidatedSignal(
                identifier: signal,
                rawValue: rawValue,
                value: value,
                isUsable: false,
                isAnomaly: false,
                exclusionReason: .outsideValidationRange,
                timestamp: timestamp
            )
        }

        // Step 3: Anomaly spike detection (requires baseline)
        if let baseline = baseline, baseline > 0 {
            if isAnomaly(value: value, baseline: baseline, for: signal) {
                return ValidatedSignal(
                    identifier: signal,
                    rawValue: rawValue,
                    value: value,
                    isUsable: false,
                    isAnomaly: true,
                    exclusionReason: .anomalySpike,
                    timestamp: timestamp
                )
            }
        }

        return ValidatedSignal(
            identifier: signal,
            rawValue: rawValue,
            value: value,
            isUsable: true,
            isAnomaly: false,
            exclusionReason: nil,
            timestamp: timestamp
        )
    }

    /// Validate a full set of raw signals, returning a dictionary of validated results.
    func validateAll(
        rawSignals: [SignalIdentifier: Double],
        baselines: [SignalIdentifier: PersonalBaseline],
        timestamp: Date = Date()
    ) -> [SignalIdentifier: ValidatedSignal] {

        var result = [SignalIdentifier: ValidatedSignal]()
        for (signal, raw) in rawSignals {
            result[signal] = validate(
                raw,
                for: signal,
                baseline: baselines[signal]?.value,
                timestamp: timestamp
            )
        }
        return result
    }

    // MARK: — Unit normalisation

    private func normalise(_ value: Double, for signal: SignalIdentifier) -> Double {
        switch signal {
        case .spo2:
            // HealthKit stores SpO2 as fraction 0.0–1.0; policy uses percentage 0–100
            return value <= 1.0 ? value * 100.0 : value
        default:
            return value
        }
    }

    // MARK: — Anomaly detection

    private func isAnomaly(value: Double, baseline: Double, for signal: SignalIdentifier) -> Bool {
        let anomaly = confidencePolicy.dataQuality.anomalyDetection

        switch signal {
        case .hrv:
            let percentChange = abs(value - baseline) / baseline
            return percentChange > anomaly.hrvSpikeThresholdPercent

        case .restingHR:
            let bpmChange = abs(value - baseline)
            return bpmChange > anomaly.rhrSpikeThresholdBpm

        case .wristTemperature:
            let celsiusChange = abs(value - baseline)
            return celsiusChange > anomaly.tempSpikeThresholdCelsius

        default:
            return false
        }
    }
}

// MARK: — Convenience: extract usable value or nil

extension ValidatedSignal {
    var usableValue: Double? {
        isUsable ? value : nil
    }
}

extension Dictionary where Key == SignalIdentifier, Value == ValidatedSignal {
    func usableValue(for signal: SignalIdentifier) -> Double? {
        self[signal]?.usableValue
    }
}
