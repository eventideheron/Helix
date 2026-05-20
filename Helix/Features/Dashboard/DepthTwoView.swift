import SwiftUI
import Foundation

private enum DepthTwoLayout {
    /// Between Depth 1 (108) and Depth 3 strand header (~34).
    static let indexFontSize: CGFloat = 36
    /// Top band: anchor chart height + room for upper-left cluster (spec v3).
    static let topSectionMinHeight: CGFloat = HelixDashboardAnchorMetrics.chartHeight + 28
}

private enum DepthTwoRadarDrawing {
    static func strokeSegmentedStrandOuterRing(
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
                with: .color(seg.color.opacity(0.58)),
                lineWidth: lineWidth
            )
        }
    }
}

struct DepthTwoView: View {
    let index: HelixIndex
    let crossStrandInsight: CrossStrandInsight?
    let namespace: Namespace.ID
    let onStrandTap: (HelixStrand) -> Void

    private var posturePresentation: PosturePresentation {
        PosturePresentation(posture: index.posture)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Upper-left: index + posture · Center: anchored chart (no positional shift vs D3 frame class).
                ZStack(alignment: .topLeading) {
                    HStack {
                        Spacer(minLength: 0)
                        DepthTwoTriangleRadar(index: index)
                            .frame(maxWidth: .infinity)
                            .frame(height: HelixDashboardAnchorMetrics.chartHeight)
                            .padding(.horizontal, HelixDashboardAnchorMetrics.chartHorizontalPadding)
                            .matchedGeometryEffect(id: "helixRadar", in: namespace)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        DepthTwoPosturePill(posture: index.posture)
                            .matchedGeometryEffect(id: "helixPosturePill", in: namespace)

                        Text("\(Int(index.score.rounded()))")
                            .font(.system(size: DepthTwoLayout.indexFontSize, weight: .thin, design: .rounded))
                            .tracking(-2)
                            .foregroundColor(posturePresentation.color)
                            .shadow(color: posturePresentation.color.opacity(0.22), radius: 14)
                            .matchedGeometryEffect(id: "helixIndexScore", in: namespace)
                    }
                    .padding(.leading, 18)
                    .padding(.top, 12)
                }
                .frame(minHeight: DepthTwoLayout.topSectionMinHeight)

                VStack(spacing: 10) {
                    DepthTwoStrandRow(
                        title: "SLEEP",
                        score: index.sleepStrand.score,
                        confidence: index.sleepStrand.confidence,
                        color: HelixTheme.sleepColor,
                        textColor: HelixTheme.sleepTextColor
                    ) {
                        onStrandTap(.sleep)
                    }

                    DepthTwoStrandRow(
                        title: "LOAD",
                        score: index.loadStrand.score,
                        confidence: index.loadStrand.confidence,
                        color: HelixTheme.loadColor,
                        textColor: HelixTheme.loadTextColor
                    ) {
                        onStrandTap(.load)
                    }

                    DepthTwoStrandRow(
                        title: "RECOVERY",
                        score: index.recoveryStrand.score,
                        confidence: index.recoveryStrand.confidence,
                        color: HelixTheme.recoveryColor,
                        textColor: HelixTheme.recoveryTextColor
                    ) {
                        onStrandTap(.recovery)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 26)

                if let insight = crossStrandInsight {
                    CrossStrandInsightBlock(insight: insight)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }

                if index.balancePenalty > 2 {
                    Text("Balance penalty -\(Int(index.balancePenalty.rounded())) pts")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(HelixTheme.textSecondary)
                        .padding(.top, 14)
                }

                Text("tap a pillar for breakdown >")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(HelixTheme.textSecondary.opacity(0.45))
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
        }
        .background(HelixTheme.backgroundPrimary)
    }
}

struct DepthTwoPosturePill: View {
    let posture: HelixPosture

    private var presentation: PosturePresentation {
        PosturePresentation(posture: posture)
    }

    var body: some View {
        Text(presentation.headline)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .tracking(3)
            .foregroundColor(presentation.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(presentation.color.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(presentation.color.opacity(0.28), lineWidth: 1)
            )
    }
}

struct DepthTwoTriangleRadar: View {
    let index: HelixIndex

    private var sleepValue: Double {
        min(max(index.sleepStrand.score / 100.0, 0.0), 1.0)
    }

    private var loadValue: Double {
        min(max(index.loadStrand.score / 100.0, 0.0), 1.0)
    }

    private var recoveryValue: Double {
        min(max(index.recoveryStrand.score / 100.0, 0.0), 1.0)
    }

    private var tint: Color {
        HelixTheme.color(for: index.posture)
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            let radius = min(size.width, size.height) * 0.34
            let angles: [Double] = [-90.0, 30.0, 150.0]

            // Inner rings (neutral)
            for fraction in [0.66, 0.33] {
                let ringRadius = radius * CGFloat(fraction)
                let rect = CGRect(
                    x: center.x - ringRadius,
                    y: center.y - ringRadius,
                    width: ringRadius * 2.0,
                    height: ringRadius * 2.0
                )

                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(HelixTheme.textSecondary.opacity(0.06)),
                    lineWidth: 0.5
                )
            }

            DepthTwoRadarDrawing.strokeSegmentedStrandOuterRing(
                context: &context,
                center: center,
                radius: radius,
                lineWidth: 1.15
            )

            // Strand sector hints (very light; posture fill carries principal read)
            drawSectorTint(
                context: &context,
                center: center,
                radius: radius,
                startAngle: -110.0,
                endAngle: -10.0,
                color: HelixTheme.sleepColor.opacity(0.028)
            )

            drawSectorTint(
                context: &context,
                center: center,
                radius: radius,
                startAngle: -10.0,
                endAngle: 110.0,
                color: HelixTheme.loadColor.opacity(0.022)
            )

            drawSectorTint(
                context: &context,
                center: center,
                radius: radius,
                startAngle: 110.0,
                endAngle: 250.0,
                color: HelixTheme.recoveryColor.opacity(0.028)
            )

            // Spokes
            let spokeColors: [Color] = [
                HelixTheme.sleepColor.opacity(0.22),
                HelixTheme.loadColor.opacity(0.22),
                HelixTheme.recoveryColor.opacity(0.22)
            ]

            for (i, angle) in angles.enumerated() {
                let radians = angle * Double.pi / 180.0
                let end = CGPoint(
                    x: center.x + radius * CGFloat(Foundation.cos(radians)),
                    y: center.y + radius * CGFloat(Foundation.sin(radians))
                )

                var line = Path()
                line.move(to: center)
                line.addLine(to: end)

                context.stroke(
                    line,
                    with: .color(spokeColors[i]),
                    lineWidth: 0.75
                )
            }

            // Polygon
            let values: [Double] = [sleepValue, loadValue, recoveryValue]
            var triangle = Path()
            var points: [CGPoint] = []

            for (i, value) in values.enumerated() {
                let radians = angles[i] * Double.pi / 180.0
                let point = CGPoint(
                    x: center.x + radius * CGFloat(value) * CGFloat(Foundation.cos(radians)),
                    y: center.y + radius * CGFloat(value) * CGFloat(Foundation.sin(radians))
                )
                points.append(point)

                if i == 0 {
                    triangle.move(to: point)
                } else {
                    triangle.addLine(to: point)
                }
            }

            triangle.closeSubpath()

            // Restraint posture-tinted interior (vNext)
            context.fill(triangle, with: .color(tint.opacity(0.085)))

            context.stroke(
                triangle,
                with: .color(tint.opacity(0.18)),
                lineWidth: 6
            )

            context.stroke(
                triangle,
                with: .color(tint.opacity(0.42)),
                lineWidth: 1.5
            )

            // Vertex dots
            let dotColors: [Color] = [
                HelixTheme.sleepColor,
                HelixTheme.loadColor,
                HelixTheme.recoveryColor
            ]

            for i in 0..<points.count {
                let point = points[i]
                let color = dotColors[i]

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - 10.0,
                        y: point.y - 10.0,
                        width: 20.0,
                        height: 20.0
                    )),
                    with: .color(color.opacity(0.12))
                )

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - 5.5,
                        y: point.y - 5.5,
                        width: 11.0,
                        height: 11.0
                    )),
                    with: .color(color)
                )
            }

            // Labels + scores
            drawLabel(
                text: "SLEEP",
                score: Int(index.sleepStrand.score.rounded()),
                angle: angles[0],
                color: HelixTheme.sleepColor,
                center: center,
                radius: radius,
                context: &context
            )

            drawLabel(
                text: "LOAD",
                score: Int(index.loadStrand.score.rounded()),
                angle: angles[1],
                color: HelixTheme.loadColor,
                center: center,
                radius: radius,
                context: &context
            )

            drawLabel(
                text: "RECOVERY",
                score: Int(index.recoveryStrand.score.rounded()),
                angle: angles[2],
                color: HelixTheme.recoveryColor,
                center: center,
                radius: radius,
                context: &context
            )
        }
    }

    private func drawLabel(
        text: String,
        score: Int,
        angle: Double,
        color: Color,
        center: CGPoint,
        radius: CGFloat,
        context: inout GraphicsContext
    ) {
        let radians = angle * Double.pi / 180.0

        let labelPoint = CGPoint(
            x: center.x + (radius + 18.0) * CGFloat(Foundation.cos(radians)),
            y: center.y + (radius + 18.0) * CGFloat(Foundation.sin(radians))
        )

        context.draw(
            Text(text)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(color.opacity(0.90)),
            at: labelPoint
        )

        let scorePoint = CGPoint(
            x: center.x + (radius * 0.88) * CGFloat(Foundation.cos(radians)),
            y: center.y + (radius * 0.88) * CGFloat(Foundation.sin(radians))
        )

        context.draw(
            Text("\(score)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(color.opacity(0.95)),
            at: scorePoint
        )
    }

    private func drawSectorTint(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        startAngle: Double,
        endAngle: Double,
        color: Color
    ) {
        var path = Path()
        let startRadians = startAngle * Double.pi / 180.0

        let startPoint = CGPoint(
            x: center.x + radius * CGFloat(Foundation.cos(startRadians)),
            y: center.y + radius * CGFloat(Foundation.sin(startRadians))
        )

        path.move(to: center)
        path.addLine(to: startPoint)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        path.closeSubpath()

        context.fill(path, with: .color(color))
    }
}

private struct DepthTwoStrandRow: View {
    let title: String
    let score: Double
    let confidence: ConfidenceLevel
    let color: Color
    let textColor: Color
    let onTap: () -> Void

    private var normalizedScore: CGFloat {
        CGFloat(min(max(score / 100.0, 0.0), 1.0))
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(HelixTheme.textSecondary)
                    .frame(width: 72, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(HelixTheme.textSecondary.opacity(0.08))
                            .frame(height: 2)

                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * normalizedScore, height: 2)
                            .shadow(color: color.opacity(0.35), radius: 6)
                    }
                }
                .frame(height: 2)

                Text("\(Int(score.rounded()))")
                    .font(.system(size: 26, weight: .thin, design: .rounded))
                    .foregroundColor(textColor)
                    .frame(width: 34, alignment: .trailing)

                ConfidenceIndicator(confidence: confidence, style: .dotsOnly)
                    .frame(minWidth: 28, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(HelixTheme.textSecondary.opacity(0.5))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(HelixTheme.backgroundSecondary.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(HelixTheme.borderSubtle, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 2)
                    .shadow(color: color.opacity(0.5), radius: 8)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Cross-Strand Insight Block

private struct CrossStrandInsightBlock: View {
    let insight: CrossStrandInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.depth2Headline)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(HelixTheme.textPrimary)

            Text(insight.depth2Body)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(HelixTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(HelixTheme.backgroundSecondary.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(HelixTheme.borderSubtle.opacity(0.6), lineWidth: 1)
        )
    }
}

// MARK: — Depth 2 content zones

struct DepthTwoTopContent: View {
    let index: HelixIndex
    let namespace: Namespace.ID

    private var posturePresentation: PosturePresentation {
        PosturePresentation(posture: index.posture)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DepthTwoPosturePill(posture: index.posture)
                .matchedGeometryEffect(id: "helixPosturePill", in: namespace)

            Text("\(Int(index.score.rounded()))")
                .font(.system(size: DepthTwoLayout.indexFontSize, weight: .thin, design: .rounded))
                .tracking(-2)
                .foregroundColor(posturePresentation.color)
                .shadow(color: posturePresentation.color.opacity(0.22), radius: 14)
                .matchedGeometryEffect(id: "helixIndexScore", in: namespace)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DepthTwoBottomContent: View {
    let index: HelixIndex
    let crossStrandInsight: CrossStrandInsight?
    let onStrandTap: (HelixStrand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                DepthTwoStrandRow(
                    title: "SLEEP",
                    score: index.sleepStrand.score,
                    confidence: index.sleepStrand.confidence,
                    color: HelixTheme.sleepColor,
                    textColor: HelixTheme.sleepTextColor
                ) { onStrandTap(.sleep) }

                DepthTwoStrandRow(
                    title: "LOAD",
                    score: index.loadStrand.score,
                    confidence: index.loadStrand.confidence,
                    color: HelixTheme.loadColor,
                    textColor: HelixTheme.loadTextColor
                ) { onStrandTap(.load) }

                DepthTwoStrandRow(
                    title: "RECOVERY",
                    score: index.recoveryStrand.score,
                    confidence: index.recoveryStrand.confidence,
                    color: HelixTheme.recoveryColor,
                    textColor: HelixTheme.recoveryTextColor
                ) { onStrandTap(.recovery) }
            }
            .padding(.horizontal, 16)

            if let insight = crossStrandInsight {
                CrossStrandInsightBlock(insight: insight)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }

            if index.balancePenalty > 2 {
                Text("Balance penalty -\(Int(index.balancePenalty.rounded())) pts")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(HelixTheme.textSecondary)
                    .padding(.top, 14)
            }

            Text("tap a pillar for breakdown >")
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(HelixTheme.textSecondary.opacity(0.45))
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
    }
}

private struct DepthTwoPreviewShell: View {
    @Namespace private var ns
    var body: some View {
        DepthTwoView(index: HelixPreviewSample.index, crossStrandInsight: nil, namespace: ns) { _ in }
            .background(HelixTheme.backgroundPrimary)
    }
}

#Preview("Depth 2") {
    DepthTwoPreviewShell()
}
