// Views/Depth1/DepthOneView.swift
// 3-second morning glance. Score, posture word, confidence dots, tap to go deeper.

import SwiftUI

struct DepthOneView: View {
    let index: HelixIndex
    let onTap: () -> Void

    private var presentation: PosturePresentation { PosturePresentation(posture: index.posture) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("\(Int(index.score))")
                .font(.system(size: 96, weight: .thin, design: .rounded))
                .foregroundColor(presentation.color)
            PostureLabel(posture: index.posture)
            ConfidenceIndicator(confidence: index.overallConfidence)
            if index.recoveryGateApplied {
                recoveryGateNotice
            }
            Text("Tap to explore")
                .font(.caption)
                .foregroundColor(HelixTheme.textSecondary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var recoveryGateNotice: some View {
        Text("Recovery gate active")
            .font(.caption2)
            .foregroundColor(HelixTheme.restoreColor.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(HelixTheme.restoreColor.opacity(0.4), lineWidth: 0.5))
    }
}
