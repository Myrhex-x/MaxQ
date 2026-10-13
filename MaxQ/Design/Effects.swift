//
//  Effects.swift
//  Max Q
//
//  SpaceXAI's signature motion, rebuilt natively:
//    - SpectrumLine: the line grok.com and x.ai draw under a headline word. It grows from its
//      center, a band of spectrum light sweeps through it once, and it settles to a quiet grey.
//    - FlipText: x.ai's hero, where each word tips up into place (40 degrees back, half a line
//      low), 650 ms per word, 60 ms apart.
//    - MorphText: x.ai's rotating word, letters blurring out and back in one after another.
//    - ShimmerText: grok.com's "Thinking" sweep.
//    - RollingText: Grokipedia's rotating search hints, rolling up out of view.
//    - TwinkleField, LiveDot, Sheen, TypingDots and the ghost's blink.
//  Everything stands still under Reduce Motion.
//

import SwiftUI

// MARK: - Timing

/// A CSS cubic-bezier timing function, solved exactly (as browsers do).
struct UnitBezier: Sendable {
    private let ax, bx, cx, ay, by, cy: Double

    init(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double) {
        cx = 3 * p1x; bx = 3 * (p2x - p1x) - cx; ax = 1 - cx - bx
        cy = 3 * p1y; by = 3 * (p2y - p1y) - cy; ay = 1 - cy - by
    }

    static let spring = UnitBezier(0.22, 1, 0.36, 1)
    static let expo = UnitBezier(0.16, 1, 0.3, 1)
    static let standard = UnitBezier(0.2, 0, 0, 1)

    func callAsFunction(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < 1e-6 { return sampleY(t) }
            let slope = (3 * ax * t + 2 * bx) * t + cx
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        var low = 0.0, high = 1.0
        t = x
        while high - low > 1e-7 {
            let value = sampleX(t)
            if abs(value - x) < 1e-6 { break }
            if x > value { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sampleY(t)
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
}

// MARK: - Spectrum line

/// The underline grok.com and x.ai draw under one headline word: it grows from its center, a band
/// of spectrum light passes through it, and it rests as a quiet grey line. With `looping`, the
/// light keeps passing (loading).
///
/// On the web this is a 2-3 px line whose background is a gradient four times its width (grey, then
/// indigo, purple, pink, orange and yellow across its middle 20%), tiled, with its position run
/// from 150% to -150% over 3 s. Drawn here directly: the band's center moves 9 widths in 3 s and
/// the tiles repeat every 4 widths, so the light crosses the line twice, quickly.
struct SpectrumLine: View {
    var height: CGFloat = 2
    /// Delay before the line grows (grok.com waits 0.8 s, after the headline lands).
    var growDelay: Double = 0.8
    /// Delay before the light starts its passes.
    var sweepDelay: Double = 0.4
    var looping = false
    /// How strongly the resting grey shows (lower it when the line only exists to show progress).
    var restingOpacity: Double = 1

    @State private var grown = false
    @State private var start = Date()
    @State private var finished = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sweep: Double = 3

    var body: some View {
        let rest = (scheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.18)).opacity(restingOpacity)
        TimelineView(.animation(minimumInterval: nil, paused: finished || reduceMotion)) { timeline in
            Canvas { context, size in
                let width = size.width
                let line = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
                context.clip(to: line)
                context.fill(line, with: .color(rest))
                guard !reduceMotion else { return }
                for center in bandCenters(at: timeline.date, width: width) {
                    let band = CGRect(x: center - 0.6 * width, y: 0, width: 1.2 * width, height: size.height)
                    guard band.maxX > 0, band.minX < width else { continue }
                    context.fill(Path(band), with: .linearGradient(
                        Gradient(stops: [
                            .init(color: rest, location: 0),
                            .init(color: Theme.spectrum[0], location: 1 / 6),
                            .init(color: Theme.spectrum[1], location: 2 / 6),
                            .init(color: Theme.spectrum[2], location: 3 / 6),
                            .init(color: Theme.spectrum[3], location: 4 / 6),
                            .init(color: Theme.spectrum[4], location: 5 / 6),
                            .init(color: rest, location: 1),
                        ]),
                        startPoint: CGPoint(x: band.minX, y: 0), endPoint: CGPoint(x: band.maxX, y: 0)))
                }
            }
        }
        .frame(height: height)
        .scaleEffect(x: grown ? 1 : 0, y: 1)
        .opacity(grown ? 1 : 0)
        .onAppear(perform: begin)
        .accessibilityHidden(true)
    }

    /// Where the band (or bands) of light sit at `date`, in points from the line's leading edge.
    private func bandCenters(at date: Date, width: CGFloat) -> [CGFloat] {
        let elapsed = date.timeIntervalSince(start) - sweepDelay
        guard elapsed >= 0 else { return [] }
        if looping {
            // One pass every 1.6 s, from just off the left edge to just off the right.
            let progress = elapsed.truncatingRemainder(dividingBy: 1.6) / 1.6
            return [-0.6 * width + CGFloat(progress) * 2.2 * width]
        }
        guard elapsed <= Self.sweep else { return [] }
        let position = 1.5 - 3 * elapsed / Self.sweep // background-position, 150% to -150%
        let offset = -3 * width * CGFloat(position)
        // Tiles repeat every four widths; each tile's band is centered two widths in.
        return (-2...3).map { offset + 2 * width + CGFloat($0) * 4 * width }
    }

    private func begin() {
        start = Date()
        finished = false
        guard !reduceMotion else {
            grown = true
            return
        }
        withAnimation(Motion.expo(0.8).delay(growDelay)) { grown = true }
        if !looping {
            DispatchQueue.main.asyncAfter(deadline: .now() + sweepDelay + Self.sweep + 0.1) { finished = true }
        }
    }
}

// MARK: - Words tipping into place (x.ai's hero)

private struct WordIndex: TextAttribute {
    let index: Int
}

/// Draws each tagged word tipping up into place: half a line low, squashed as if leaning back 40
/// degrees, transparent, then landing on Grokipedia's spring curve.
private struct FlipRenderer: TextRenderer, Animatable {
    /// Seconds since the reveal began.
    var elapsed: Double
    let wordDuration: Double
    let stagger: Double
    let lift: CGFloat

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                let index = run[WordIndex.self]?.index ?? 0
                let local = UnitBezier.spring((elapsed - Double(index) * stagger) / wordDuration)
                if local >= 1 {
                    context.draw(run)
                    continue
                }
                guard local > 0 else { continue }
                var copy = context
                let bounds = run.typographicBounds.rect
                let tilt = 0.77 + 0.23 * local // cos(40°) at rest, flat when landed
                copy.opacity = local
                copy.translateBy(x: 0, y: (1 - local) * lift)
                copy.translateBy(x: bounds.midX, y: bounds.maxY)
                copy.scaleBy(x: 1, y: tilt)
                copy.translateBy(x: -bounds.midX, y: -bounds.maxY)
                copy.draw(run)
            }
        }
    }
}

/// x.ai's headline reveal for a block of text. Words tip up one after another; the text keeps
/// its natural spacing, kerning and wrapping.
struct FlipText: View {
    let text: String
    var font: Font
    /// Point size, for the lift (x.ai lifts each word 27 points at 60).
    var size: CGFloat
    var delay: Double = 0
    var stagger: Double = 0.06
    var wordDuration: Double = 0.65

    @State private var elapsed: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var words: [Substring] { text.split(separator: " ", omittingEmptySubsequences: false) }

    var body: some View {
        let total = wordDuration + Double(max(words.count - 1, 0)) * stagger
        composed
            .font(font)
            .textRenderer(FlipRenderer(elapsed: reduceMotion ? 100 : elapsed, wordDuration: wordDuration,
                                       stagger: stagger, lift: size * 0.45))
            .onAppear {
                guard !reduceMotion else { return }
                elapsed = 0
                withAnimation(.linear(duration: total).delay(delay)) { elapsed = total }
            }
            .accessibilityLabel(text)
    }

    private var composed: Text {
        var result = Text("")
        for (index, word) in words.enumerated() {
            if index > 0 { result = result + Text(" ") }
            result = result + Text(String(word)).customAttribute(WordIndex(index: index))
        }
        return result
    }
}

// MARK: - Letters blurring between words (x.ai's rotating word)

private struct GlyphRenderer: TextRenderer, Animatable {
    /// 0 hidden, `total` fully shown. Letters arrive and leave first to last.
    var elapsed: Double
    let glyphDuration: Double
    let stagger: Double
    /// How far a letter travels while it clears: positive rises in from below, negative drifts
    /// up and away.
    var travel: CGFloat = 0
    /// Leaving letters ease out of view (fading at once, then trailing off); arriving letters ease
    /// into it. The same curve run backwards would hold each letter, then drop it.
    var leaving = false

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // Leaving letters go in reading order too, so the old phrase clears from the left just
        // ahead of the new one filling in from the left.
        var count = 0
        if leaving { for line in layout { for run in line { count += run.count } } }
        var index = 0
        for line in layout {
            for run in line {
                for slice in run {
                    let order = leaving ? count - 1 - index : index
                    let progress = min(max((elapsed - Double(order) * stagger) / glyphDuration, 0), 1)
                    let shown = leaving ? 1 - UnitBezier.expo(1 - progress) : UnitBezier.expo(progress)
                    index += 1
                    if shown >= 1 {
                        context.draw(slice)
                        continue
                    }
                    guard shown > 0.001 else { continue }
                    var copy = context
                    copy.opacity = shown
                    copy.addFilter(.blur(radius: (1 - shown) * 6))
                    copy.translateBy(x: 0, y: (1 - shown) * travel)
                    copy.draw(slice)
                }
            }
        }
    }
}

/// A line that changes phrase in place, centered on its own middle: the old letters drift up
/// and blur away in reading order (12 ms apart), and a beat later the new ones rise out of a blur
/// (22 ms apart) while the width eases to the new phrase from both sides, so nothing slides
/// sideways. Both phrases are driven directly rather than by removal transitions, which SwiftUI
/// doesn't animate through a text renderer (the old phrase used to sit there, sharp, then vanish).
struct MorphText: View {
    let text: String
    var font: Font
    /// Point size, for how far the letters travel.
    var size: CGFloat = 40

    @State private var current = ""
    @State private var leaving = ""
    @State private var arrived: Double = 0
    @State private var departed: Double = 0
    @State private var width: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let outGlyph = 0.22, outStagger = 0.012
    private static let inGlyph = 0.46, inStagger = 0.022, inDelay = 0.16

    private static func outTotal(_ text: String) -> Double { outGlyph + Double(max(text.count - 1, 0)) * outStagger }
    private static func inTotal(_ text: String) -> Double { inGlyph + Double(max(text.count - 1, 0)) * inStagger }

    var body: some View {
        ZStack {
            Text(leaving)
                .font(font)
                .fixedSize()
                .textRenderer(GlyphRenderer(elapsed: departed, glyphDuration: Self.outGlyph, stagger: Self.outStagger,
                                            travel: -size * 0.14, leaving: true))
            Text(current)
                .font(font)
                .fixedSize()
                .textRenderer(GlyphRenderer(elapsed: arrived, glyphDuration: Self.inGlyph, stagger: Self.inStagger,
                                            travel: size * 0.2))
        }
        .frame(width: width)
        .background(
            Text(text).font(font).fixedSize().hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                    if width == nil || reduceMotion {
                        width = newWidth
                    } else {
                        // Starts as the old phrase leaves and lands with the new one.
                        withAnimation(.spring(response: 0.62, dampingFraction: 0.9).delay(0.08)) { width = newWidth }
                    }
                }
        )
        .onAppear {
            current = text
            arrived = Self.inTotal(text)
        }
        .onChange(of: text) { _, new in change(to: new) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func change(to new: String) {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { current = new }
            return
        }
        // Hand the shown phrase to the leaving layer and blank the new one, without animating...
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            leaving = current
            departed = Self.outTotal(current)
            current = new
            arrived = 0
        }
        // ...then let both run.
        DispatchQueue.main.async {
            withAnimation(.linear(duration: Self.outTotal(leaving))) { departed = 0 }
            withAnimation(.linear(duration: Self.inTotal(new)).delay(Self.inDelay)) { arrived = Self.inTotal(new) }
        }
    }
}

// MARK: - Thinking shimmer (grok.com)

/// grok.com's `.shimmer-text`: a soft-tailed band of light passes over the text every 2.4 s.
struct ShimmerText: View {
    let text: String
    var font: Font = .mqCaption
    var base: Color = Theme.textTertiary
    var peak: Color = Theme.textPrimary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(base)
            .overlay {
                if !reduceMotion {
                    TimelineView(.animation) { timeline in
                        GeometryReader { proxy in
                            let width = proxy.size.width
                            let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                            // background-size 200%, position 200% to -200%.
                            let offset = -2 * width + 4 * width * cycle
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.28),
                                .init(color: peak.opacity(0.16), location: 0.42),
                                .init(color: peak.opacity(0.42), location: 0.52),
                                .init(color: peak.opacity(0.78), location: 0.58),
                                .init(color: peak, location: 0.61),
                                .init(color: .clear, location: 0.66),
                                .init(color: .clear, location: 1),
                            ], startPoint: UnitPoint(x: 0, y: 0.42), endPoint: UnitPoint(x: 1, y: 0.58))
                            .frame(width: width * 2)
                            .offset(x: offset)
                        }
                    }
                    .mask(Text(text).font(font))
                    .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Rolling hints (Grokipedia's search placeholder)

/// Text that rolls up to the next value: the old line slides up 60% and fades, the new one rises
/// from below (520 ms on the spring curve, opacity 360 ms).
struct RollingText: View {
    let text: String
    var font: Font = .mqBody
    var color: Color = Theme.textTertiary
    /// The line's height, for the roll distance.
    var lineHeight: CGFloat = 20

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .id(text)
                .transition(.asymmetric(
                    insertion: .modifier(active: RollModifier(position: 1, distance: lineHeight * 0.6),
                                         identity: RollModifier(position: 0, distance: lineHeight * 0.6)),
                    removal: .modifier(active: RollModifier(position: -1, distance: lineHeight * 0.6),
                                       identity: RollModifier(position: 0, distance: lineHeight * 0.6))
                ))
        }
        .animation(Motion.spring(0.52), value: text)
    }
}

private struct RollModifier: ViewModifier {
    /// 1 below, 0 in place, -1 above.
    let position: CGFloat
    let distance: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(y: position * distance)
            .opacity(1 - abs(position))
    }
}

/// Cycles through `hints` every few seconds while `active`.
struct HintCycler: View {
    let hints: [String]
    var interval: Double = 3.6
    var font: Font = .mqBody
    var color: Color = Theme.textTertiary
    var lineHeight: CGFloat = 20
    var active = true

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RollingText(text: hints.isEmpty ? "" : hints[index % hints.count], font: font, color: color, lineHeight: lineHeight)
            .task(id: active) {
                guard active, !reduceMotion, hints.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    if Task.isCancelled { break }
                    index += 1
                }
            }
    }
}

// MARK: - Live dot (Grokipedia)

/// A dot with a ring pulsing out of it every 2.2 s.
struct LiveDot: View {
    var color: Color = Theme.textPrimary
    var size: CGFloat = 6
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: size, height: size)
                .scaleEffect(pulse ? 1.6 : 0.6)
                .opacity(pulse ? 0 : 0.9)
            Circle().fill(color).frame(width: size, height: size)
        }
        .frame(width: size * 1.8, height: size * 1.8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.standard(1.55).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// Back-compat name.
typealias PulseDot = LiveDot

// MARK: - Twinkling stars (Grokipedia's home)

/// Fixed points of light that swell and fade slowly (scale 0.8 to 1.2, opacity 30% to 100%,
/// 3.3 to 5.5 s each), as on Grokipedia's front page.
struct TwinkleField: View {
    var count = 56
    var seed: UInt64 = 7

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Star {
        let x, y, size, alpha, duration, delay: Double
    }

    private var stars: [Star] {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
        let sizes: [Double] = [1, 1, 1, 2, 2, 4, 6]
        let alphas: [Double] = [0.4, 0.3, 0.3, 0.2, 0.3, 0.14, 0.12]
        return (0..<count).map { _ in
            let kind = Int(next() * Double(sizes.count)) % sizes.count
            return Star(x: next(), y: next(), size: sizes[kind], alpha: alphas[kind],
                        duration: 3.3 + next() * 2.2, delay: next() * 3.3)
        }
    }

    var body: some View {
        let stars = stars
        let ink: Color = scheme == .dark ? .white : .black
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for star in stars {
                    let phase = ((time + star.delay) / star.duration).truncatingRemainder(dividingBy: 1)
                    let wave = reduceMotion ? 0.5 : 0.5 - 0.5 * cos(phase * 2 * .pi)
                    let scale = 0.8 + 0.4 * wave
                    let diameter = star.size * scale
                    let rect = CGRect(x: star.x * size.width - diameter / 2, y: star.y * size.height - diameter / 2,
                                      width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(star.alpha * (0.3 + 0.7 * wave))))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Sheen (x.ai's card hover)

/// A soft diagonal band of light that crosses a card once when `active` turns on (700 ms).
struct Sheen: View {
    let active: Bool
    @State private var position: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, .white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: proxy.size.width * 0.6)
                .rotationEffect(.degrees(12))
                .offset(x: position * proxy.size.width * 1.4 + proxy.size.width * 0.2)
                .frame(maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .onChange(of: active) { _, isActive in
            guard isActive else { return }
            position = -1
            withAnimation(.timingCurve(0, 0, 0.2, 1, duration: 0.7)) { position = 1 }
        }
    }
}

// MARK: - Typing dots (x.ai's chat demo)

struct TypingDots: View {
    var color: Color = Theme.textSecondary
    var size: CGFloat = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.8) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = ((time - Double(index) * 0.16) / 1.2).truncatingRemainder(dividingBy: 1)
                    let lit = phase < 0.25 ? phase / 0.25 : (phase < 0.55 ? 1 - (phase - 0.25) / 0.3 : 0)
                    Circle().fill(color).frame(width: size, height: size)
                        .opacity(0.25 + 0.45 * max(0, lit))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The ghost (private windows)

/// The private-window ghost, blinking twice every few seconds.
struct GhostMark: View {
    var size: CGFloat = 20
    var blinking = true

    private static let outline = SVGPath.parse("M5.5 20.25V11.5A6.5 6.5 0 0 1 18.5 11.5V20.25L16.25 18.5L14.1 20.25L12 18.5L9.9 20.25L7.75 18.5Z")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !blinking || reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.2) / 4.2
            // Two quick blinks, at 10% and 50% of a cycle (grok.com's ghost-eye-blink, slowed).
            let blink = blinkAmount(phase)
            ZStack {
                GridShape(path: Self.outline)
                    .stroke(style: StrokeStyle(lineWidth: 2 * size / 24, lineJoin: .miter))
                HStack(spacing: size * 0.12) {
                    ForEach(0..<2, id: \.self) { _ in
                        Ellipse()
                            .frame(width: size * 0.104, height: size * 0.133)
                            .scaleEffect(x: 1, y: 1 - 0.75 * blink)
                    }
                }
                .offset(y: -size * 0.02)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    private func blinkAmount(_ phase: Double) -> Double {
        for center in [0.08, 0.16] {
            let distance = abs(phase - center)
            if distance < 0.025 { return 1 - distance / 0.025 }
        }
        return 0
    }
}

// MARK: - Check landing (Grokipedia's icon-check)

extension View {
    /// Plays Grokipedia's check landing (small and tilted, overshooting, settling) each time
    /// `trigger` changes.
    func checkPop<T: Equatable>(_ trigger: T) -> some View {
        keyframeAnimator(initialValue: PopFrame(), trigger: trigger) { content, frame in
            content
                .scaleEffect(frame.scale)
                .rotationEffect(.degrees(frame.rotation))
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.4, duration: 0.001)
                CubicKeyframe(1.15, duration: 0.22)
                CubicKeyframe(1, duration: 0.16)
            }
            KeyframeTrack(\.rotation) {
                CubicKeyframe(-20, duration: 0.001)
                CubicKeyframe(3, duration: 0.22)
                CubicKeyframe(0, duration: 0.16)
            }
        }
    }
}

struct PopFrame {
    var scale: CGFloat = 1
    var rotation: Double = 0
}
