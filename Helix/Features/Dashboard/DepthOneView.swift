import SwiftUI

struct DepthOneView: View {
    let index: HelixIndex
    let namespace: Namespace.ID
    let onTap: () -> Void

    private var posturePresentation: PosturePresentation {
        PosturePresentation(posture: index.posture)
    }

    private var confidencePresentation: ConfidencePresentation {
        ConfidencePresentation(level: index.overallConfidence)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Spatial anchor: same 300×8 frame as D3; ghost + overlay use HelixDashboardAnchorMetrics.helixCenterPoint (matches DepthThreeRadar).
                ZStack {
                    DepthOneGhostRadarView(
                        index: index,
                        tint: posturePresentation.color
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: HelixDashboardAnchorMetrics.chartHeight)
                    .padding(.horizontal, HelixDashboardAnchorMetrics.chartHorizontalPadding)
                    .matchedGeometryEffect(id: "helixRadar", in: namespace)
                    .opacity(0.58)

                    DepthOneRadarCenterOverlay(
                        index: index,
                        namespace: namespace,
                        style: .hero
                    )
                }
                .frame(height: HelixDashboardAnchorMetrics.chartHeight)
                .frame(maxWidth: .infinity)

                Spacer()
                    .frame(height: max(16, geo.size.height * 0.04))

                ConfidenceIndicator(confidence: index.overallConfidence, style: .labeledChip)
                    .scaleEffect(1.18)

                if index.recoveryGateApplied {
                    DepthOneRecoveryGateNotice()
                        .padding(.top, 16)
                }

                Spacer(minLength: 12)

                Text("tap to explore >")
                    .font(.system(size: 12, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(HelixTheme.textPrimary)
                    .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HelixTheme.backgroundPrimary)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct DepthOneConfidenceRow: View {
    let confidence: ConfidenceLevel

    private var presentation: ConfidencePresentation {
        ConfidencePresentation(level: confidence)
    }

    private var filledCount: Int {
        switch confidence {
        case .high:
            return 3
        case .medium:
            return 2
        case .low:
            return 1
        @unknown default:
            return 1
        }
    }

    private var label: String {
        switch confidence {
        case .high:
            return "ALL SIGNALS PRESENT"
        case .medium:
            return "ESTIMATED"
        case .low:
            return "LOW DATA"
        @unknown default:
            return "LOW DATA"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i <= filledCount ? presentation.color : HelixTheme.textSecondary.opacity(0.20))
                    .frame(width: 5, height: 5)
                    .shadow(
                        color: i <= filledCount ? presentation.color.opacity(0.60) : .clear,
                        radius: 3
                    )
            }

            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(presentation.color.opacity(0.78))
        }
    }
}

private struct DepthOneRecoveryGateNotice: View {
    var body: some View {
        Text("Recovery gate active")
            .font(.system(size: 10, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(HelixTheme.restoreColor.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(HelixTheme.restoreColor.opacity(0.30), lineWidth: 1)
            )
    }
}

// MARK: — Depth 1 center anchor (matches `DepthThreeRadar` / `HelixDashboardAnchorMetrics.helixCenterPoint`)

enum DepthOneIndexOverlayStyle {
    /// Monolithic `DepthOneView` (large index).
    case hero
    /// Live dashboard `SharedRadarView` (matches Depth 2–3 header scale for `matchedGeometryEffect`).
    case compact
}

private struct DepthOneScoreHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DepthOnePostureHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Positions posture above the Helix Index; index glyph center sits on `helixCenterPoint` (same as D3 radar circle center).
struct DepthOneRadarCenterOverlay: View {
    let index: HelixIndex
    let namespace: Namespace.ID
    let style: DepthOneIndexOverlayStyle

    @State private var scoreHeight: CGFloat = 0
    @State private var postureHeight: CGFloat = 0

    private var posturePresentation: PosturePresentation {
        PosturePresentation(posture: index.posture)
    }

    private var stackSpacing: CGFloat { 8 }

    private var fallbackScoreHeight: CGFloat {
        switch style {
        case .hero: return 116
        case .compact: return 64
        }
    }

    private var fallbackPostureHeight: CGFloat { 22 }

    var body: some View {
        GeometryReader { geo in
            let center = HelixDashboardAnchorMetrics.helixCenterPoint(in: geo.size)
            let sh = scoreHeight > 1 ? scoreHeight : fallbackScoreHeight
            let ph = postureHeight > 1 ? postureHeight : fallbackPostureHeight

            ZStack {
                Text("\(Int(index.score.rounded()))")
                    .font(.system(size: style == .hero ? 108 : 56, weight: .thin, design: .rounded))
                    .tracking(style == .hero ? -4 : -2)
                    .foregroundColor(posturePresentation.color)
                    .shadow(
                        color: posturePresentation.color.opacity(style == .hero ? 0.30 : 0.22),
                        radius: style == .hero ? 28 : 14
                    )
                    .matchedGeometryEffect(id: "helixIndexScore", in: namespace)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: DepthOneScoreHeightKey.self, value: g.size.height)
                        }
                    )
                    .position(center)

                DepthTwoPosturePill(posture: index.posture)
                    .matchedGeometryEffect(id: "helixPosturePill", in: namespace)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: DepthOnePostureHeightKey.self, value: g.size.height)
                        }
                    )
                    .position(
                        x: center.x,
                        y: center.y - sh / 2 - stackSpacing - ph / 2
                    )
            }
            .onPreferenceChange(DepthOneScoreHeightKey.self) { scoreHeight = $0 }
            .onPreferenceChange(DepthOnePostureHeightKey.self) { postureHeight = $0 }
        }
    }
}

struct DepthOneGhostRadarView: View {
    let index: HelixIndex
    let tint: Color

    private var sleepFraction: Double {
        min(max(index.sleepStrand.score / 100.0, 0.0), 1.0)
    }

    private var loadFraction: Double {
        min(max(index.loadStrand.score / 100.0, 0.0), 1.0)
    }

    private var recoveryFraction: Double {
        min(max(index.recoveryStrand.score / 100.0, 0.0), 1.0)
    }

    var body: some View {
        Canvas { context, size in
            let center = HelixDashboardAnchorMetrics.helixCenterPoint(in: size)
            let radius = HelixDashboardAnchorMetrics.radarOuterRadius(in: size)
            let angles: [Double] = [-90, 30, 150]

            for fraction in [0.66, 0.33] {
                let ringRadius = radius * fraction
                let rect = CGRect(
                    x: center.x - ringRadius,
                    y: center.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                )

                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(HelixTheme.textSecondary.opacity(0.18)),
                    lineWidth: 0.5
                )
            }

            strokeSegmentedStrandOuterRing(
                context: &context,
                center: center,
                radius: radius,
                lineWidth: 1.0
            )

            for angle in angles {
                let radians = angle * .pi / 180
                let endpoint = CGPoint(
                    x: center.x + radius * cos(radians),
                    y: center.y + radius * sin(radians)
                )

                var line = Path()
                line.move(to: center)
                line.addLine(to: endpoint)

                context.stroke(
                    line,
                    with: .color(HelixTheme.textSecondary.opacity(0.18)),
                    lineWidth: 0.5
                )
            }

            let values = [sleepFraction, loadFraction, recoveryFraction]
            var polygon = Path()

            for (i, value) in values.enumerated() {
                let radians = angles[i] * .pi / 180
                let point = CGPoint(
                    x: center.x + radius * value * cos(radians),
                    y: center.y + radius * value * sin(radians)
                )

                if i == 0 {
                    polygon.move(to: point)
                } else {
                    polygon.addLine(to: point)
                }
            }

            polygon.closeSubpath()

            context.fill(polygon, with: .color(tint.opacity(0.08)))
            context.stroke(polygon, with: .color(tint.opacity(0.30)), lineWidth: 1.2)

        }
        .opacity(0.55)
    }
}

/// Sleep / load / recovery pillar sectors (120° each, boundaries at strand midlines between -90°, 30°, 150°).
private func strokeSegmentedStrandOuterRing(
    context: inout GraphicsContext,
    center: CGPoint,
    radius: CGFloat,
    lineWidth: CGFloat
) {
    let segments: [(start: Double, end: Double, color: Color)] = [
        (-150, -30, HelixTheme.sleepColor),
        (-30, 90, HelixTheme.loadColor),
        (90, 210, HelixTheme.recoveryColor)
    ]
    for seg in segments {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(seg.start),
            endAngle: .degrees(seg.end),
            clockwise: false
        )
        context.stroke(
            path,
            with: .color(seg.color.opacity(0.55)),
            lineWidth: lineWidth
        )
    }
}

// MARK: — Depth 1 bottom content zone

struct DepthOneBottomContent: View {
    let index: HelixIndex
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ConfidenceIndicator(confidence: index.overallConfidence, style: .labeledChip)
                .scaleEffect(1.18)
                .padding(.top, 12)
                .padding(.bottom, 22)

            if index.recoveryGateApplied {
                DepthOneRecoveryGateNotice()
                    .padding(.bottom, 16)
            }

            Text("tap to explore >")
                .font(.system(size: 12, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(HelixTheme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct DepthOnePreviewShell: View {
    @Namespace private var ns
    var body: some View {
        DepthOneView(index: HelixPreviewSample.index, namespace: ns) { }
            .background(HelixTheme.backgroundPrimary)
    }
}

#Preview("Depth 1") {
    DepthOnePreviewShell()
}
