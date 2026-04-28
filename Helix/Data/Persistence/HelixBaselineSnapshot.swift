// Models/HelixBaselineSnapshot.swift
// Persists yesterday's EWMA baseline values to SwiftData so that
// HelixBaselineEngine can use the O(1) iterative update path instead of
// the expensive 90-day historical scan on every app launch.
//
// Lifecycle:
//   First launch / data gap > iterativeGapDayThreshold → full scan (slow path)
//   Normal daily launch → iterative EWMA update (fast path)
//   Data gap 2–7 days → iterative loop over gap days (medium path)

import SwiftData
import Foundation

@Model
class HelixBaselineSnapshot {
    var date: Date = Date()
    var signalRaw: String = ""     // SignalIdentifier.rawValue — must match JSON key
    var ewmaValue: Double = 0.0
    var decayRate: Double = 0.0
    var dataPointCount: Int = 0
    var stabilityStatusRaw: String = "stable" // "stable" | "transient" | "recalibrating"
    /// When set, EWMA for this signal was computed from a specific metric definition (e.g. sleep consistency v2).
    var metricSignatureRaw: String? = nil

    init() {
        self.date = Date()
        self.signalRaw = ""
        self.ewmaValue = 0
        self.decayRate = 0
        self.dataPointCount = 0
        self.stabilityStatusRaw = "stable"
        self.metricSignatureRaw = nil
    }

    init(
        date: Date,
        signal: SignalIdentifier,
        ewmaValue: Double,
        decayRate: Double,
        dataPointCount: Int,
        stabilityStatus: BaselineStabilityStatus = .stable,
        metricSignature: String? = nil
    ) {
        self.date = date
        self.signalRaw = signal.rawValue
        self.ewmaValue = ewmaValue
        self.decayRate = decayRate
        self.dataPointCount = dataPointCount
        self.stabilityStatusRaw = stabilityStatus.persistedString
        self.metricSignatureRaw = metricSignature
    }

    var signal: SignalIdentifier? {
        SignalIdentifier(rawValue: signalRaw)
    }

    var stabilityStatus: BaselineStabilityStatus {
        BaselineStabilityStatus(from: stabilityStatusRaw) ?? .stable
    }
}

// MARK: — BaselineStabilityStatus persistence helpers

private extension BaselineStabilityStatus {
    var persistedString: String {
        switch self {
        case .stable:
            return "stable"
        case .transient(let days):
            return "transient:\(days)"
        case .recalibrating(let progress):
            return "recalibrating:\(progress)"
        }
    }

    init?(from string: String) {
        if string == "stable" {
            self = .stable
        } else if string.hasPrefix("transient:"),
                  let days = Int(string.dropFirst("transient:".count)) {
            self = .transient(daysPersisted: days)
        } else if string.hasPrefix("recalibrating:"),
                  let progress = Double(string.dropFirst("recalibrating:".count)) {
            self = .recalibrating(progress: progress)
        } else {
            return nil
        }
    }
}
