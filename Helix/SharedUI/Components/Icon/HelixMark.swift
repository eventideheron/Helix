import SwiftUI

struct HelixMark: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                HelixSleepStrand()
                    .fill(HelixColor.sleep)

                HelixRecoveryStrand()
                    .fill(HelixColor.recovery)

                HelixLoadStrand()
                    .fill(HelixColor.load)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .drawingGroup()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Sleep strand
// Left vertical ribbon with slight inward taper / curve

struct HelixSleepStrand: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var p = Path()

        p.move(to: CGPoint(x: w * 0.28, y: h * 0.08))

        // Outer left edge
        p.addCurve(
            to: CGPoint(x: w * 0.18, y: h * 0.78),
            control1: CGPoint(x: w * 0.24, y: h * 0.20),
            control2: CGPoint(x: w * 0.10, y: h * 0.58)
        )

        // Bottom belly
        p.addCurve(
            to: CGPoint(x: w * 0.30, y: h * 0.92),
            control1: CGPoint(x: w * 0.17, y: h * 0.86),
            control2: CGPoint(x: w * 0.23, y: h * 0.94)
        )

        // Inner right edge back upward
        p.addCurve(
            to: CGPoint(x: w * 0.42, y: h * 0.14),
            control1: CGPoint(x: w * 0.39, y: h * 0.76),
            control2: CGPoint(x: w * 0.45, y: h * 0.30)
        )

        // Top cap
        p.addCurve(
            to: CGPoint(x: w * 0.28, y: h * 0.08),
            control1: CGPoint(x: w * 0.40, y: h * 0.10),
            control2: CGPoint(x: w * 0.33, y: h * 0.08)
        )

        p.closeSubpath()
        return p
    }
}

// MARK: - Recovery strand
// Right arch / shoulder of the lowercase "h"

struct HelixRecoveryStrand: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var p = Path()

        p.move(to: CGPoint(x: w * 0.58, y: h * 0.36))

        // Inner left edge of arch
        p.addCurve(
            to: CGPoint(x: w * 0.60, y: h * 0.84),
            control1: CGPoint(x: w * 0.55, y: h * 0.48),
            control2: CGPoint(x: w * 0.58, y: h * 0.72)
        )

        // Bottom curve
        p.addCurve(
            to: CGPoint(x: w * 0.80, y: h * 0.76),
            control1: CGPoint(x: w * 0.64, y: h * 0.92),
            control2: CGPoint(x: w * 0.76, y: h * 0.88)
        )

        // Outer right edge up
        p.addCurve(
            to: CGPoint(x: w * 0.90, y: h * 0.44),
            control1: CGPoint(x: w * 0.88, y: h * 0.70),
            control2: CGPoint(x: w * 0.94, y: h * 0.54)
        )

        // Top shoulder
        p.addCurve(
            to: CGPoint(x: w * 0.73, y: h * 0.24),
            control1: CGPoint(x: w * 0.88, y: h * 0.30),
            control2: CGPoint(x: w * 0.80, y: h * 0.22)
        )

        // Return into stem
        p.addCurve(
            to: CGPoint(x: w * 0.58, y: h * 0.36),
            control1: CGPoint(x: w * 0.66, y: h * 0.25),
            control2: CGPoint(x: w * 0.60, y: h * 0.28)
        )

        p.closeSubpath()
        return p
    }
}

// MARK: - Load strand
// Front diagonal crossing ribbon

struct HelixLoadStrand: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var p = Path()

        p.move(to: CGPoint(x: w * 0.12, y: h * 0.68))

        // Lower outer edge
        p.addCurve(
            to: CGPoint(x: w * 0.32, y: h * 0.92),
            control1: CGPoint(x: w * 0.10, y: h * 0.80),
            control2: CGPoint(x: w * 0.18, y: h * 0.92)
        )

        // Main rise across center
        p.addCurve(
            to: CGPoint(x: w * 0.84, y: h * 0.28),
            control1: CGPoint(x: w * 0.52, y: h * 0.78),
            control2: CGPoint(x: w * 0.72, y: h * 0.26)
        )

        // Top edge cap
        p.addCurve(
            to: CGPoint(x: w * 0.70, y: h * 0.18),
            control1: CGPoint(x: w * 0.88, y: h * 0.24),
            control2: CGPoint(x: w * 0.80, y: h * 0.18)
        )

        // Return edge downward
        p.addCurve(
            to: CGPoint(x: w * 0.22, y: h * 0.58),
            control1: CGPoint(x: w * 0.54, y: h * 0.22),
            control2: CGPoint(x: w * 0.28, y: h * 0.42)
        )

        // Close into starting tail
        p.addCurve(
            to: CGPoint(x: w * 0.12, y: h * 0.68),
            control1: CGPoint(x: w * 0.16, y: h * 0.60),
            control2: CGPoint(x: w * 0.11, y: h * 0.64)
        )

        p.closeSubpath()
        return p
    }
}
