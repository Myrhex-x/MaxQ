//
//  MorphIconTests.swift
//  Max Q
//

import AppKit
import SwiftUI
import Testing
@testable import MaxQ

@MainActor
struct MorphIconTests {
    @Test func everyGlyphHasThreeLines() {
        for glyph in [MorphGlyph.arrowRight, .chevronDown, .plus, .close, .minus, .check, .menu, .equals, .more, .external] {
            #expect(glyph.lines.count == 15)
        }
        // Same shape, turned: only the rotation differs.
        #expect(MorphGlyph.arrowRight.lines == MorphGlyph.arrowUp.lines)
        #expect(MorphGlyph.plus.lines.count == MorphGlyph.close.lines.count)
    }

    @Test func turnsTheShortestWay() {
        // A cross is the same at 45° and 135°: on its way to a left arrow it turns 45°, not 135°.
        let (start, end) = MorphIcon.turn(from: 45, old: .close, to: .arrowLeft)
        #expect(abs(end - start) == 45)
        // Right to up is a quarter turn back.
        let (a, b) = MorphIcon.turn(from: 0, old: .arrowRight, to: .arrowUp)
        #expect(b - a == -90)
        // A chevron pointing down becomes dots without turning.
        let (c, d) = MorphIcon.turn(from: 90, old: .chevronDown, to: .dots)
        #expect(c == d)
    }

    /// Renders the in-between frames of a few morphs to a strip, for looking at by eye
    /// (MAXQ_MORPH_FRAMES=/path/to/folder).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MAXQ_MORPH_FRAMES"] != nil))
    func rendersFrames() throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MAXQ_MORPH_FRAMES"]!)
        let pairs: [(String, MorphGlyph, MorphGlyph)] = [
            ("more-close", .more, .close), ("plus-close", .plus, .close), ("menu-close", .menu, .close),
            ("close-back", .close, .arrowLeft), ("chevron-dots", .chevronDown, .dots), ("down-up", .chevronDown, .chevronUp),
        ]
        for (name, from, to) in pairs {
            let (start, end) = MorphIcon.turn(from: from.rotation, old: from, to: to)
            let frames = (0...6).map { step -> AnyView in
                let t = Double(step) / 6
                let values = zip(from.lines, to.lines).map { $0 + ($1 - $0) * t }
                return AnyView(MorphLinesShape(lines: MorphLines(values: values))
                    .rotationEffect(.degrees(start + (end - start) * t))
                    .frame(width: 72, height: 72)
                    .foregroundStyle(Color.white))
            }
            let strip = HStack(spacing: 16) { ForEach(0..<frames.count, id: \.self) { frames[$0] } }
                .padding(16)
                .background(Color(red: 0.07, green: 0.07, blue: 0.07))
            let renderer = ImageRenderer(content: strip)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                Issue.record("render \(name)")
                continue
            }
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
