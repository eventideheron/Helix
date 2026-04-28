// HelixWidgetInstrumentView.swift
// Widget-target circle instrument: outer segmented strand ring + inner
// concentric rings + radial spokes + filled strand triangle, with posture
// label and index number centered. Pure input-driven; no main-app theme
// imports. Constants and colors mirror the canonical values used by
// DepthOneGhostRadarView and HelixColor in the main app.

import SwiftUI

struct HelixWidgetInstrumentView: View {

    let helixIndex: Double
    let posture: String
    let sleepFraction: Double
    let loadFraction: Double
    let recoveryFraction: Double
    let tint: Color

    // Strand angles (degrees, math convention: 0° = +x, 90° = +y / down).
    // Match DepthOneGhostRadarView (DepthOneView.swift) — sleep top,
    // load bottom-right, recovery bottom-left.
    private static let sleepAngleDeg:    Double = -90
    private static let loadAngleDeg:     Double =  30
    private static let recoveryAngleDeg: Double = 150

    // Outer ring radius as a fraction of min(width, height). Matches
    // HelixDashboardAnchorMetrics.radarOuterRadius (`min * 0.34`).
    private static let radiusFactor:       CGFloat = 0.34
    private static let midRingFraction:    Double  = 0.66
    private static let innerRingFraction:  Double  = 0.33

    // Canonical palette values copied from HelixColor in
    // Helix/Helix/SharedUI/Theme/Colors.swift. SharedUI is not in the
    // widget target — values are inlined here verbatim.
    static let sleepColor:    Color = Color(red:  74.0 / 255.0, green:  85.0 / 255.0, blue: 162.0 / 255.0) // #4A55A2
    static let loadColor:     Color = Color(red:   0.0 / 255.0, green: 227.0 / 255.0, blue: 255.0 / 255.0) // #00E3FF
    static let recoveryColor: Color = Color(red:  46.0 / 255.0, green: 143.0 / 255.0, blue: 110.0 / 255.0) // #2E8F6E
    static let neutralColor:  Color = Color(red: 139.0 / 255.0, green: 148.0 / 255.0, blue: 158.0 / 255.0) // #8B949E

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) * Self.radiusFactor

                    drawInnerRings(context: context, center: center, radius: radius)
                    drawOuterStrandRing(context: context, center: center, radius: radius)
                    drawSpokes(context: context, center: center, radius: radius)
                    drawStrandTriangle(context: context, center: center, radius: radius)
                }
                .opacity(0.55)

                centerLabels(side: min(geo.size.width, geo.size.height))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: — Geometry

    private func drawInnerRings(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for fraction in [Self.midRingFraction, Self.innerRingFraction] {
            let r = radius * fraction
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(Self.neutralColor.opacity(0.18)),
                lineWidth: 0.5
            )
        }
    }

    private func drawOuterStrandRing(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let segments: [(start: Double, end: Double, color: Color)] = [
            (-150,  -30, Self.sleepColor),
            ( -30,   90, Self.loadColor),
            (  90,  210, Self.recoveryColor)
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
            context.stroke(path, with: .color(seg.color.opacity(0.55)), lineWidth: 1.0)
        }
    }

    private func drawSpokes(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for angle in [Self.sleepAngleDeg, Self.loadAngleDeg, Self.recoveryAngleDeg] {
            let radians: Double = angle * .pi / 180
            let endpoint = CGPoint(
                x: center.x + radius * CGFloat(cos(radians)),
                y: center.y + radius * CGFloat(sin(radians))
            )
            var line = Path()
            line.move(to: center)
            line.addLine(to: endpoint)
            context.stroke(
                line,
                with: .color(Self.neutralColor.opacity(0.18)),
                lineWidth: 0.5
            )
        }
    }

    private func drawStrandTriangle(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let angles = [Self.sleepAngleDeg, Self.loadAngleDeg, Self.recoveryAngleDeg]
        let fractions = [
            clampUnit(sleepFraction),
            clampUnit(loadFraction),
            clampUnit(recoveryFraction)
        ]
        var polygon = Path()
        for i in 0..<3 {
            let radians: Double = angles[i] * .pi / 180
            let p = CGPoint(
                x: center.x + radius * CGFloat(fractions[i]) * CGFloat(cos(radians)),
                y: center.y + radius * CGFloat(fractions[i]) * CGFloat(sin(radians))
            )
            if i == 0 { polygon.move(to: p) } else { polygon.addLine(to: p) }
        }
        polygon.closeSubpath()

        context.fill(polygon, with: .color(tint.opacity(0.08)))
        context.stroke(polygon, with: .color(tint.opacity(0.30)), lineWidth: 1.2)
    }

    // MARK: — Center labels

    @ViewBuilder
    private func centerLabels(side: CGFloat) -> some View {
        VStack(spacing: max(2, side * 0.02)) {
            Text(posture)
                .font(.system(size: max(7, side * 0.07), weight: .semibold))
                .tracking(2)
                .foregroundColor(tint.opacity(0.85))
            Text("\(Int(helixIndex.rounded()))")
                .font(.system(size: max(28, side * 0.42), weight: .thin, design: .rounded))
                .foregroundColor(tint)
        }
    }

    private func clampUnit(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}
