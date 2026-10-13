//
//  Morphs.swift
//  Max Q
//
//  Things that become other things, the principle Benji Taylor set out for Family ("any element
//  can become another if the change has a reason; we fly instead of teleport") and that runs
//  through grok.com's code today:
//    - MorphChevron: grok.com's model chevron, whose three points fold through a flat line from
//      down to up on a 400 / 30 spring.
//    - MorphLabel: labels that keep their shared letters. Letters both words have glide to their
//      new places; the rest fade out or in (after Family's "Continue" to "Confirm").
//    - StreamingText: Grok's answers word by word: each new piece clears out of 4 points of blur
//      in 200 ms on (0.22, 1, 0.36, 1); what is already shown never animates again.
//    - scrollEdgeFade: grok.com's 16-point fade at the edge of a list, only once it has scrolled.
//

import SwiftUI

// MARK: - Chevron

private struct ChevronShape: Shape {
    /// 0 points down, 1 points up.
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // grok.com's 16-point polyline: (4,6 8,10 12,6) down, (4,10 8,6 12,10) up.
        let unit = min(rect.width, rect.height) / 16
        let outer = 6 + 4 * progress, middle = 10 - 4 * progress
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4 * unit, y: rect.minY + outer * unit))
        path.addLine(to: CGPoint(x: rect.minX + 8 * unit, y: rect.minY + middle * unit))
        path.addLine(to: CGPoint(x: rect.minX + 12 * unit, y: rect.minY + outer * unit))
        return path
    }
}

struct MorphChevron: View {
    let open: Bool
    var size: CGFloat = 14

    /// A chevron turns rather than morphs (Benji Taylor's rule for glyphs of the same shape): down
    /// to up is a half turn, the shortest way round.
    var body: some View {
        MorphIcon(open ? .chevronUp : .chevronDown, size: size, weight: 2.6)
    }
}

// MARK: - Shared-letter labels

/// A label that morphs into its next value keeping the letters the two share: shared letters
/// glide, new ones arrive from 95% after a beat, old ones fade first. 400 ms on
/// (0.19, 1, 0.22, 1), the curve Family's text morph is usually run on.
struct MorphLabel: View {
    let text: String
    var font: Font = .mqBody

    @State private var glyphs: [Glyph] = []
    @State private var nextID = 0

    fileprivate struct Glyph: Identifiable, Equatable {
        let id: Int
        let character: Character
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(glyphs) { glyph in
                Text(String(glyph.character))
                    .font(font)
                    .fixedSize()
                    .transition(.asymmetric(
                        insertion: AnyTransition.modifier(active: GlyphArrival(shown: false), identity: GlyphArrival(shown: true))
                            .animation(.timingCurve(0.19, 1, 0.22, 1, duration: 0.3).delay(0.1)),
                        removal: AnyTransition.modifier(active: GlyphArrival(shown: false), identity: GlyphArrival(shown: true))
                            .animation(.timingCurve(0.3, 0, 1, 1, duration: 0.1))
                    ))
            }
        }
        .lineLimit(1)
        .onAppear { if glyphs.isEmpty { glyphs = assign(text, keeping: []) } }
        .onChange(of: text) { _, new in
            withAnimation(.timingCurve(0.19, 1, 0.22, 1, duration: 0.4)) {
                glyphs = assign(new, keeping: glyphs)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    /// Gives the new text's letters ids, reusing the ids of letters matched to the old text by a
    /// longest common subsequence.
    private func assign(_ text: String, keeping old: [Glyph]) -> [Glyph] {
        let new = Array(text)
        let oldChars = old.map(\.character)
        var lengths = Array(repeating: Array(repeating: 0, count: new.count + 1), count: oldChars.count + 1)
        if !oldChars.isEmpty && !new.isEmpty {
            for i in stride(from: oldChars.count - 1, through: 0, by: -1) {
                for j in stride(from: new.count - 1, through: 0, by: -1) {
                    lengths[i][j] = oldChars[i] == new[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
                }
            }
        }
        var result: [Glyph] = []
        var i = 0, j = 0
        var counter = nextID
        while j < new.count {
            if i < oldChars.count, oldChars[i] == new[j], lengths[i][j] == lengths[i + 1][j + 1] + 1 {
                result.append(Glyph(id: old[i].id, character: new[j]))
                i += 1
                j += 1
            } else if i < oldChars.count, lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                counter += 1
                result.append(Glyph(id: counter, character: new[j]))
                j += 1
            }
        }
        DispatchQueue.main.async { nextID = counter }
        return result
    }
}

private struct GlyphArrival: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.95)
    }
}

// MARK: - Streaming text

private struct Arrival: TextAttribute {
    let time: TimeInterval
}

/// Marks a citation chip: grok.com sets each citation as a small pill with the source's name.
struct CitationChipMark: TextAttribute {}

/// Draws a chip's pill behind its run (the run carries its own padding as no-break spaces).
private func drawChip(_ run: Text.Layout.Run, in context: inout GraphicsContext) {
    let rect = run.typographicBounds.rect.insetBy(dx: 0, dy: -2.5)
    context.fill(Capsule(style: .continuous).path(in: rect), with: .color(Theme.chip))
}

/// Draws citation chips; everything else as usual.
struct ChipRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[CitationChipMark.self] != nil { drawChip(run, in: &context) }
                context.draw(run)
            }
        }
    }
}

/// Draws each newly arrived piece of text clearing out of a 4-point blur over 200 ms, and the
/// citation chips.
private struct ArrivalRenderer: TextRenderer {
    let now: TimeInterval

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                let chip = run[CitationChipMark.self] != nil
                guard let arrival = run[Arrival.self] else {
                    if chip { drawChip(run, in: &context) }
                    context.draw(run)
                    continue
                }
                let shown = UnitBezier.spring((now - arrival.time) / 0.2)
                if shown >= 1 {
                    if chip { drawChip(run, in: &context) }
                    context.draw(run)
                    continue
                }
                var copy = context
                copy.opacity = shown
                copy.addFilter(.blur(radius: (1 - shown) * 4))
                if chip { drawChip(run, in: &copy) }
                copy.draw(run)
            }
        }
    }
}

/// Builds Text from an attributed string whose `chips` character ranges are citation chips.
enum ChipText {
    static func text(_ string: AttributedString, chips: [Range<Int>], from start: Int = 0, to end: Int? = nil) -> Text {
        let length = string.characters.count
        let end = min(end ?? length, length)
        var result = Text("")
        var cursor = max(0, start)
        for chip in chips where chip.upperBound > cursor && chip.lowerBound < end {
            let lower = max(chip.lowerBound, cursor), upper = min(chip.upperBound, end)
            if lower > cursor { result = result + Text(slice(string, cursor, lower)) }
            result = result + Text(slice(string, lower, upper)).customAttribute(CitationChipMark())
            cursor = upper
        }
        if cursor < end { result = result + Text(slice(string, cursor, end)) }
        return result
    }

    static func slice(_ string: AttributedString, _ start: Int, _ end: Int) -> AttributedString {
        let length = string.characters.count
        let clampedStart = max(0, min(start, length)), clampedEnd = max(clampedStart, min(end, length))
        let lower = string.characters.index(string.startIndex, offsetBy: clampedStart)
        let upper = string.characters.index(string.startIndex, offsetBy: clampedEnd)
        return AttributedString(string[lower..<upper])
    }
}

/// Inline text that grows while Grok streams: only the newest pieces animate, each clearing out
/// of a slight blur (grok.com uses Streamdown's blur-in at 200 ms).
struct StreamingText: View {
    let text: AttributedString
    var font: Font
    /// Citation chips, as character ranges of `text`.
    var chips: [Range<Int>] = []

    @State private var chunks: [(end: Int, time: TimeInterval)] = []
    @State private var settledAt = 0

    private var length: Int { text.characters.count }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: settledAt == chunks.count)) { timeline in
            composed(now: timeline.date.timeIntervalSinceReferenceDate)
                .font(font)
                .textRenderer(ArrivalRenderer(now: timeline.date.timeIntervalSinceReferenceDate))
        }
        .onChange(of: length) { old, new in
            if new < old {
                chunks = []
                settledAt = 0
            } else if new > old {
                chunks.append((new, Date.timeIntervalSinceReferenceDate))
            }
        }
        .task(id: chunks.count) {
            try? await Task.sleep(for: .milliseconds(260))
            if !Task.isCancelled { settledAt = chunks.count }
        }
    }

    /// The settled text in one piece, then each fresh chunk tagged with when it arrived.
    private func composed(now: TimeInterval) -> Text {
        let fresh = chunks.filter { now - $0.time < 0.22 }
        guard let first = fresh.first, let firstIndex = chunks.firstIndex(where: { $0.end == first.end && $0.time == first.time }) else {
            return ChipText.text(text, chips: chips)
        }
        let settledEnd = firstIndex > 0 ? chunks[firstIndex - 1].end : 0
        var result = ChipText.text(text, chips: chips, from: 0, to: settledEnd)
        var start = settledEnd
        for chunk in chunks[firstIndex...] {
            let end = min(chunk.end, length)
            guard end > start else { continue }
            result = result + ChipText.text(text, chips: chips, from: start, to: end).customAttribute(Arrival(time: chunk.time))
            start = end
        }
        if start < length { result = result + ChipText.text(text, chips: chips, from: start, to: length) }
        return result
    }
}

// MARK: - Scroll edges

private struct ScrollEdgeFade: ViewModifier {
    var edge: CGFloat = 16
    @State private var fadeTop = false
    @State private var fadeBottom = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: [Bool].self) { geometry in
                [geometry.contentOffset.y > 1,
                 geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1]
            } action: { _, state in
                withAnimation(Motion.standard(0.2)) {
                    fadeTop = state[0]
                    fadeBottom = state[1]
                }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(fadeTop ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: edge)
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(fadeBottom ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: edge)
                }
            }
    }
}

extension View {
    /// Fades a scroll view's content out over 16 points at an edge it has scrolled away from.
    func scrollEdgeFade(_ edge: CGFloat = 16) -> some View {
        modifier(ScrollEdgeFade(edge: edge))
    }
}
