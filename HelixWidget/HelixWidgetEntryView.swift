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
            case .accessoryCircular:
                CircularWidgetView(record: record)
                    .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            case .accessoryRectangular:
                RectangularWidgetView(record: record)
                    .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            case .systemSmall:
                SmallWidgetView(record: record)
                    .containerBackground(for: .widget) { Color.black }
            default:
                MediumWidgetView(record: record)
                    .containerBackground(for: .widget) { Color.black }
            }
        } else {
            emptyState
                .containerBackground(for: .widget) { Color.black }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.body)
                .foregroundColor(.gray)
            Text("Open Helix")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}

// MARK: — Lock screen circular

struct CircularWidgetView: View {
    let record: HelixWidgetDisplayRecord
    private var color: Color { PosturePresentation(posture: record.posture).color }

    var body: some View {
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
        HelixWidgetInstrumentView(
            helixIndex:       record.helixIndex,
            posture:          record.postureRaw,
            sleepFraction:    record.sleepScore    / 100.0,
            loadFraction:     record.loadScore     / 100.0,
            recoveryFraction: record.recoveryScore / 100.0,
            tint:             p.color
        )
        .clipShape(Circle())
    }
}

// MARK: — Home screen medium

struct MediumWidgetView: View {
    let record: HelixWidgetDisplayRecord
    private var p: PosturePresentation { PosturePresentation(posture: record.posture) }

    var body: some View {
        HStack(spacing: 12) {
            HelixWidgetInstrumentView(
                helixIndex:       record.helixIndex,
                posture:          record.postureRaw,
                sleepFraction:    record.sleepScore    / 100.0,
                loadFraction:     record.loadScore     / 100.0,
                recoveryFraction: record.recoveryScore / 100.0,
                tint:             p.color
            )
            .clipShape(Circle())
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                strandRow(label: "SLEEP",    score: record.sleepScore,    color: HelixWidgetInstrumentView.sleepColor)
                strandRow(label: "LOAD",     score: record.loadScore,     color: HelixWidgetInstrumentView.loadColor)
                strandRow(label: "RECOVERY", score: record.recoveryScore, color: HelixWidgetInstrumentView.recoveryColor)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private func strandRow(label: String, score: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .semibold))
                .tracking(2)
                .foregroundColor(color.opacity(0.7))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                        .frame(height: 3)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * score / 100.0, height: 3)
                }
            }
            .frame(height: 3)
            Text("\(Int(score))")
                .font(.system(size: 16, weight: .thin, design: .rounded))
                .foregroundColor(color)
        }
    }
}
