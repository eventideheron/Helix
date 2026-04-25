// Features/History/HistoryView.swift
// Longitudinal view — Today In History cards, trend arrows, milestone messages,
// and eventually the historical helix spiral visualisation (Tier 3).
//
// Activated from the dashboard after 90 days of data.
// Requires HelixHistoryEngine output passed from HelixViewModel.

import SwiftUI
import SwiftData

struct HistoryView: View {

    let historyResult: HistoryResult
    let allRecords:    [HelixDailyRecord]
    let trendArrow:    TrendDirection

    var body: some View {
        ZStack {
            HelixTheme.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    // Today In History card
                    if let message = historyResult.todayInHistoryMessage {
                        TodayInHistoryCard(message: message, triggerType: historyResult.triggerType)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }

                    // Seasonal warning
                    if let seasonal = historyResult.seasonalWarning {
                        SeasonalWarningCard(message: seasonal)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }

                    // Trend section
                    TrendSection(records: allRecords, arrow: trendArrow)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // 30-day sparklines placeholder
                    SparklineSection(records: allRecords)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Milestone message
                    if let milestone = historyResult.milestoneMessage {
                        MilestoneCard(message: milestone)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                    }

                    // Historical helix visualisation — Tier 3
                    HelixVisualisationPlaceholder()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
                .padding(.top, 20)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HISTORY")
                .font(HelixTypography.microLabel)
                .tracking(HelixTracking.sectionHeader)
                .foregroundColor(HelixTheme.textSecondary)
            Text("\(allRecords.count) days of data")
                .font(.system(size: 28, weight: .thin))
                .foregroundColor(HelixTheme.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}

// MARK: — Today In History card

struct TodayInHistoryCard: View {
    let message:     String
    let triggerType: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(HelixTheme.pursueColor)
                Text("TODAY IN HISTORY")
                    .font(HelixTypography.microLabel)
                    .tracking(HelixTracking.sectionHeader)
                    .foregroundColor(HelixTheme.pursueColor)
            }
            Text(message)
                .font(HelixTypography.explanationBody)
                .foregroundColor(HelixTheme.textPrimary)
        }
        .padding(16)
        .background(HelixTheme.pursueColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(HelixTheme.pursueColor.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(12)
    }
}

// MARK: — Seasonal warning card

struct SeasonalWarningCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundColor(HelixTheme.moderateColor)
                Text("SEASONAL PATTERN")
                    .font(HelixTypography.microLabel)
                    .tracking(HelixTracking.sectionHeader)
                    .foregroundColor(HelixTheme.moderateColor)
            }
            Text(message)
                .font(HelixTypography.explanationBody)
                .foregroundColor(HelixTheme.textPrimary)
        }
        .padding(16)
        .background(HelixTheme.moderateColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(HelixTheme.moderateColor.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(12)
    }
}

// MARK: — Trend section

struct TrendSection: View {
    let records: [HelixDailyRecord]
    let arrow:   TrendDirection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("7-DAY TREND")
                .font(HelixTypography.microLabel)
                .tracking(HelixTracking.sectionHeader)
                .foregroundColor(HelixTheme.textSecondary)

            HStack(spacing: 16) {
                trendArrowView
                VStack(alignment: .leading, spacing: 4) {
                    Text(arrowLabel)
                        .font(HelixTypography.explanationBody)
                        .foregroundColor(HelixTheme.textPrimary)
                    Text("3-day weighted moving average")
                        .font(.caption2)
                        .foregroundColor(HelixTheme.textSecondary)
                }
            }
        }
    }

    private var trendArrowView: some View {
        Image(systemName: arrowIconName)
            .font(.system(size: 28, weight: .thin))
            .foregroundColor(arrowColor)
    }

    private var arrowIconName: String {
        switch arrow {
        case .up:   return "arrow.up.right"
        case .flat: return "arrow.right"
        case .down: return "arrow.down.right"
        }
    }

    private var arrowColor: Color {
        switch arrow {
        case .up:   return HelixTheme.confidenceHigh
        case .flat: return HelixTheme.textSecondary
        case .down: return HelixTheme.restoreColor
        }
    }

    private var arrowLabel: String {
        switch arrow {
        case .up:   return "Helix Index trending up"
        case .flat: return "Helix Index stable"
        case .down: return "Helix Index trending down"
        }
    }
}

// MARK: — Sparkline section (30-day scores)

struct SparklineSection: View {
    let records: [HelixDailyRecord]

    private var last30: [HelixDailyRecord] {
        Array(records.sorted { $0.date < $1.date }.suffix(30))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("30 DAYS")
                .font(HelixTypography.microLabel)
                .tracking(HelixTracking.sectionHeader)
                .foregroundColor(HelixTheme.textSecondary)

            if last30.count >= 7 {
                SparklineChart(records: last30)
                    .frame(height: 60)
            } else {
                Text("Accumulating data…")
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.textSecondary)
                    .frame(height: 60)
            }
        }
    }
}

struct SparklineChart: View {
    let records: [HelixDailyRecord]

    var body: some View {
        GeometryReader { geo in
            let scores  = records.map(\.helixIndex)
            let minVal  = scores.min() ?? 0
            let maxVal  = max(scores.max() ?? 100, minVal + 1)
            let range   = maxVal - minVal
            let width   = geo.size.width
            let height  = geo.size.height
            let step    = width / CGFloat(max(records.count - 1, 1))

            Path { path in
                for (i, score) in scores.enumerated() {
                    let x = CGFloat(i) * step
                    let y = height - CGFloat((score - minVal) / range) * height
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else       { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(HelixTheme.pursueColor.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: — Milestone card

struct MilestoneCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.title3)
                .foregroundColor(HelixTheme.recoveryColor)
            Text(message)
                .font(HelixTypography.captionBody)
                .foregroundColor(HelixTheme.textSecondary)
        }
        .padding(14)
        .background(HelixTheme.backgroundSecondary)
        .cornerRadius(10)
    }
}

// MARK: — Historical helix visualisation placeholder (Tier 3)

struct HelixVisualisationPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.system(size: 32))
                .foregroundColor(HelixTheme.textSecondary.opacity(0.4))
            Text("Historical helix visualisation")
                .font(HelixTypography.captionBody)
                .foregroundColor(HelixTheme.textSecondary.opacity(0.5))
            Text("Tier 3")
                .font(.caption2)
                .foregroundColor(HelixTheme.textSecondary.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}
