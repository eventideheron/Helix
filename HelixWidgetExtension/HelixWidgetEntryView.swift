// HelixWidgetExtension/HelixWidgetEntryView.swift
// All widget surface views. Routes to the correct layout based on WidgetFamily.
// Uses PosturePresentation from SharedUI/Theme — no hardcoded colors.

import WidgetKit
import SwiftUI

struct HelixWidgetEntryView: View {
    let entry: HelixWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let record = entry.display {
            switch family {
            case .accessoryCircular:    CircularWidgetView(record: record)
            case .accessoryRectangular: RectangularWidgetView(record: record)
            case .systemSmall:          SmallWidgetView(record: record)
            default:                    MediumWidgetView(record: record)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ZStack {
            HelixTheme.backgroundPrimary
            VStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.body)
                    .foregroundColor(HelixTheme.textSecondary)
                Text("Open Helix")
                    .font(.caption2)
                    .foregroundColor(HelixTheme.textSecondary)
            }
        }
    }
}

// MARK: — Lock screen circular

struct CircularWidgetView: View {
    let record: HelixWidgetDisplayRecord
    private var color: Color { PosturePresentation(posture: record.posture).color }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Text("\(Int(record.helixIndex))")
                    .font(.system(size: 20, weight: .thin, design: .rounded))
                    .foregroundColor(color)
                Text(record.postureRaw.prefix(3))
                    .font(.system(size: 7, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(color.opacity(0.7))
            }
        }
    }
}

// MARK: — Lock screen rectangular

struct RectangularWidgetView: View {
    let record: HelixWidgetDisplayRecord
    private var color: Color { PosturePresentation(posture: record.posture).color }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(Int(record.helixIndex))")
                .font(.system(size: 28, weight: .thin, design: .rounded))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.postureRaw)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(color.opacity(0.8))
                HStack(spacing: 6) {
                    miniScore("S", record.sleepScore,    .cyan)
                    miniScore("L", record.loadScore,     .orange)
                    miniScore("R", record.recoveryScore, .green)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func miniScore(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 8)).foregroundColor(.gray)
            Text("\(Int(value))").font(.system(size: 9, weight: .light)).foregroundColor(color)
        }
    }
}

// MARK: — Home screen small

struct SmallWidgetView: View {
    let record: HelixWidgetDisplayRecord
    private var p: PosturePresentation { PosturePresentation(posture: record.posture) }

    var body: some View {
        ZStack {
            HelixTheme.backgroundSecondary
            VStack(spacing: 8) {
                Text("\(Int(record.helixIndex))")
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .foregroundColor(p.color)
                Text(record.postureRaw)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(3)
                    .foregroundColor(p.color.opacity(0.7))
            }
        }
    }
}

// MARK: — Home screen medium

struct MediumWidgetView: View {
    let record: HelixWidgetDisplayRecord
    private var p: PosturePresentation { PosturePresentation(posture: record.posture) }

    var body: some View {
        ZStack {
            HelixTheme.backgroundSecondary
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(Int(record.helixIndex))")
                        .font(.system(size: 52, weight: .thin, design: .rounded))
                        .foregroundColor(p.color)
                    Text(record.postureRaw)
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(3)
                        .foregroundColor(p.color.opacity(0.7))
                }
                VStack(alignment: .leading, spacing: 10) {
                    strandRow("SLEEP",    record.sleepScore,    .cyan)
                    strandRow("LOAD",     record.loadScore,     .orange)
                    strandRow("RECOVERY", record.recoveryScore, .green)
                }
            }
            .padding()
        }
    }

    private func strandRow(_ label: String, _ score: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9))
                .tracking(1)
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .leading)
            Text("\(Int(score))")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(color)
        }
    }
}
