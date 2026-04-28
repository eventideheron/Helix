// Models/SignalIdentifier.swift
// CRITICAL: rawValues must match helix_policy.v1.x.json decay_rates keys exactly.
// Any drift between these rawValues and the JSON keys will cause silent fallback
// to the default decay rate (0.94) in HelixBaselineEngine.buildBaselines().
// Validate alignment whenever policy JSON is updated.

enum SignalIdentifier: String, CaseIterable, Codable {

    // MARK: — Sleep strand
    // rawValues match HistoricalRawData field names and policy decay_rates keys
    case sleepDuration          = "sleep_duration"
    case deepSleepPercent       = "deep_sleep_percent"
    case remSleepPercent        = "rem_sleep_percent"
    case awakeningsPerHour      = "awakenings_per_hour"
    case sleepConsistency       = "sleep_consistency"
    case wristTemperature       = "wrist_temperature"
    case overnightRespiratory   = "respiratory_rate"

    // MARK: — Load strand
    case trainingVolume         = "training_volume"
    case trainingIntensity      = "training_intensity"
    case acuteChronicRatio      = "acute_chronic_ratio"
    case activityCompletion     = "activity_completion"
    case hrElevation            = "hr_elevation"

    // MARK: — Recovery strand
    case hrv                    = "hrv"
    case restingHR              = "resting_hr"
    case overnightHRDip         = "overnight_hr_dip"
    case respiratoryRecovery    = "respiratory_recovery"
    case spo2                   = "spo2"
}

enum HelixStrand: String, Codable {
    case sleep    = "STRAND_I"
    case load     = "STRAND_II"
    case recovery = "STRAND_III"
}

enum HelixPosture: String, Codable {
    case pursue   = "PURSUE"
    case moderate = "MODERATE"
    case restore  = "RESTORE"
}

enum ConfidenceLevel: String, Codable {
    case high   = "HIGH"
    case medium = "MEDIUM"
    case low    = "LOW"
}

enum RecoveryGateLevel: String, Codable {
    case severe   // score < 20, multiplier 0.55 — checked FIRST (worse state)
    case critical // score < 35, multiplier 0.75
}

enum BaselineStabilityStatus: Codable {
    case stable
    case transient(daysPersisted: Int)
    case recalibrating(progress: Double)
}

extension HelixStrand {
    var displayLabel: String {
        switch self {
        case .sleep:    return "SLEEP"
        case .load:     return "LOAD"
        case .recovery: return "RECOVERY"
        }
    }
}

extension ConfidenceLevel: Comparable {
    public static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool {
        let order: [ConfidenceLevel] = [.low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Key used to look up this signal's validation range in policy validation_ranges (helix_policy.v1.x.json).
/// Nil for signals that have no validation range in policy.
extension SignalIdentifier {
    var validationRangeKey: String? {
        switch self {
        case .sleepDuration:          return "sleep_duration_hours"
        case .deepSleepPercent:       return "deep_sleep_percent"
        case .remSleepPercent:        return "rem_sleep_percent"
        case .awakeningsPerHour:      return "awakenings_per_hour"
        // Combined bedtime + wake timing SD; policy still stores per-component ranges only — skip single-key validation here.
        case .sleepConsistency:       return nil
        case .wristTemperature:       return "wrist_temp_celsius_delta"
        case .overnightRespiratory:   return "respiratory_rate_brpm"
        case .trainingVolume:         return "active_energy_kcal_daily"
        case .trainingIntensity:      return nil
        case .acuteChronicRatio:      return nil
        case .activityCompletion:     return nil
        case .hrElevation:            return nil
        case .hrv:                    return "hrv_sdnn_ms"
        case .restingHR:              return "resting_hr_bpm"
        case .overnightHRDip:         return "hr_dip_bpm"
        case .respiratoryRecovery:    return "respiratory_rate_brpm"
        case .spo2:                   return "spo2_percent"
        }
    }
}

extension SignalIdentifier {
    var explanationKey: String {
        switch self {
        case .sleepDuration:      return "sleep_duration"
        case .deepSleepPercent:   return "deep_sleep"
        case .remSleepPercent:    return "rem_sleep"
        case .awakeningsPerHour:  return "disturbance"
        case .sleepConsistency:   return "sleep_consistency"
        case .wristTemperature:   return "wrist_temperature"
        case .overnightRespiratory: return "respiratory"
        case .trainingVolume:     return "acwr"
        case .trainingIntensity:  return "acwr"
        case .acuteChronicRatio:  return "acwr"
        case .activityCompletion: return "acwr"
        case .hrElevation:        return "hr_elevation"
        case .hrv:                return "hrv"
        case .restingHR:          return "resting_hr"
        case .overnightHRDip:     return "overnight_hr_dip"
        case .respiratoryRecovery: return "respiratory"
        case .spo2:               return "respiratory"
        }
    }
}

extension SignalIdentifier {
    var displayLabel: String {
        switch self {
        case .sleepDuration:        return "Sleep Duration"
        case .deepSleepPercent:     return "Deep Sleep"
        case .remSleepPercent:      return "REM Sleep"
        case .awakeningsPerHour:    return "Disturbance"
        case .sleepConsistency:     return "Consistency"
        case .wristTemperature:     return "Temperature"
        case .overnightRespiratory: return "Respiratory"
        case .trainingVolume:       return "Volume"
        case .trainingIntensity:    return "Intensity"
        case .acuteChronicRatio:    return "ACWR"
        case .activityCompletion:   return "Activity"
        case .hrElevation:          return "HR Elevation"
        case .hrv:                  return "HRV"
        case .restingHR:            return "Resting HR"
        case .overnightHRDip:       return "HR Dip"
        case .respiratoryRecovery:  return "Respiratory"
        case .spo2:                 return "SpO2"
        }
    }
}
