//
//  MorphIcon.swift
//  Max Q
//
//  Icons that turn into each other instead of swapping, by Benji Taylor's method: every glyph is
//  exactly three lines, so any glyph can become any other by moving the lines' ends. A glyph that
//  needs fewer lines folds the spare one into a point at the center. Glyphs of the same shape
//  turn rather than morph (an arrow pointing right becomes one pointing down by rotating a
//  quarter turn; a plus becomes a cross by rotating 45°), the shortest way round.
//
//  Drawn on Max Q's 24-point grid at the house weight, with round ends, so the three dots of
//  "more" are lines of no length that stretch into the strokes of a cross.
//

import SwiftUI

/// One of the three-line glyphs.
nonisolated struct MorphGlyph: Equatable, Sendable {
    /// Each line: start x, start y, end x, end y, stroke width (0 folds it away).
    let lines: [Double]
    /// Degrees the glyph is turned, for glyphs that share a shape.
    let rotation: Double
    /// A turn that leaves the glyph looking the same (90° for a plus or a cross), so a morph can
    /// start or end at whichever of its angles is closest and turn as little as possible.
    let symmetry: Double

    private static let spare: [Double] = [12, 12, 12, 12, 0]

    private init(_ a: [Double], _ b: [Double], _ c: [Double], rotation: Double = 0, symmetry: Double = 0) {
        lines = a + b + c
        self.rotation = rotation
        self.symmetry = symmetry
    }

    // Arrows: the shaft, then the two strokes of the head.
    private static func arrow(_ rotation: Double) -> MorphGlyph {
        MorphGlyph([4.25, 12, 18.75, 12, 2], [12.25, 5.5, 18.75, 12, 2], [18.75, 12, 12.25, 18.5, 2], rotation: rotation)
    }
    static let arrowRight = arrow(0)
    static let arrowDown = arrow(90)
    static let arrowLeft = arrow(180)
    static let arrowUp = arrow(270)

    // Chevrons: an arrow's head, the shaft folded into its point.
    private static func chevron(_ rotation: Double) -> MorphGlyph {
        MorphGlyph([15.5, 12, 15.5, 12, 0], [9.25, 5.75, 15.5, 12, 2], [15.5, 12, 9.25, 18.25, 2], rotation: rotation)
    }
    static let chevronRight = chevron(0)
    static let chevronDown = chevron(90)
    static let chevronLeft = chevron(180)
    static let chevronUp = chevron(270)

    // The plus family: the across line first, so three dots ("more") stretch into it.
    static let plus = MorphGlyph([4.5, 12, 19.5, 12, 2], [12, 4.5, 12, 19.5, 2], spare, symmetry: 90)
    /// The plus, turned 45°.
    static let close = MorphGlyph([4.25, 12, 19.75, 12, 2], [12, 4.25, 12, 19.75, 2], spare, rotation: 45, symmetry: 90)
    static let minus = MorphGlyph([4.5, 12, 19.5, 12, 2], [12, 12, 12, 12, 0], spare)
    static let check = MorphGlyph([4.75, 12.5, 9.5, 17.25, 2], [9.5, 17.25, 19.25, 7.5, 2], spare)
    static let menu = MorphGlyph([4.5, 7, 19.5, 7, 2], [4.5, 12, 19.5, 12, 2], [4.5, 17, 19.5, 17, 2])
    static let equals = MorphGlyph([5, 9.25, 19, 9.25, 2], [5, 14.75, 19, 14.75, 2], spare)
    /// Three dots: lines of no length, as wide as the static glyph's dots. The outer two stretch
    /// into a cross's strokes; the middle one folds away.
    static let more = MorphGlyph([5.5, 12, 5.5, 12, 3.5], [18.5, 12, 18.5, 12, 3.5], [12, 12, 12, 12, 3.5], symmetry: 180)
    /// Three dots for "working": a chevron's point becomes the middle dot and each arm shrinks into
    /// one at its end (laid out down the glyph and turned, so a chevron pointing down needs no turn).
    static let dots = MorphGlyph([12, 12, 12, 12, 3.5], [12, 5.5, 12, 5.5, 3.5], [12, 18.5, 12, 18.5, 3.5], rotation: 90, symmetry: 180)
    static let external = MorphGlyph([6.75, 17.25, 16.5, 7.5, 2], [8.25, 6.75, 17.25, 6.75, 2], [17.25, 6.75, 17.25, 15.75, 2])
}

/// The lines as one animatable value, so SwiftUI can move every end at once.
nonisolated struct MorphLines: VectorArithmetic, Sendable {
    var values: [Double]

    static var zero: MorphLines { MorphLines(values: Array(repeating: 0, count: 15)) }

    static func + (lhs: MorphLines, rhs: MorphLines) -> MorphLines {
        MorphLines(values: zip(lhs.padded, rhs.padded).map(+))
    }

    static func - (lhs: MorphLines, rhs: MorphLines) -> MorphLines {
        MorphLines(values: zip(lhs.padded, rhs.padded).map(-))
    }

    mutating func scale(by rhs: Double) {
        values = padded.map { $0 * rhs }
    }

    var magnitudeSquared: Double { padded.reduce(0) { $0 + $1 * $1 } }

    private var padded: [Double] { values.count == 15 ? values : values + Array(repeating: 0, count: max(0, 15 - values.count)) }
}

/// The three lines, each stroked with round ends at its own width, as one filled shape.
struct MorphLinesShape: Shape {
    var lines: MorphLines

    var animatableData: MorphLines {
        get { lines }
        set { lines = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var result = Path()
        let v = lines.values
        guard v.count >= 15 else { return result }
        for index in 0..<3 {
            let base = index * 5
            let width = v[base + 4]
            guard width > 0.05 else { continue }
            var line = Path()
            let start = CGPoint(x: rect.minX + v[base] * scale, y: rect.minY + v[base + 1] * scale)
            let end = CGPoint(x: rect.minX + v[base + 2] * scale, y: rect.minY + v[base + 3] * scale)
            line.move(to: start)
            // A line of no length still draws its round end as a dot.
            line.addLine(to: start == end ? CGPoint(x: end.x + 0.001, y: end.y) : end)
            result.addPath(line.strokedPath(StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round)))
        }
        return result
    }
}

/// A glyph that turns into the next one: its lines' ends move, or it turns, on a quick spring.
struct MorphIcon: View {
    let glyph: MorphGlyph
    var size: CGFloat = 18
    /// Stroke weight in grid points (2 is the house weight; small glyphs in pills read better
    /// a little heavier).
    var weight: Double = 2

    @State private var angle: Double?
    /// The glyph the current angle belongs to, for picking the shortest turn to the next one.
    @State private var shown: MorphGlyph?

    init(_ glyph: MorphGlyph, size: CGFloat = 18, weight: Double = 2) {
        self.glyph = glyph
        self.size = size
        self.weight = weight
    }

    private var lines: MorphLines {
        var values = glyph.lines
        // Widths (every fifth value) follow the weight; dots keep their size.
        for index in stride(from: 4, to: values.count, by: 5) where values[index] > 0 && values[index] <= 2 {
            values[index] = values[index] * weight / 2
        }
        return MorphLines(values: values)
    }

    var body: some View {
        MorphLinesShape(lines: lines)
            .rotationEffect(.degrees(angle ?? glyph.rotation))
            .frame(width: size, height: size)
            .animation(Self.spring, value: glyph.lines)
            .onChange(of: glyph) { old, new in
                let (start, end) = Self.turn(from: angle ?? old.rotation, old: old, to: new)
                // Re-basing a symmetric glyph's angle changes nothing on screen.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { angle = start }
                withAnimation(Self.spring) { angle = end }
            }
            .accessibilityHidden(true)
    }

    /// The angles to turn between: the shortest way round, starting and ending at whichever of a
    /// symmetric glyph's equivalent angles is closest.
    nonisolated static func turn(from current: Double, old: MorphGlyph, to new: MorphGlyph) -> (Double, Double) {
        func steps(_ symmetry: Double) -> [Double] {
            symmetry > 0 ? stride(from: -360.0, through: 360.0, by: symmetry).map { $0 } : [0]
        }
        // The new glyph's angle, brought within half a turn of where things are.
        var target = new.rotation
        while target - current > 180 { target -= 360 }
        while target - current < -180 { target += 360 }
        var best = (start: current, end: target)
        for shift in steps(old.symmetry) {
            for offset in steps(new.symmetry) {
                let start = current + shift, end = target + offset
                if abs(end - start) < abs(best.end - best.start) - 0.001 { best = (start, end) }
            }
        }
        return best
    }

    /// Small, quick, settling without a bounce worth seeing.
    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.82)
}
