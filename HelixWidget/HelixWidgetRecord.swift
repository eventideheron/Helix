// HelixWidgetRecord.swift
// Widget display DTO — maps canonical SwiftData `HelixDailyRecord` from the shared store.
// Not persisted; not `@Model`.

import Foundation

/// Snapshot for widget UI — built from the app’s canonical `HelixDailyRecord` in the App Group store.
struct HelixWidgetDisplayRecord: Sendable {
    var date: Date = Date()
    var helixIndex: Double = 0.0
    var postureRaw: String = "MODERATE"
    var sleepScore: Double = 0.0
    var loadScore: Double = 0.0
    var recoveryScore: Double = 0.0
    var confidenceRaw: String = "LOW"

    init() {}

    init(from record: HelixDailyRecord) {
        self.date = record.date
        self.helixIndex = record.helixIndex
        self.postureRaw = record.postureRaw
        self.sleepScore = record.sleepScore
        self.loadScore = record.loadScore
        self.recoveryScore = record.recoveryScore
        self.confidenceRaw = record.confidenceRaw
    }

    var posture: HelixPosture {
        HelixPosture(rawValue: postureRaw) ?? .moderate
    }
}
