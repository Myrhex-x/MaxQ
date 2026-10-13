//
//  DesignTests.swift
//  Max Q
//

import Foundation
import SwiftUI
import Testing
@testable import MaxQ

struct SearchVerticalTests {
    @Test func readsGrokipediaAndXSearches() {
        let grokipedia = SearchVertical.detect(URL(string: "https://grokipedia.com/search?q=elon+musk")!)
        #expect(grokipedia?.vertical == .grokipedia)
        #expect(grokipedia?.query == "elon musk")

        let x = SearchVertical.detect(URL(string: "https://x.com/search?q=c%2B%2B&src=typed_query")!)
        #expect(x?.vertical == .x)
        #expect(x?.query == "c++")
    }

    @Test func ignoresOtherPages() {
        #expect(SearchVertical.detect(URL(string: "https://grokipedia.com/page/SpaceX")!) == nil)
        #expect(SearchVertical.detect(URL(string: "https://x.com/SpaceXAI")!) == nil)
        #expect(SearchVertical.detect(URL(string: "https://example.com/search?q=mars")!) == nil)
        #expect(SearchVertical.detect(URL(string: "https://x.com/search?q=")!) == nil)
    }
}

struct GrokipediaSectionTests {
    @Test func readsTopLevelSectionsAndSkipsFurniture() {
        let html = """
        <h2 id="history" class="font-serif">History</h2><p>…</p>
        <h2 id="technological-innovations" class="x">Technological Innovations</h2>
        <h2 id="references-title" class="type-display">References</h2>
        <h2 class="type-label">Contents</h2>
        <h2 id="contribute-title">Suggest an edit</h2>
        """
        let sections = GrokipediaArticleClient.extractSections(from: html)
        #expect(sections.map(\.id) == ["history", "technological-innovations"])
        #expect(sections.map(\.title) == ["History", "Technological Innovations"])
    }

    @Test func readsTheUpdateDate() {
        let html = #"<script type="application/ld+json">{"dateModified":"2026-10-01T14:13:30.000Z"}</script>"#
        let date = GrokipediaArticleClient.extractDateModified(from: html)
        #expect(date == ISO8601DateFormatter().date(from: "2026-10-01T14:13:30Z"))
        #expect(GrokipediaArticleClient.extractDateModified(from: "<p>no date</p>") == nil)
    }
}

@MainActor
struct MotionCurveTests {
    @Test func bezierHitsItsEnds() {
        for curve in [UnitBezier.spring, .expo, .standard] {
            #expect(abs(curve(0)) < 0.0001)
            #expect(abs(curve(1) - 1) < 0.0001)
        }
    }

    @Test func easeOutCurvesRiseFastAndNeverGoBack() {
        var previous = 0.0
        for step in 1...20 {
            let value = UnitBezier.spring(Double(step) / 20)
            #expect(value >= previous)
            previous = value
        }
        // Half way through, Grokipedia's spring curve is nearly there.
        #expect(UnitBezier.spring(0.5) > 0.85)
    }
}

@MainActor
struct IconTests {
    @Test func everyIconParsesToSomethingInsideTheGrid() {
        for icon in MQIcon.allCases {
            let path = SVGPath.parse(IconTests.pathData(for: icon))
            let bounds = path.boundingRect
            #expect(!path.isEmpty, "\(icon) is empty")
            #expect(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 24 && bounds.maxY <= 24, "\(icon) leaves the grid: \(bounds)")
        }
    }

    @Test func arcsBecomeCurves() {
        let circle = SVGPath.parse("M2 12A10 10 0 1 0 22 12A10 10 0 1 0 2 12Z")
        let bounds = circle.boundingRect
        #expect(abs(bounds.width - 20) < 0.5 && abs(bounds.height - 20) < 0.5)
    }

    /// Every icon's parts, joined.
    private static func pathData(for icon: MQIcon) -> String {
        icon.pathData
    }
}
