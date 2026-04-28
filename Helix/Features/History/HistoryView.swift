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

                    // Seasonal warning (prior-year window; provisional vs confirmed context from policy)
                    if let seasonal = historyResult.seasonalWarning {
                        SeasonalWarningCard(
                            contextLine: historyResult.seasonalContextLine,
                            message: seasonal
                        )
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

                    // Triple Helix braid chart — Tier 3
                    TripleHelixBraidSection(records: allRecords)
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
            Text("\(allRecords.count) day\(allRecords.count == 1 ? "" : "s") recorded")
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
    let contextLine: String?
    let message:     String

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
            if let contextLine {
                Text(contextLine)
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.textSecondary)
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

// MARK: — Triple Helix braid visualisation (Tier 3)

struct TripleHelixBraidSection: View {
    let records: [HelixDailyRecord]

    private var sorted: [HelixDailyRecord] {
        records.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TRIPLE HELIX")
                    .font(HelixTypography.microLabel)
                    .tracking(HelixTracking.sectionHeader)
                    .foregroundColor(HelixTheme.textSecondary)

                Spacer()

                if let first = sorted.first, let last = sorted.last {
                    Text(dateRangeLabel(from: first.date, to: last.date))
                        .font(.caption2)
                        .foregroundColor(HelixTheme.textSecondary.opacity(0.55))
                }
            }

            if sorted.count >= 14 {
                TripleHelixBraidChart(records: sorted)
                    .frame(height: 140)
            } else {
                Text("Accumulating data…")
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.textSecondary)
                    .frame(height: 140)
            }

            HStack(spacing: 16) {
                StrandLegendDot(color: HelixTheme.sleepColor, label: "Sleep")
                StrandLegendDot(color: HelixTheme.loadColor, label: "Load")
                StrandLegendDot(color: HelixTheme.recoveryColor, label: "Recovery")
            }
        }
    }

    private func dateRangeLabel(from start: Date, to end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let startStr = formatter.string(from: start)
        formatter.dateFormat = "MMM yyyy"
        let endStr = formatter.string(from: end)
        return "\(startStr) – \(endStr)"
    }
}

struct TripleHelixBraidChart: View {
    let records: [HelixDailyRecord]

    var body: some View {
        Canvas { context, size in
            let count = records.count
            guard count >= 2 else { return }

            let width      = size.width
            let height     = size.height
            let topPad: CGFloat    = 12
            let bottomPad: CGFloat = 12
            let drawHeight = height - topPad - bottomPad
            let step       = width / CGFloat(count - 1)

            func yPos(_ score: Double) -> CGFloat {
                let clamped = min(max(score, 0), 100)
                return topPad + drawHeight * CGFloat(1.0 - clamped / 100.0)
            }

            func buildPath(points: [(index: Int, score: Double)]) -> Path {
                var path = Path()
                for (i, point) in points.enumerated() {
                    let x = CGFloat(point.index) * step
                    let y = yPos(point.score)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else       { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                return path
            }

            let liveRecords = records.filter { $0.appStateRaw != "historicalBackfill" }
            let sleepPoints = liveRecords.enumerated().map { (index: $0.offset, score: $0.element.sleepScore) }
            let recoveryPoints = liveRecords.enumerated().map { (index: $0.offset, score: $0.element.recoveryScore) }
            let loadPoints = liveRecords.enumerated().map { (index: $0.offset, score: $0.element.loadScore) }

            let sleepPath = buildPath(points: sleepPoints)
            let recoveryPath = buildPath(points: recoveryPoints)
            let loadPath = buildPath(points: loadPoints)

            // Sleep — Indigo (back)
            context.stroke(sleepPath,
                with: .color(HelixTheme.sleepColor.opacity(0.25)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            context.stroke(sleepPath,
                with: .color(HelixTheme.sleepColor.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Recovery — Emerald (middle)
            context.stroke(recoveryPath,
                with: .color(HelixTheme.recoveryColor.opacity(0.25)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            context.stroke(recoveryPath,
                with: .color(HelixTheme.recoveryColor.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Load — Cyan (front), suppress backfilled rows
            if loadPoints.count >= 2 {
                context.stroke(loadPath,
                    with: .color(HelixTheme.loadColor.opacity(0.25)),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                context.stroke(loadPath,
                    with: .color(HelixTheme.loadColor.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }

            drawMonthMarkers(
                context: &context,
                records: records,
                step: step,
                height: height,
                topPad: topPad
            )
        }
    }

    private func drawMonthMarkers(
        context: inout GraphicsContext,
        records: [HelixDailyRecord],
        step: CGFloat,
        height: CGFloat,
        topPad: CGFloat
    ) {
        let calendar = Calendar.current
        var lastMonth = -1

        for (i, record) in records.enumerated() {
            let month = calendar.component(.month, from: record.date)
            if month != lastMonth && lastMonth != -1 {
                let x = CGFloat(i) * step
                var line = Path()
                line.move(to: CGPoint(x: x, y: topPad))
                line.addLine(to: CGPoint(x: x, y: height))
                context.stroke(
                    line,
                    with: .color(HelixTheme.textSecondary.opacity(0.10)),
                    lineWidth: 0.5
                )

                let formatter = DateFormatter()
                formatter.dateFormat = "MMM"
                context.draw(
                    Text(formatter.string(from: record.date))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(HelixTheme.textSecondary.opacity(0.35)),
                    at: CGPoint(x: x + 6, y: height - 8)
                )
            }
            lastMonth = month
        }
    }
}

private struct StrandLegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(HelixTheme.textSecondary.opacity(0.7))
        }
    }
}
