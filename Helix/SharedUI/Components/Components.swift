// SharedUI/Components/ConfidenceIndicator.swift

import SwiftUI

struct ConfidenceIndicator: View {
    enum DisplayStyle: Equatable {
        /// Default: `●●● Confident` style chip (Depth 3, decomposition, etc.).
        case labeledChip
        /// Triple dots only, existing colors — Depth 2 pillar rows only.
        case dotsOnly
    }

    let confidence: ConfidenceLevel
    var style: DisplayStyle = .labeledChip

    private var p: ConfidencePresentation { ConfidencePresentation(level: confidence) }

    var body: some View {
        switch style {
        case .labeledChip:
            Text(p.indicator)
                .font(HelixTypography.confidenceLabel)
                .foregroundColor(p.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(p.color.opacity(0.5), lineWidth: 0.5)
                )
        case .dotsOnly:
            HStack(spacing: 5) {
                ForEach(1...3, id: \.self) { i in
                    Circle()
                        .fill(i <= p.filledDotCount ? p.color : HelixTheme.textSecondary.opacity(0.20))
                        .frame(width: 5, height: 5)
                        .shadow(
                            color: i <= p.filledDotCount ? p.color.opacity(0.55) : .clear,
                            radius: 3
                        )
                }
            }
            .accessibilityLabel("Confidence indicator, \(p.filledDotCount) of three")
        }
    }
}

// SharedUI/Components/PostureLabel.swift

struct PostureLabel: View {
    let posture: HelixPosture
    private var p: PosturePresentation { PosturePresentation(posture: posture) }

    var body: some View {
        Text(p.headline)
            .font(HelixTypography.postureLabel)
            .tracking(HelixTracking.postureWord)
            .foregroundColor(p.color.opacity(0.8))
    }
}

// SharedUI/Components/StrandRow.swift
// Used in DepthTwoView. Extracted per ChatGPT one-file-per-component recommendation.

struct StrandRow: View {
    let strand: StrandScore
    let color:  Color
    let onTap:  () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Subtle left accent in strand color
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.6))
                        .frame(width: 4)
                        .padding(.trailing, 12)
                    HStack {
                        Text(strand.strand.displayLabel.uppercased())
                            .font(HelixTypography.strandLabel)
                            .foregroundColor(HelixTheme.textSecondary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Text("\(Int(strand.score))")
                            .font(HelixTypography.scoreSmall)
                            .foregroundColor(color)
                        ConfidenceIndicator(confidence: strand.confidence)
                            .padding(.leading, 8)
                        Image(systemName: "chevron.right")
                            .foregroundColor(HelixTheme.textSecondary)
                            .font(.caption)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                }
                .padding(.leading, 20)
                // Thin progress bar in strand color
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        HelixTheme.textSecondary.opacity(0.2)
                            .frame(height: 2)
                        color
                            .frame(width: max(0, geo.size.width * (strand.score / 100)), height: 2)
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .background(HelixTheme.backgroundSecondary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(HelixTheme.borderSubtle, lineWidth: 1)
            )
        }
    }
}

// SharedUI/Components/DecompositionPanel.swift
// Full signal breakdown panel, usable in both DepthThreeView and future History detail.

struct DecompositionPanel: View {
    let contributions: [SignalContribution]
    let missingSignals: [SignalIdentifier]
    let confidence: ConfidenceLevel
    let strandColor: Color
    let maxContributors: Int

    @State private var expandedSignal: SignalIdentifier? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !missingSignals.isEmpty {
                missingSignalsRow
                    .padding(.bottom, 12)
            }

            Text("SIGNAL BREAKDOWN")
                .font(HelixTypography.microLabel)
                .tracking(HelixTracking.sectionHeader)
                .foregroundColor(HelixTheme.textSecondary)
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                ForEach(contributions.prefix(maxContributors), id: \.signal) { contribution in
                    SignalContributionRow(
                        contribution: contribution,
                        isExpanded: expandedSignal == contribution.signal,
                        color: strandColor
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedSignal = expandedSignal == contribution.signal
                                ? nil : contribution.signal
                        }
                    }
                }
            }
        }
    }

    private var missingSignalsRow: some View {
        HStack(spacing: 8) {
            ConfidenceIndicator(confidence: confidence)
            Text("Missing: \(missingSignals.map(\.displayLabel).joined(separator: ", "))")
                .font(HelixTypography.captionBody)
                .foregroundColor(HelixTheme.textSecondary)
        }
    }
}

// MARK: — Signal contribution row (used inside DecompositionPanel)

struct SignalContributionRow: View {
    let contribution:      SignalContribution
    let isExpanded:       Bool
    let color:            Color
    var explanationEngine: HelixExplanationEngine? = nil
    let onTap:            () -> Void

    private var displayExplanation: String {
        guard let engine = explanationEngine else { return contribution.explanation }
        return engine.resolveForDisplay(contribution.explanation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Text(contribution.signal.displayLabel)
                        .font(HelixTypography.signalLabel)
                        .foregroundColor(HelixTheme.textPrimary)
                    Spacer()
                    if !contribution.deltaDescription.isEmpty {
                        Text(contribution.deltaDescription)
                            .font(.caption2)
                            .foregroundColor(HelixTheme.textSecondary)
                    }
                    Text(pointString)
                        .font(HelixTypography.signalLabel.weight(.light))
                        .foregroundColor(pointColor)
                        .frame(width: 44, alignment: .trailing)
                    // Depth 3 vNext: dot cluster mirrors chevron — same tap target (expand/collapse).
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(HelixTheme.textSecondary.opacity(0.38))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .accessibilityHidden(true)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(HelixTheme.textSecondary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(HelixTheme.backgroundSecondary)
                .cornerRadius(isExpanded ? 0 : 10)
                .cornerRadius(isExpanded ? 10 : 10, corners: [.topLeft, .topRight])
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(displayExplanation)
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HelixTheme.surfaceSecondary.opacity(0.6))
                    .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
            }
        }
    }

    private var pointString: String {
        let pts = contribution.pointContribution
        return pts >= 0 ? "+\(Int(pts))" : "\(Int(pts))"
    }

    private var pointColor: Color {
        contribution.pointContribution >= 0 ? color : HelixTheme.restoreColor
    }
}

// MARK: — Corner radius shape helper (shared)

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius:  CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
