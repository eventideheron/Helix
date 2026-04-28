// Features/Dashboard/SignalCardMapper.swift
// Gate C/D: formats existing strand outputs for `SignalExplanationCardView` — no scoring.

import Foundation
import SwiftUI

struct SignalCardMapper {

    let explanationEngine: HelixExplanationEngine

    func cards(for strand: StrandScore) -> [SignalExplanationCardModel] {
        strand.contributionBreakdown
            .sorted { abs($0.pointContribution) > abs($1.pointContribution) }
            .compactMap { contribution -> SignalExplanationCardModel? in
                guard let signal = strand.componentSignals.first(where: { $0.identifier == contribution.signal }) else {
                    return nil
                }
                return card(for: contribution, signal: signal, strand: strand)
            }
    }

    func card(
        for contribution: SignalContribution,
        signal: HelixSignal,
        strand: StrandScore
    ) -> SignalExplanationCardModel {
        let sid = contribution.signal
        let id = "\(strand.strand.rawValue)_\(sid.rawValue)"
        let title = sid.displayTitle
        let strandCard: ExplanationCardStrand = {
            switch strand.strand {
            case .sleep:    return .sleep
            case .load:     return .load
            case .recovery: return .recovery
            }
        }()

        let routingContext = Self.routingContext(for: signal)
        let resolution = explanationEngine.resolveSignalCardExplanation(
            signal: sid,
            normalizedScore: signal.normalizedScore,
            deltaFromBaseline: signal.deltaFromBaseline,
            pointContribution: contribution.pointContribution,
            context: routingContext
        )

        let direction: SignalCardDirection = {
            switch resolution.directionKey {
            case "supporting":   return .supporting
            case "constraining": return .constraining
            default:             return .neutral
            }
        }()

        let valueText = Self.formatValue(signal: signal)
        let baselineText: String? = signal.baseline == 0 ? nil : Self.formatBaseline(signal: signal)
        let deltaText: String? = contribution.deltaDescription.isEmpty ? nil : contribution.deltaDescription
        let pointContributionText: String? = {
            let p = contribution.pointContribution
            if abs(p) < 0.5 { return nil }
            let i = Int(p.rounded())
            if i == 0 { return "0" }
            return i > 0 ? "+\(i)" : "\(i)"
        }()

        let missingNotes = strand.missingSignals.map { missing in
            "\(missing.displayTitle) not available — excluded from score"
        }

        let confidenceSourceKey = explanationEngine.confidenceSourceKey(for: strand)
        let confidenceLine = explanationEngine.confidenceString(forKey: confidenceSourceKey)
        let confidenceText: String = confidenceLine.isEmpty
            ? explanationEngine.confidenceString(for: strand.confidence)
            : confidenceLine

        return SignalExplanationCardModel(
            id: id,
            signalKey: resolution.signalKey,
            title: title,
            strand: strandCard,
            stateKey: resolution.stateKey,
            templateKey: resolution.templateKey,
            direction: direction,
            directionKey: resolution.directionKey,
            confidence: strand.confidence,
            confidenceSourceKey: confidenceSourceKey,
            valueText: valueText,
            baselineText: baselineText,
            deltaText: deltaText,
            pointContributionText: pointContributionText,
            headlineText: nil,
            explanationText: resolution.explanationText,
            implicationText: nil,
            confidenceText: confidenceText,
            missingSignalNotes: missingNotes,
            isCrossStrandSample: false
        )
    }

    private static func routingContext(for signal: HelixSignal) -> SignalExplanationRoutingContext {
        var c = SignalExplanationRoutingContext()
        switch signal.identifier {
        case .acuteChronicRatio:
            c.acuteChronicWorkloadRatio = signal.rawValue
        case .restingHR:
            c.restingHRBpmDelta = signal.rawValue - signal.baseline
        default:
            break
        }
        return c
    }

    private static func formatValue(signal: HelixSignal) -> String {
        switch signal.identifier {
        case .sleepDuration:
            return formatHours(signal.rawValue)
        case .deepSleepPercent, .remSleepPercent:
            return String(format: "%.0f%%", signal.rawValue * 100)
        case .sleepConsistency:
            return String(format: "%.0f min Σ", signal.rawValue)
        case .awakeningsPerHour:
            return String(format: "%.2f /hr", signal.rawValue)
        case .wristTemperature:
            return String(format: "%+.2f °C Δ", signal.rawValue)
        case .overnightRespiratory:
            return String(format: "%.1f brpm", signal.rawValue)
        case .hrv:
            return String(format: "%.0f ms", signal.rawValue)
        case .restingHR:
            return String(format: "%.0f bpm", signal.rawValue)
        case .overnightHRDip:
            return String(format: "%.0f bpm dip", signal.rawValue)
        case .respiratoryRecovery:
            return String(format: "%.1f /min", signal.rawValue)
        case .spo2:
            return String(format: "%.0f%%", signal.rawValue)
        case .acuteChronicRatio:
            return String(format: "%.2f ratio", signal.rawValue)
        case .trainingVolume:
            return String(format: "%.0f TSS", signal.rawValue)
        case .activityCompletion:
            return String(format: "%.0f pts", signal.rawValue)
        case .trainingIntensity:
            return String(format: "%.1f", signal.rawValue)
        case .hrElevation:
            return String(format: "%.0f bpm", signal.rawValue)
        }
    }

    private static func formatBaseline(signal: HelixSignal) -> String {
        switch signal.identifier {
        case .sleepDuration:
            return formatHours(signal.baseline)
        case .deepSleepPercent, .remSleepPercent:
            return String(format: "%.0f%%", signal.baseline * 100)
        case .sleepConsistency:
            return String(format: "%.0f min Σ", signal.baseline)
        case .awakeningsPerHour:
            return String(format: "%.2f /hr", signal.baseline)
        case .wristTemperature:
            return String(format: "%.2f °C", signal.baseline)
        case .overnightRespiratory:
            return String(format: "%.1f brpm", signal.baseline)
        case .hrv:
            return String(format: "%.0f ms", signal.baseline)
        case .restingHR:
            return String(format: "%.0f bpm", signal.baseline)
        case .overnightHRDip:
            return String(format: "%.0f bpm", signal.baseline)
        case .respiratoryRecovery:
            return String(format: "%.1f /min", signal.baseline)
        case .spo2:
            return String(format: "%.0f%%", signal.baseline)
        case .acuteChronicRatio:
            return String(format: "%.2f ratio", signal.baseline)
        case .trainingVolume:
            return String(format: "%.0f TSS", signal.baseline)
        case .activityCompletion:
            return String(format: "%.0f pts", signal.baseline)
        case .trainingIntensity:
            return String(format: "%.1f", signal.baseline)
        case .hrElevation:
            return String(format: "%.0f bpm", signal.baseline)
        }
    }

    private static func formatHours(_ h: Double) -> String {
        let totalMin = max(0, Int((h * 60).rounded()))
        let hh = totalMin / 60
        let mm = totalMin % 60
        if mm == 0 { return "\(hh)h" }
        return "\(hh)h \(mm)m"
    }
}

// MARK: — Display titles (mapper-local)

fileprivate extension SignalIdentifier {
    var displayTitle: String {
        switch self {
        case .hrv:                  return "HRV"
        case .restingHR:            return "Resting HR"
        case .sleepDuration:        return "Sleep Duration"
        case .sleepConsistency:     return "Sleep Consistency"
        case .deepSleepPercent:     return "Deep Sleep"
        case .remSleepPercent:      return "REM Sleep"
        case .awakeningsPerHour:    return "Disturbance"
        case .wristTemperature:     return "Wrist Temperature"
        case .overnightRespiratory: return "Respiratory Rate"
        case .overnightHRDip:       return "Overnight HR Dip"
        case .respiratoryRecovery:  return "Respiratory Recovery"
        case .acuteChronicRatio:    return "ACWR"
        case .trainingVolume:       return "Training Volume"
        case .activityCompletion:   return "Activity Completion"
        case .hrElevation:          return "HR Elevation"
        case .trainingIntensity:    return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        case .spo2:                 return "SpO2"
        }
    }
}

#if DEBUG
private struct SignalCardMapperPreviewHarness: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(sampleCards()) { card in
                    SignalExplanationCardView(model: card)
                }
            }
            .padding()
        }
        .background(HelixTheme.backgroundPrimary)
    }

    private func sampleCards() -> [SignalExplanationCardModel] {
        let policy = try! HelixPolicyLoader.load(
            filename: "helix_explanation_policy",
            as: HelixExplanationPolicy.self
        )
        let engine = HelixExplanationEngine(policy: policy)
        let mapper = SignalCardMapper(explanationEngine: engine)
        let now = Date()
        let contributions: [SignalContribution] = [
            SignalContribution(
                signal: .hrv,
                pointContribution: -12,
                explanation: "hrv.notable_drop",
                deltaDescription: "−18%"
            )
        ]
        let signals: [HelixSignal] = [
            HelixSignal(
                identifier: .hrv,
                rawValue: 42,
                unit: "ms",
                timestamp: now,
                baseline: 52,
                deltaFromBaseline: -0.19,
                normalizedScore: 58,
                isValid: true,
                isAnomaly: false
            )
        ]
        let strand = StrandScore(
            strand: .recovery,
            score: 64,
            componentSignals: signals,
            missingSignals: [.spo2],
            confidence: .medium,
            contributionBreakdown: contributions,
            primaryExplanation: "Recovery is in a stable range.",
            calculatedAt: now
        )
        return mapper.cards(for: strand)
    }
}

#Preview("Card Mapper") {
    SignalCardMapperPreviewHarness()
}
#endif
