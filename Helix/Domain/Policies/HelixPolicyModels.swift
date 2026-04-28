// Policy/HelixPolicyModels.swift
// Decodable structs for bundled policy JSON files (core, confidence, explanation, history, cross-strand).
// HelixPolicyError and HelixPolicyLoader live in HelixPolicyLoader.swift.

import Foundation

// MARK: - Bundle

struct HelixPolicyBundle {
    let core:        HelixCorePolicy
    let confidence:  HelixConfidencePolicy
    let explanation: HelixExplanationPolicy
    let history:     HelixHistoryPolicy
    let crossStrand: CrossStrandPolicy
}

// MARK: - Core Policy (helix_policy.json)

struct HelixCorePolicy: Decodable {
    let policyVersion:    String
    let validationRanges: [String: ValidationRange]
    let baseline:         BaselineConfig
    let strandSleep:      SleepConfig
    let strandLoad:       LoadConfig
    let strandRecovery:   RecoveryConfig
    let helixIndex:       IndexConfig
}

struct ValidationRange: Decodable {
    let min: Double
    let max: Double
    func contains(_ value: Double) -> Bool { value >= min && value <= max }
}

struct BaselineConfig: Decodable {
    let windowDays:            Int
    let minimumDaysToActivate: Int
    let method:                String
    let decayRates:            [String: Double]
}

// MARK: Sleep

struct SleepConfig: Decodable {
    let weights:             SleepWeights
    let duration:            SleepDurationConfig
    let deepSleep:           SleepStageConfig
    let remSleep:            SleepStageConfig
    let disturbance:         DisturbanceConfig
    let consistency:         ConsistencyConfig
    let thermal:             ThermalConfig
    let respiratory:         SensitivityConfig
    let populationDefaults:  SleepPopulationDefaults
}

/// Warm-up baselines for sleep duration / staging when personal EWMA is absent or zero (policy-sourced only).
struct SleepPopulationDefaults: Decodable {
    let sleepDurationHours: Double
    let deepSleepFraction:  Double
    let remSleepFraction:   Double
}

struct SleepWeights: Decodable {
    let duration:    Double
    let deepSleep:   Double
    let remSleep:    Double
    let disturbance: Double
    let consistency: Double
    let thermal:     Double
    let respiratory: Double
}

struct SleepDurationConfig: Decodable {
    let undersleepCostPerHour: Double
    let oversleepCostPerHour:  Double
}

struct SleepStageConfig: Decodable {
    let baselineComparison: String
    let maxComponentScore:  Double
}

struct DisturbanceConfig: Decodable {
    let costPerAwakeningPerHour: Double
    let maxScore:                Double
}

struct ConsistencyConfig: Decodable {
    let bedtimeVarianceCostPerMinute: Double
    let wakeVarianceCostPerMinute:    Double
    let varianceWindowDays:           Int
}

struct ThermalConfig: Decodable {
    let sensitivity:                 Double
    let anomalyFlagThresholdCelsius: Double
    let baselineType:                String?
    let note:                        String?
}

struct SensitivityConfig: Decodable {
    let sensitivity: Double
}

// MARK: Load

struct LoadConfig: Decodable {
    let weights:        LoadWeights
    let heartRateZones: HRZoneConfig
    let acuteChronic:   AcuteChronicConfig
    let acwrScoring:    ACWRConfig
    let hrElevation:    HRElevationConfig
}

struct LoadWeights: Decodable {
    let acwr:               Double
    let acuteLoad:          Double
    let activityCompletion: Double
    let hrElevationPenalty: Double
}

struct HRZoneConfig: Decodable {
    let method:                String
    let zoneStressMultipliers: [String: Double]
    let neatEnergyMultiplier:  Double
}

struct AcuteChronicConfig: Decodable {
    let acuteWindowDays:   Int
    let chronicWindowDays: Int
    let acuteDecay:        Double
    let chronicDecay:      Double
}

struct ACWRConfig: Decodable {
    let undertrainingCeiling: Double
    let optimalLow:           Double
    let optimalHigh:          Double
    let cautionCeiling:       Double
}

struct HRElevationConfig: Decodable {
    let costPerBpmAboveBaseline: Double
    let maximumPenalty:          Double
}

// MARK: Recovery

struct RecoveryConfig: Decodable {
    let weights:        RecoveryWeights
    let hrv:            HRVConfig
    let restingHr:      RHRConfig
    let overnightHrDip: HRDipConfig
    let respiratory:    SensitivityConfig
    let spo2:           SpO2Config
}

struct RecoveryWeights: Decodable {
    let hrv:            Double
    let restingHr:      Double
    let overnightHrDip: Double
    let respiratory:    Double
}

struct HRVConfig: Decodable {
    let sensitivity:            Double
    let midpoint:               Double
    let morningWindowStartHour: Int?
    let morningWindowEndHour:   Int?
}

struct RHRConfig: Decodable {
    let costPerBpmAboveBaseline: Double
}

struct HRDipConfig: Decodable {
    let scoreMultiplier:                Double
    let minimumHrSamplesRequired:     Int
    /// Historical overnight min-HR series only; today’s path still uses `minimumHrSamplesRequired` (60).
    let minimumHistoricalHrSamples:     Int?
}

struct SpO2Config: Decodable {
    let rollingAverageNights: Int
    let thresholds:           SpO2Thresholds
    let modifiers:            SpO2Modifiers
}

struct SpO2Thresholds: Decodable {
    let nominal: Double
    let caution: Double
    let concern: Double
}

struct SpO2Modifiers: Decodable {
    let nominal:  Double
    let caution:  Double
    let concern:  Double
    let critical: Double
}

// MARK: Index

struct IndexConfig: Decodable {
    let weights:           IndexWeights
    let interactionTerms:  InteractionConfig
    let recoveryGate:      RecoveryGateConfig
    let balancePenalty:    BalancePenaltyConfig
    let postureThresholds: PostureThresholds
}

struct IndexWeights: Decodable {
    let sleep:    Double
    let recovery: Double
    let load:     Double
}

struct InteractionConfig: Decodable {
    let sleepBoostDivisor: Double
    let loadCostDivisor:   Double
}

struct RecoveryGateConfig: Decodable {
    let severeThreshold:    Double
    let severeMultiplier:   Double
    let criticalThreshold:  Double
    let criticalMultiplier: Double
}

struct BalancePenaltyConfig: Decodable {
    let varianceMultiplier: Double
    let maximumPenalty:     Double
}

struct PostureThresholds: Decodable {
    let pursue:   Double
    let moderate: Double
    let restore:  Double
}

// MARK: - Confidence Policy (helix_confidence_policy.json)

struct HelixConfidencePolicy: Decodable {
    let policyVersion:       String
    let signalRequirements:  [String: SignalRequirement]
    let confidenceLevels:    ConfidenceLevels
    let watchOffline:        WatchOfflineConfig
    let gracefulDegradation: GracefulDegradationConfig
    let baselineStability:   BaselineStabilityConfig?
    let dataQuality:         DataQualityConfig
}

struct SignalRequirement: Decodable {
    let minimumReadings:       Int?
    let maximumAgeHours:       Int?
    let fallbackIfUnavailable: String?
}

struct ConfidenceLevels: Decodable {
    let high:   HighConfidenceConfig
    let medium: MediumConfidenceConfig
    let low:    LowConfidenceConfig
}

struct HighConfidenceConfig: Decodable {
    let minimumSignalsPresentPercent: Double
    let primarySignalsRequired: [String]
}

struct MediumConfidenceConfig: Decodable {
    let minimumSignalsPresent: Int
}

struct LowConfidenceConfig: Decodable {
    let minimumSignalsPresent: Int
}

struct WatchOfflineConfig: Decodable {
    let scoreSupressedIfOfflineHours: Double
    let partialScoreIfOfflineHours:   Double
    let messageTrigger:               String
}

struct GracefulDegradationConfig: Decodable {
    let method:                    String
    let minimumSignalsToCalculate: Int
    let belowMinimumBehavior:      String
}

struct BaselineStabilityConfig: Decodable {
    let enabled:                  Bool
    let shortWindowDays:          Int
    let longWindowDays:           Int
    let shiftDetectionThresholds: ShiftThresholds
    let confirmationRequiredDays: Int
    let recalibrationBehavior:    RecalibrationConfig
}

struct ShiftThresholds: Decodable {
    let hrvPercentChange:         Double
    let restingHrBpmChange:       Double
    let sleepDurationHoursChange: Double
}

struct RecalibrationConfig: Decodable {
    let method:          String
    let blendWindowDays: Int
}

struct DataQualityConfig: Decodable {
    let anomalyDetection: AnomalyDetectionConfig
}

struct AnomalyDetectionConfig: Decodable {
    let hrvSpikeThresholdPercent:  Double
    let rhrSpikeThresholdBpm:      Double
    let tempSpikeThresholdCelsius: Double
}

// MARK: - Explanation Policy (helix_explanation_policy.json)

struct HelixExplanationPolicy: Decodable {
    let policyVersion:       String
    let designPrinciples:    ExplanationDesignPrinciples?
    let signalThresholds:    SignalThresholds
    let languageTemplates:   [String: [String: String]]
    let postureLanguage:     [String: PostureLanguage]
    let confidenceLanguage:  [String: String]
    let decomposition:       DecompositionConfig
}

/// Governance copy bundled with explanation policy (`design_principles` in JSON). Optional for backward compatibility.
struct ExplanationDesignPrinciples: Decodable {
    let languageRule:                   String
    let rationale:                      String
    let directionalLanguagePermitted: String
    let appliesTo:                      [String]
    let enforcement:                    String
}

struct SignalThresholds: Decodable {
    let hrv:              HRVThresholds
    let restingHr:        RHRThresholds
    let sleepDuration:    SleepDurationThresholds
    let sleepConsistency: SleepConsistencyThresholds
    let wristTemperature: TemperatureThresholds
    let overnightHrDip:   HRDipThresholds
    let acwr:             ACWRThresholds
    let hrElevation:      HrElevationThresholds
}

/// Bands for `language_templates.hr_elevation.*` (explanation policy). Compared to normalized component score (higher = less strain).
struct HrElevationThresholds: Decodable {
    let highStrainThreshold: Double
    let moderateStrainThreshold: Double
}

struct HRVThresholds: Decodable {
    let notableDropPercent:     Double
    let significantDropPercent: Double
    let strongDropPercent:      Double
    let notableRisePercent:     Double
    let significantRisePercent: Double
}

struct RHRThresholds: Decodable {
    let notableRiseBpm:     Double
    let significantRiseBpm: Double
    let strongRiseBpm:      Double
    let notableDropBpm:     Double
}

struct SleepDurationThresholds: Decodable {
    let notableDeficitHours:     Double
    let significantDeficitHours: Double
    let strongDeficitHours:      Double
    let notableSurplusHours:     Double
}

struct SleepConsistencyThresholds: Decodable {
    let notableVarianceMinutes:     Double
    let significantVarianceMinutes: Double
}

struct TemperatureThresholds: Decodable {
    let notableDeviationCelsius:     Double
    let significantDeviationCelsius: Double
}

struct HRDipThresholds: Decodable {
    let strongDipBpm:   Double
    let moderateDipBpm: Double
    let shallowDipBpm:  Double
}

struct ACWRThresholds: Decodable {
    let highLoadThreshold:     Double
    let veryHighLoadThreshold: Double
    let lowLoadThreshold:      Double
}

struct PostureLanguage: Decodable {
    let headline: String
    let subtext:  String
}

struct DecompositionConfig: Decodable {
    let showPointContribution:    Bool
    let showDeltaFromBaseline:    Bool
    let showConfidenceLevel:      Bool
    let showMissingSignals:       Bool
    let maximumContributorsShown: Int
    let sortBy:                   String
}

// MARK: - History Policy (helix_history_policy.json)

struct HelixHistoryPolicy: Decodable {
    let policyVersion:           String
    let baselineRelationship:    BaselineRelationshipConfig
    let activationRequirements:  HistoryActivationConfig
    let todayInHistory:          TodayInHistoryConfig
    let seasonalDetection:       SeasonalDetectionConfig
    let seasonalOutputs:         SeasonalOutputsConfig
    let comparisonWindows:       ComparisonWindowsConfig
    let trendDetection:          TrendDetectionConfig
    let milestones:              MilestonesConfig
}

struct BaselineRelationshipConfig: Decodable {
    let scoringBaselineSource:           String
    let scoringBaselineWindowDays:       Int
    let scoringBaselineMethod:           String
    let seasonalLayerAffectsScoring:    Bool
    let seasonalLayerAffectsExplanation: Bool
    let seasonalLayerAffectsUserWarnings: Bool
    let note:                            String
}

struct HistoryActivationConfig: Decodable {
    let minimumDaysForBasicHistory:          Int
    let minimumDaysForSeasonalDetection:     Int
    let minimumYearsForSeasonalConfirmation: Int
}

struct TodayInHistoryConfig: Decodable {
    let enabled:  Bool
    let triggers: [String: AnyCodable]
}

struct PatternConfirmationSeasonal: Decodable {
    let minimumYears:                 Int
    let minimumCorrelation:          Double
    let minimumRepeatObservations:   Int
}

struct SeasonalClassificationRules: Decodable {
    let provisionalAfterFirstYear:  Bool
    let confirmedAfterSecondYear:    Bool
}

struct SeasonalDetectionConfig: Decodable {
    let enabled:                               Bool
    let detectionMethod:                       String
    let comparisonAnchorDaysAgo:               Int
    let comparisonWindowDaysBeforeAnchor:      Int
    let comparisonWindowDaysAfterAnchor:       Int
    let minimumDaysInWindow:                   Int
    let windowWeightingMethod:                 String
    let distanceDecayCurve:                    String
    let exactAnchorDayWeight:                  Double
    let edgeOfWindowWeight:                    Double
    let useSmoothedCurrentValues:              Bool
    let currentSmoothingWindowDays:            Int
    let comparisonMode:                        String
    let ignoreFixedMonthBuckets:               Bool
    let patternConfirmation:                   PatternConfirmationSeasonal
    let classification:                        SeasonalClassificationRules
    let warningLeadDays:                       Int
    let sleepDeclineThresholdPoints:           Double
    let recoverySuppressionThresholdPoints:    Double
    let trainingDisruptionVarianceThreshold:   Double
}

struct SeasonalMessageModes: Decodable {
    let provisional: String
    let confirmed:   String
}

struct SeasonalOutputsConfig: Decodable {
    let allowExplanatoryContext:       Bool
    let allowSupportingInsightCards:   Bool
    let allowWarningMessages:          Bool
    let allowBaselineReplacement:      Bool
    let allowDirectScoreModification:  Bool
    let messageModes:                  SeasonalMessageModes
}

struct ComparisonWindowsConfig: Decodable {
    let shortTermDays:   Int
    let mediumTermDays:  Int
    let longTermDays:    Int
    let allTime:         Bool
    let percentileBands: [String: Int]
}

struct TrendDetectionConfig: Decodable {
    let shortTrendDays:  Int
    let mediumTrendDays: Int
}

struct MilestonesConfig: Decodable {
    let enabled:                   Bool
    let consistencyMilestoneDays:  [Int]
    let baselineMaturityStages:    BaselineMaturityStages
}

struct BaselineMaturityStages: Decodable {
    let learning:    MaturityStage
    let developing:  MaturityStage
    let established: MaturityStage
    let mature:      MaturityStage
}

struct MaturityStage: Decodable {
    let dayRange: [Int]
    let message:  String
}

// MARK: - AnyCodable (heterogeneous JSON values in TodayInHistory triggers)

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)                 { value = v; return }
        if let v = try? container.decode(Int.self)                  { value = v; return }
        if let v = try? container.decode(Double.self)               { value = v; return }
        if let v = try? container.decode(String.self)               { value = v; return }
        if let v = try? container.decode([String: AnyCodable].self) { value = v; return }
        if let v = try? container.decode([AnyCodable].self)         { value = v; return }
        value = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        default:              try container.encodeNil()
        }
    }
}
