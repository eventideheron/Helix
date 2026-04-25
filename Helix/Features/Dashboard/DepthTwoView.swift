// Views/Depth2/DepthTwoView.swift
// Three spoke triangle view. Each StrandRow is tappable — leads to Depth 3.

import SwiftUI

struct DepthTwoView: View {
    let index: HelixIndex
    let onStrandTap: (HelixStrand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Int(index.score))")
                .font(.system(size: 56, weight: .thin))
                .foregroundColor(HelixTheme.textPrimary)
                .padding(.bottom, 8)
            PostureLabel(posture: index.posture)
                .padding(.bottom, 24)

            VStack(spacing: 12) {
                StrandRow(strand: index.sleepStrand,    color: HelixTheme.sleepColor)    { onStrandTap(.sleep) }
                StrandRow(strand: index.loadStrand,     color: HelixTheme.loadColor)     { onStrandTap(.load) }
                StrandRow(strand: index.recoveryStrand, color: HelixTheme.recoveryColor) { onStrandTap(.recovery) }
            }
            .padding(.horizontal, 24)

            if index.balancePenalty > 2 {
                balancePenaltyNotice
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    private var balancePenaltyNotice: some View {
        Text("Balance penalty −\(Int(index.balancePenalty)) pts")
            .font(.caption2)
            .foregroundColor(HelixTheme.textSecondary)
            .padding(.top, 16)
    }
}

struct StrandRow: View {
    let strand: StrandScore
    let color:  Color
    let onTap:  () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(strandLabel)
                    .font(.caption)
                    .foregroundColor(HelixTheme.textSecondary)
                    .frame(width: 80, alignment: .leading)
                Spacer()
                if strand.confidence == .low {
                    Text("—")
                        .font(.title2.weight(.light))
                        .foregroundColor(HelixTheme.textSecondary)
                } else {
                    Text("\(Int(strand.score))")
                        .font(.title2.weight(.light))
                        .foregroundColor(color)
                }
                ConfidenceIndicator(confidence: strand.confidence)
                    .padding(.leading, 8)
                Image(systemName: "chevron.right")
                    .foregroundColor(HelixTheme.textSecondary)
                    .font(.caption)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(HelixTheme.backgroundSecondary)
            .cornerRadius(12)
        }
    }

    private var strandLabel: String { strand.strand.displayLabel.uppercased() }
}
