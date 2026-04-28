// Data/Persistence/HelixSchema.swift
// Owns SwiftData schema versioning and migration plan for Helix.
//
// FROZEN MODEL NAMING RULE — DO NOT CHANGE:
//   Frozen model copies inside HelixSchemaV1 MUST use the
//   original class names: HelixDailyRecord, HelixBaselineSnapshot,
//   HelixTriggerRecord. SwiftData uses the class name as the entity name
//   for schema hash computation. These names must match the entity names
//   already written to the on-disk store.
//
// V1 FROZEN SHAPE (2026-04-21 CL pre-flight):
//   Cross-checked against live `HelixDailyRecord.swift` / baseline / trigger.
//   **`appStateRaw` is `String?`** on deployed rows (legacy-safe); CG reference
//   used non-optional `String` — repo truth wins for V1 anchor.
//
// V2:
//   `HelixSchemaV2` lists **module-level** `@Model` types (live files) with
//   declaration defaults — no duplicate nested `@Model` classes here.
//
// MODEL EVOLUTION: see plan / handoff standing rules.

import SwiftData
import Foundation

// MARK: — V1: Frozen schema as deployed through 2026-04-21

enum HelixSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    @Model final class HelixDailyRecord {
        var date: Date
        var helixIndex: Double
        var postureRaw: String
        var confidenceRaw: String
        var balancePenalty: Double
        var recoveryGateApplied: Bool
        var recoveryGateLevelRaw: String?
        var sleepScore: Double
        var loadScore: Double
        var recoveryScore: Double
        var sleepConfidenceRaw: String
        var loadConfidenceRaw: String
        var recoveryConfidenceRaw: String
        var sleepBoostApplied: Double
        var loadCostApplied: Double
        var sleepContributionsJSON: String
        var loadContributionsJSON: String
        var recoveryContributionsJSON: String
        var sleepMissingSignalsRaw: String
        var loadMissingSignalsRaw: String
        var recoveryMissingSignalsRaw: String
        var sleepPrimaryExplanation: String
        var loadPrimaryExplanation: String
        var recoveryPrimaryExplanation: String
        var isTodayInHistory: Bool
        var historyTriggerRaw: String?
        var historyMessage: String?
        var baselineMaturityStageRaw: String
        var dataPointCountAtCalculation: Int
        var appStateRaw: String?

        init() {
            self.date = Date()
            self.helixIndex = 0
            self.postureRaw = ""
            self.confidenceRaw = ""
            self.balancePenalty = 0
            self.recoveryGateApplied = false
            self.recoveryGateLevelRaw = nil
            self.sleepScore = 0
            self.loadScore = 0
            self.recoveryScore = 0
            self.sleepConfidenceRaw = ""
            self.loadConfidenceRaw = ""
            self.recoveryConfidenceRaw = ""
            self.sleepBoostApplied = 0
            self.loadCostApplied = 0
            self.sleepContributionsJSON = "[]"
            self.loadContributionsJSON = "[]"
            self.recoveryContributionsJSON = "[]"
            self.sleepMissingSignalsRaw = ""
            self.loadMissingSignalsRaw = ""
            self.recoveryMissingSignalsRaw = ""
            self.sleepPrimaryExplanation = ""
            self.loadPrimaryExplanation = ""
            self.recoveryPrimaryExplanation = ""
            self.isTodayInHistory = false
            self.historyTriggerRaw = nil
            self.historyMessage = nil
            self.baselineMaturityStageRaw = "learning"
            self.dataPointCountAtCalculation = 0
            self.appStateRaw = nil
        }
    }

    @Model final class HelixBaselineSnapshot {
        var date: Date
        var signalRaw: String
        var ewmaValue: Double
        var decayRate: Double
        var dataPointCount: Int
        var stabilityStatusRaw: String
        var metricSignatureRaw: String?

        init() {
            self.date = Date()
            self.signalRaw = ""
            self.ewmaValue = 0
            self.decayRate = 0
            self.dataPointCount = 0
            self.stabilityStatusRaw = "stable"
            self.metricSignatureRaw = nil
        }
    }

    @Model final class HelixTriggerRecord {
        var date: Date
        var triggerTypeRaw: String
        var strandRaw: String?
        var message: String
        var metricValue: Double
        var thresholdPercentile: Double?

        init() {
            self.date = Date()
            self.triggerTypeRaw = ""
            self.strandRaw = nil
            self.message = ""
            self.metricValue = 0
            self.thresholdPercentile = nil
        }
    }

    static var models: [any PersistentModel.Type] {
        [HelixDailyRecord.self, HelixBaselineSnapshot.self, HelixTriggerRecord.self]
    }
}

// MARK: — V2: Current schema (live @Model types in app target)

enum HelixSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [HelixDailyRecord.self, HelixBaselineSnapshot.self, HelixTriggerRecord.self]
    }
}

// MARK: — Migration Plan

enum HelixMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [HelixSchemaV1.self, HelixSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: HelixSchemaV1.self,
        toVersion: HelixSchemaV2.self
    )
}
