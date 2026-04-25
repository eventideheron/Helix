// Views/Depth3/DepthThreeView.swift
// Full signal breakdown for a selected strand. Tapping any signal shows its explanation.

import SwiftUI

struct DepthThreeView: View {
    let index:          HelixIndex
    let selectedStrand: HelixStrand?
    @State private var expandedSignal: SignalIdentifier? = nil

    private var strand: StrandScore {
        switch selectedStrand {
        case .sleep:    return index.sleepStrand
        case .load:     return index.loadStrand
        case .recovery: return index.recoveryStrand
        case nil:       return index.recoveryStrand
        }
    }

    private var strandColor: Color {
        StrandPresentation(strand: strand.strand).color
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Strand header
                HStack {
                    Text(strand.strand.displayLabel.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(3)
                        .foregroundColor(strandColor)
                    Spacer()
                    Text("\(Int(strand.score))")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundColor(strandColor)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Primary explanation
                Text(strand.primaryExplanation)
                    .font(.subheadline)
                    .foregroundColor(HelixTheme.textPrimary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                // Confidence + missing signals
                ConfidenceRow(strand: strand)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                // Signal contribution rows
                if !strand.contributionBreakdown.isEmpty {
                    Text("SIGNAL BREAKDOWN")
                        .font(.system(size: 10))
                        .tracking(2)
                        .foregroundColor(HelixTheme.textSecondary)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 8) {
                        ForEach(strand.contributionBreakdown.prefix(5), id: \.signal) { contribution in
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
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

// MARK: — Confidence row

struct ConfidenceRow: View {
    let strand: StrandScore

    var body: some View {
        HStack(spacing: 8) {
            ConfidenceIndicator(confidence: strand.confidence)
            if !strand.missingSignals.isEmpty {
                Text(missingText)
                    .font(.caption2)
                    .foregroundColor(HelixTheme.textSecondary)
            }
        }
    }

    private var missingText: String {
        let labels = strand.missingSignals.map(\.displayLabel)
        return "Missing: \(labels.joined(separator: ", "))"
    }
}

// MARK: — Signal contribution row

struct SignalContributionRow: View {
    let contribution: SignalContribution
    let isExpanded:   Bool
    let color:        Color
    let onTap:        () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(contribution.signal.displayLabel)
                        .font(.subheadline)
                        .foregroundColor(HelixTheme.textPrimary)
                    Spacer()
                    if !contribution.deltaDescription.isEmpty {
                        Text(contribution.deltaDescription)
                            .font(.caption2)
                            .foregroundColor(HelixTheme.textSecondary)
                    }
                    Text(pointString)
                        .font(.subheadline.weight(.light))
                        .foregroundColor(pointColor)
                        .frame(width: 44, alignment: .trailing)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(HelixTheme.textSecondary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(HelixTheme.backgroundSecondary)
                .cornerRadius(isExpanded ? 0 : 10)
                .cornerRadius(isExpanded ? 10 : 10, corners: [.topLeft, .topRight])
            }

            if isExpanded {
                Text(contribution.explanation)
                    .font(.caption)
                    .foregroundColor(HelixTheme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
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

// MARK: — Corner radius helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
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
