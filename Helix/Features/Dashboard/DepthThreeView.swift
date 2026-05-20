import SwiftUI

// MARK: — Depth 3 expansion (shared by fixed radar + breakdown rows + vertex taps)
//
// Uses `@Observable` (not `ObservableObject`) so the type works under
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which breaks synthesized
// `ObservableObject` conformance for plain classes.

@Observable
final class DepthThreeExpansionCoordinator {
    var expandedSignal: SignalIdentifier? = nil
    /// Set by a cross-strand vertex tap in `DepthThreeRadar`; observed by `HelixContentView`
    /// to update `selectedStrand` without needing a direct binding through the view hierarchy.
    var strandChangeRequest: HelixStrand? = nil

    @MainActor
    func toggle(_ signal: SignalIdentifier) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            expandedSignal = (expandedSignal == signal) ? nil : signal
        }
    }
}

struct DepthThreeView: View {
    let index: HelixIndex
    let selectedStrand: HelixStrand?
    let explanationEngine: HelixExplanationEngine
    let namespace: Namespace.ID

    private var strand: StrandScore {
        switch selectedStrand {
        case .sleep:
            return index.sleepStrand
        case .load:
            return index.loadStrand
        case .recovery, .none:
            return index.recoveryStrand
        }
    }

    private var posturePresentation: PosturePresentation {
        PosturePresentation(posture: index.posture)
    }

    @State private var strandClusterSlide: CGFloat = 1
    @State private var signalCardsAnimationTick: Int = 0
    @State private var expansionCoordinator = DepthThreeExpansionCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                HStack {
                    Spacer(minLength: 0)
                    DepthThreeRadar(
                        index: index,
                        selectedStrand: strand.strand,
                        expansion: expansionCoordinator
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: HelixDashboardAnchorMetrics.chartHeight)
                    .padding(.horizontal, HelixDashboardAnchorMetrics.chartHorizontalPadding)
                    .matchedGeometryEffect(id: "helixRadar", in: namespace)
                    Spacer(minLength: 0)
                }
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity)

                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            DepthTwoPosturePill(posture: index.posture)
                                .matchedGeometryEffect(id: "helixPosturePill", in: namespace)

                            Text("\(Int(index.score.rounded()))")
                                .font(.system(size: 36, weight: .thin, design: .rounded))
                                .tracking(-2)
                                .foregroundColor(posturePresentation.color)
                                .shadow(color: posturePresentation.color.opacity(0.22), radius: 14)
                                .matchedGeometryEffect(id: "helixIndexScore", in: namespace)
                        }
                        .padding(.leading, 18)
                        .padding(.top, 12)

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 3) {
                            // Row 1: confidence chip — aligns with posture pill
                            ConfidenceIndicator(confidence: strand.confidence)

                            // Row 2: strand score — aligns with Helix index
                            Text("\(Int(strand.score.rounded()))")
                                .font(.system(size: 36, weight: .thin, design: .rounded))
                                .tracking(-1)
                                .foregroundColor(HelixTheme.textColor(for: strand.strand))

                            // Row 3: strand name — identifier below score
                            Text(strand.strand.displayLabel.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(3)
                                .foregroundColor(HelixTheme.textColor(for: strand.strand))
                        }
                        .padding(.trailing, 18)
                        .padding(.top, 12)
                        .offset(y: 60 * strandClusterSlide)
                        .opacity(1.0 - 0.35 * Double(strandClusterSlide))
                    }
                }
                .frame(minHeight: HelixDashboardAnchorMetrics.chartHeight + 28)
                .onAppear {
                    strandClusterSlide = 1
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                        strandClusterSlide = 0
                    }
                    signalCardsAnimationTick &+= 1
                }
                .onChange(of: selectedStrand) { _, _ in
                    signalCardsAnimationTick &+= 1
                    expansionCoordinator.expandedSignal = nil
                }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                if expansionCoordinator.expandedSignal == nil {
                    Text(explanationEngine.resolveForDisplay(strand.primaryExplanation))
                        .font(.body)
                        .foregroundColor(HelixTheme.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }

                if !strand.missingSignals.isEmpty || (index.recoveryGateApplied && strand.strand == .recovery) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !strand.missingSignals.isEmpty {
                            Text("\(strand.missingSignals.count) signal\(strand.missingSignals.count == 1 ? "" : "s") unavailable — score is estimated")
                                .font(.caption2)
                                .foregroundColor(HelixTheme.confidenceMedium)

                            Text("Missing: \(strand.missingSignals.map(\.displayLabel).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundColor(HelixTheme.textSecondary)
                        }

                        if index.recoveryGateApplied && strand.strand == .recovery {
                            Text("Recovery gate active - overall Helix score is being suppressed by a collapsed recovery state.")
                                .font(.caption)
                                .foregroundColor(HelixTheme.restoreColor.opacity(0.85))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HelixTheme.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(HelixTheme.borderSubtle, lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                if !strand.contributionBreakdown.isEmpty {
                    Text("SIGNAL BREAKDOWN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(HelixTheme.textSecondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

                    ExpandableSignalBreakdown(
                        contributions: Array(strand.contributionBreakdown.prefix(5)),
                        color: HelixTheme.textColor(for: strand.strand),
                        explanationEngine: explanationEngine,
                        expansion: expansionCoordinator,
                        animationTrigger: signalCardsAnimationTick
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(HelixTheme.backgroundPrimary.ignoresSafeArea())
    }
}

private enum DepthThreeRadarDrawing {
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
                with: .color(seg.color.opacity(0.52)),
                lineWidth: lineWidth
            )
        }
    }
}

struct DepthThreeRadar: View {
    let index: HelixIndex
    let selectedStrand: HelixStrand
    /// When `nil`, polygon vertex dots are not tappable.
    var expansion: DepthThreeExpansionCoordinator? = nil

    private let slots: [RadarSlot] = RadarSlot.defaultSlots

    var body: some View {
        GeometryReader { geo in
            let vertexPoints = polygonVertexPositions(in: geo.size)
            ZStack {
                radarCanvas
                if let expansion = expansion {
                    ForEach(slots.indices, id: \.self) { i in
                        if let signal = slots[i].vertexTapSignal {
                            Circle()
                                .stroke(Color.clear, lineWidth: 0)
                                .background(Color.clear)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                                .position(vertexPoints[i])
                                .onTapGesture {
                                    // Cross-strand: request a strand switch before toggling the signal.
                                    // HelixContentView observes strandChangeRequest and updates selectedStrand.
                                    if slots[i].strand != selectedStrand {
                                        expansion.strandChangeRequest = slots[i].strand
                                    }
                                    expansion.toggle(signal)
                                }
                        }
                    }
                }
            }
        }
    }

    /// Unchanged drawing path; wrapped so vertex overlays share the same geometry as the canvas.
    private var radarCanvas: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.34

            for fraction in [0.70, 0.38, 0.13] {
                let r = radius * fraction
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)

                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(HelixTheme.textSecondary.opacity(0.05)),
                    lineWidth: 0.6
                )
            }

            DepthThreeRadarDrawing.strokeSegmentedStrandOuterRing(
                context: &context,
                center: center,
                radius: radius,
                lineWidth: 1.05
            )

            drawSectorTint(
                context: &context,
                center: center,
                radius: radius + 12,
                startAngle: -105,
                endAngle: 15,
                color: HelixTheme.sleepColor.opacity(0.05)
            )

            drawSectorTint(
                context: &context,
                center: center,
                radius: radius + 12,
                startAngle: 15,
                endAngle: 135,
                color: HelixTheme.loadColor.opacity(0.04)
            )

            drawSectorTint(
                context: &context,
                center: center,
                radius: radius + 12,
                startAngle: 135,
                endAngle: 255,
                color: recoverySectorColor.opacity(0.05)
            )

            for slot in slots {
                let radians = slot.angle * .pi / 180
                let end = CGPoint(
                    x: center.x + radius * cos(radians),
                    y: center.y + radius * sin(radians)
                )

                var line = Path()
                line.move(to: center)
                line.addLine(to: end)

                let spokeColor = slot.isPillar
                    ? color(for: slot.strand).opacity(0.22)
                    : HelixTheme.textSecondary.opacity(0.08)

                context.stroke(
                    line,
                    with: .color(spokeColor),
                    lineWidth: slot.isPillar ? 1.0 : 0.75
                )

                let labelPoint = CGPoint(
                    x: center.x + (radius + (slot.isPillar ? 18 : 14)) * cos(radians),
                    y: center.y + (radius + (slot.isPillar ? 18 : 14)) * sin(radians)
                )

                context.draw(
                    Text(slot.short)
                        .font(.system(size: slot.isPillar ? 7.5 : 6, design: .monospaced))
                        .foregroundColor(color(for: slot.strand).opacity(slot.isPillar ? 0.92 : 0.80)),
                    at: labelPoint
                )
            }

            let polygonValues = resolvedPolygonValues()
            let polygonPoints: [CGPoint] = zip(slots, polygonValues).map { slot, value in
                let clamped = min(max(value / 100.0, 0.0), 1.0)
                let radians = slot.angle * .pi / 180
                return CGPoint(
                    x: center.x + radius * clamped * cos(radians),
                    y: center.y + radius * clamped * sin(radians)
                )
            }

            var polygon = Path()
            for (i, point) in polygonPoints.enumerated() {
                if i == 0 {
                    polygon.move(to: point)
                } else {
                    polygon.addLine(to: point)
                }
            }
            polygon.closeSubpath()

            let postureTint = PosturePresentation(posture: index.posture).color

            context.stroke(
                polygon,
                with: .color(selectedTint.opacity(0.28)),
                lineWidth: 8
            )
            context.fill(
                polygon,
                with: .color(postureTint.opacity(0.07))
            )
            context.stroke(
                polygon,
                with: .color(selectedTint.opacity(0.50)),
                lineWidth: 1.5
            )

            for (vertexIndex, point) in polygonPoints.enumerated() {
                let slot = slots[vertexIndex]
                let dotColor = color(for: slot.strand)
                let dotRadius: CGFloat = slot.isPillar ? 5.5 : 3.6

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - (dotRadius + 5),
                        y: point.y - (dotRadius + 5),
                        width: (dotRadius + 5) * 2,
                        height: (dotRadius + 5) * 2
                    )),
                    with: .color(dotColor.opacity(0.15))
                )

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - dotRadius,
                        y: point.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )),
                    with: .color(dotColor.opacity(slot.isPillar ? 1.0 : 0.78))
                )
            }
        }
    }

    private func polygonVertexPositions(in size: CGSize) -> [CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.34
        let polygonValues = resolvedPolygonValues()
        return zip(slots, polygonValues).map { slot, value in
            let clamped = min(max(value / 100.0, 0.0), 1.0)
            let radians = slot.angle * .pi / 180
            return CGPoint(
                x: center.x + radius * clamped * cos(radians),
                y: center.y + radius * clamped * sin(radians)
            )
        }
    }

    private func resolvedPolygonValues() -> [Double] {
        let sleepValues = perStrandValues(for: index.sleepStrand)
        let loadValues = perStrandValues(for: index.loadStrand)
        let recoveryValues = perStrandValues(for: index.recoveryStrand)
        return sleepValues + loadValues + recoveryValues
    }

    private func perStrandValues(for strand: StrandScore) -> [Double] {
        // Spoke radii = signal state (0…100), not weighted contribution magnitude.
        // Rank order only: top contributors by |pointContribution|, then plot each signal's normalizedScore.
        let topThreeSignals = strand.contributionBreakdown
            .sorted { abs($0.pointContribution) > abs($1.pointContribution) }
            .prefix(3)
            .map(\.signal)

        var values: [Double] = [strand.score]

        for signalId in topThreeSignals {
            if let component = strand.componentSignals.first(where: { $0.identifier == signalId }) {
                values.append(component.normalizedScore.clampedToHelixScore())
            } else {
                values.append(strand.score.clampedToHelixScore())
            }
        }

        while values.count < 4 {
            let fallback = max(strand.score - Double(values.count * 8), 18.0)
            values.append(fallback)
        }

        return values
    }

    private func color(for strand: HelixStrand) -> Color {
        switch strand {
        case .sleep:
            return HelixTheme.sleepColor
        case .load:
            return HelixTheme.loadColor
        case .recovery:
            return recoverySectorColor
        }
    }

    private var recoverySectorColor: Color {
        if selectedStrand == .recovery && index.posture == .restore {
            return HelixTheme.restoreColor
        }
        return HelixTheme.recoveryColor
    }

    private var selectedTint: Color {
        switch selectedStrand {
        case .sleep:
            return HelixTheme.sleepColor
        case .load:
            return HelixTheme.loadColor
        case .recovery:
            return recoverySectorColor
        }
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
        let start = CGPoint(
            x: center.x + radius * cos(startAngle * .pi / 180),
            y: center.y + radius * sin(startAngle * .pi / 180)
        )

        path.move(to: center)
        path.addLine(to: start)
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

private struct RadarSlot {
    let short: String
    let strand: HelixStrand
    let angle: Double
    let isPillar: Bool

    static let defaultSlots: [RadarSlot] = [
        RadarSlot(short: "SLP", strand: .sleep, angle: -90, isPillar: true),
        RadarSlot(short: "DUR", strand: .sleep, angle: -60, isPillar: false),
        RadarSlot(short: "DEEP", strand: .sleep, angle: -30, isPillar: false),
        RadarSlot(short: "REM", strand: .sleep, angle: 0, isPillar: false),

        RadarSlot(short: "LOAD", strand: .load, angle: 30, isPillar: true),
        RadarSlot(short: "VOL", strand: .load, angle: 60, isPillar: false),
        RadarSlot(short: "COMP", strand: .load, angle: 90, isPillar: false),
        RadarSlot(short: "HRZ", strand: .load, angle: 120, isPillar: false),

        RadarSlot(short: "REC", strand: .recovery, angle: 150, isPillar: true),
        RadarSlot(short: "HRV", strand: .recovery, angle: 180, isPillar: false),
        RadarSlot(short: "RHR", strand: .recovery, angle: 210, isPillar: false),
        RadarSlot(short: "DIP", strand: .recovery, angle: 240, isPillar: false)
    ]
}

private extension RadarSlot {
    /// Maps radar spokes to `SignalContribution.signal` for vertex / row expansion parity.
    var vertexTapSignal: SignalIdentifier? {
        switch short {
        case "SLP", "DUR": return .sleepDuration
        case "DEEP": return .deepSleepPercent
        case "REM": return .remSleepPercent
        case "LOAD", "VOL": return .trainingVolume
        case "COMP": return .activityCompletion
        case "HRZ": return .hrElevation
        case "REC", "HRV": return .hrv
        case "RHR": return .restingHR
        case "DIP": return .overnightHRDip
        default: return nil
        }
    }
}

private struct ExpandableSignalBreakdown: View {
    let contributions: [SignalContribution]
    let color: Color
    let explanationEngine: HelixExplanationEngine
    var expansion: DepthThreeExpansionCoordinator
    let animationTrigger: Int

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(contributions.enumerated()), id: \.element.signal) { index, contribution in
                let isExpanded = expansion.expandedSignal == contribution.signal
                SignalContributionRow(
                    contribution: contribution,
                    isExpanded: isExpanded,
                    color: color,
                    explanationEngine: explanationEngine
                ) {
                    expansion.toggle(contribution.signal)
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.82)
                        .delay(Double(index) * 0.055),
                    value: animationTrigger
                )
            }
        }
    }
}

// MARK: — Depth 3 content zones

struct DepthThreeTopContent: View {
    let index: HelixIndex
    let selectedStrand: HelixStrand?
    let explanationEngine: HelixExplanationEngine
    let namespace: Namespace.ID

    @State private var strandClusterSlide: CGFloat = 1

    private var strand: StrandScore {
        switch selectedStrand {
        case .sleep:             return index.sleepStrand
        case .load:              return index.loadStrand
        case .recovery, .none:  return index.recoveryStrand
        }
    }

    private var posturePresentation: PosturePresentation {
        PosturePresentation(posture: index.posture)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    DepthTwoPosturePill(posture: index.posture)
                        .matchedGeometryEffect(id: "helixPosturePill", in: namespace)

                    Text("\(Int(index.score.rounded()))")
                        .font(.system(size: 36, weight: .thin, design: .rounded))
                        .tracking(-2)
                        .foregroundColor(posturePresentation.color)
                        .shadow(color: posturePresentation.color.opacity(0.22), radius: 14)
                        .matchedGeometryEffect(id: "helixIndexScore", in: namespace)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    ConfidenceIndicator(confidence: strand.confidence)

                    Text("\(Int(strand.score.rounded()))")
                        .font(.system(size: 36, weight: .thin, design: .rounded))
                        .tracking(-1)
                        .foregroundColor(HelixTheme.textColor(for: strand.strand))

                    Text(strand.strand.displayLabel.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(HelixTheme.textColor(for: strand.strand))
                }
                .offset(y: 60 * strandClusterSlide)
                .opacity(1.0 - 0.35 * Double(strandClusterSlide))
            }
        }
        .onAppear {
            strandClusterSlide = 1
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                strandClusterSlide = 0
            }
        }
    }
}

struct DepthThreeBottomContent: View {
    let index: HelixIndex
    let selectedStrand: HelixStrand?
    let explanationEngine: HelixExplanationEngine
    var expansion: DepthThreeExpansionCoordinator

    @State private var signalCardsAnimationTick: Int = 0

    private var strand: StrandScore {
        switch selectedStrand {
        case .sleep:             return index.sleepStrand
        case .load:              return index.loadStrand
        case .recovery, .none:  return index.recoveryStrand
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if expansion.expandedSignal == nil {
                    Text(explanationEngine.resolveForDisplay(strand.primaryExplanation))
                        .font(.body)
                        .foregroundColor(HelixTheme.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }

                if !strand.missingSignals.isEmpty || (index.recoveryGateApplied && strand.strand == .recovery) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !strand.missingSignals.isEmpty {
                            Text("\(strand.missingSignals.count) signal\(strand.missingSignals.count == 1 ? "" : "s") unavailable — score is estimated")
                                .font(.caption2)
                                .foregroundColor(HelixTheme.confidenceMedium)

                            Text("Missing: \(strand.missingSignals.map(\.displayLabel).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundColor(HelixTheme.textSecondary)
                        }

                        if index.recoveryGateApplied && strand.strand == .recovery {
                            Text("Recovery gate active - overall Helix score is being suppressed by a collapsed recovery state.")
                                .font(.caption)
                                .foregroundColor(HelixTheme.restoreColor.opacity(0.85))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HelixTheme.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(HelixTheme.borderSubtle, lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                if !strand.contributionBreakdown.isEmpty {
                    Text("SIGNAL BREAKDOWN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(HelixTheme.textSecondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

                    ExpandableSignalBreakdown(
                        contributions: Array(strand.contributionBreakdown.prefix(5)),
                        color: HelixTheme.textColor(for: strand.strand),
                        explanationEngine: explanationEngine,
                        expansion: expansion,
                        animationTrigger: signalCardsAnimationTick
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            signalCardsAnimationTick &+= 1
        }
        .onChange(of: selectedStrand) { _, _ in
            // Do not clear expandedSignal here — a cross-strand vertex tap sets it immediately
            // before selectedStrand changes, so clearing would undo that expansion.
            // expandedSignal is cleared by HelixContentView when leaving depth 3 entirely.
            signalCardsAnimationTick &+= 1
        }
    }
}

#Preview("Depth 3") {
    Text("Use app runtime preview for Depth 3 once explanation engine is injected.")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HelixTheme.backgroundPrimary)
}
