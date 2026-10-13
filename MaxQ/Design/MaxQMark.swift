//
//  MaxQMark.swift
//  Max Q
//
//  The Max Q mark: an ascent trajectory bending into orbit, with a single bright point on it.
//  Max Q is the moment of peak aerodynamic pressure on a launch; the point marks it. Drawn in
//  the primary color only, so it inverts cleanly between light and dark mode.
//
//  `animated: true` plays the launch: the trajectory draws itself upward, then the point ignites
//  and sends out one pressure ring.
//

import SwiftUI

enum MaxQGeometry {
    // Unit-space cubic Bezier for the trajectory (0...1 on both axes, y down).
    static let p0 = CGPoint(x: 0.16, y: 0.90)
    static let c1 = CGPoint(x: 0.20, y: 0.50)
    static let c2 = CGPoint(x: 0.44, y: 0.22)
    static let p3 = CGPoint(x: 0.90, y: 0.15)
    /// Where on the curve the Max Q point sits.
    static let markerT: CGFloat = 0.40

    static func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p3.y
        )
    }

    static func path(in rect: CGRect) -> Path {
        func s(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        var path = Path()
        path.move(to: s(p0))
        path.addCurve(to: s(p3), control1: s(c1), control2: s(c2))
        return path
    }
}

struct TrajectoryShape: Shape {
    func path(in rect: CGRect) -> Path { MaxQGeometry.path(in: rect) }
}

struct MaxQMark: View {
    var size: CGFloat = 56
    var glow: Bool = true
    var animated: Bool = false

    @State private var drawn: CGFloat = 1
    @State private var ignited = true
    @State private var ring = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lineWidth = max(1.2, size * 0.05)
        let unit = MaxQGeometry.point(at: MaxQGeometry.markerT)
        let r = size * 0.085

        ZStack(alignment: .topLeading) {
            TrajectoryShape()
                .trim(from: 0, to: drawn)
                .stroke(
                    LinearGradient(colors: [Theme.textPrimary.opacity(0), Theme.textPrimary.opacity(0.95)],
                                   startPoint: UnitPoint(x: MaxQGeometry.p0.x, y: 1),
                                   endPoint: UnitPoint(x: MaxQGeometry.p3.x, y: 0)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            ZStack {
                if glow {
                    Circle()
                        .fill(Theme.textPrimary.opacity(0.32))
                        .frame(width: r * 3.4, height: r * 3.4)
                        .blur(radius: r * 1.3)
                }
                Circle()
                    .strokeBorder(Theme.textPrimary.opacity(ring ? 0 : 0.24), lineWidth: max(0.8, lineWidth * 0.45))
                    .frame(width: r * 4.2, height: r * 4.2)
                    .scaleEffect(ring ? 1.9 : 1)
                Circle()
                    .fill(Theme.textPrimary)
                    .frame(width: r * 2, height: r * 2)
            }
            .scaleEffect(ignited ? 1 : 0.2)
            .opacity(ignited ? 1 : 0)
            .position(x: unit.x * size, y: unit.y * size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear(perform: launch)
    }

    private func launch() {
        guard animated, !reduceMotion else { return }
        drawn = 0
        ignited = false
        ring = false
        withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: 1.1)) { drawn = 1 }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.42)) { ignited = true }
        withAnimation(.easeOut(duration: 1.2).delay(0.55)) { ring = true }
    }
}

/// Mark plus the "Max Q" wordmark.
struct MaxQLockup: View {
    var markSize: CGFloat = 58
    var wordmarkSize: CGFloat = 34
    var animated = false

    var body: some View {
        VStack(spacing: 12) {
            MaxQMark(size: markSize, animated: animated)
            Text("Max Q")
                .font(.hero(wordmarkSize))
                .tracking(-wordmarkSize * 0.012)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel("Max Q")
        }
    }
}
