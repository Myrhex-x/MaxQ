//
//  ContentTests.swift
//  Max Q
//

import AppKit
import Foundation
import Testing
@testable import MaxQ

struct MarkdownParserTests {
    @Test func splitsBlocks() {
        let blocks = MarkdownParser.parse("""
        ## Summary
        First line
        still the same paragraph.

        - one
          - nested
        1. first
        2) second
        > quoted
        ---
        ```swift
        let x = 1
        ```
        | a | b |
        |---|---|
        | 1 | 2 |
        """)
        #expect(blocks == [
            .heading(level: 2, text: "Summary"),
            .paragraph("First line\nstill the same paragraph."),
            .bullet(indent: 0, text: "one"),
            .bullet(indent: 1, text: "nested"),
            .numbered(number: "1", indent: 0, text: "first"),
            .numbered(number: "2", indent: 0, text: "second"),
            .quote("quoted"),
            .rule,
            .code(language: "swift", text: "let x = 1"),
            .table(["| a | b |", "|---|---|", "| 1 | 2 |"]),
        ])
    }

    @Test func unterminatedCodeStillRenders() {
        #expect(MarkdownParser.parse("```\ncode") == [.code(language: "", text: "code")])
    }

    @Test func hashtagsAreNotHeadings() {
        #expect(MarkdownParser.parse("#SpaceX launched") == [.paragraph("#SpaceX launched")])
    }

    @Test func onlyWebLinksStayClickable() {
        let safe = MarkdownParser.inline("[site](https://example.com) and [[1]](https://x.com/i/status/1)")
        #expect(safe.runs.compactMap(\.link).map(\.absoluteString) == ["https://example.com", "https://x.com/i/status/1"])
        let unsafe = MarkdownParser.inline("[click](javascript:alert(1)) [file](file:///etc/passwd)")
        #expect(unsafe.runs.compactMap(\.link).isEmpty)
    }
}

struct GrokSessionTextTests {
    @Test func composeMarksAttachedPagesAsUntrusted() {
        let text = GrokSession.compose(question: "What changed?", contexts: [
            PageContext(title: "Release notes", url: URL(string: "https://example.com/notes"), text: "Version 2 adds X."),
        ])
        #expect(text.hasPrefix("What changed?"))
        #expect(text.contains("untrusted web content"))
        #expect(text.contains("[Page 1] Release notes"))
        #expect(text.contains("URL: https://example.com/notes"))
        #expect(text.contains("Version 2 adds X."))
        #expect(GrokSession.compose(question: "Hi", contexts: []) == "Hi")
    }

    @Test func stripQuotesFromRewrites() {
        #expect(GrokSession.stripQuotes("\"Hello there\"") == "Hello there")
        #expect(GrokSession.stripQuotes("“Hello”") == "Hello")
        #expect(GrokSession.stripQuotes("\"\"\"\nHello\n\"\"\"") == "Hello")
        #expect(GrokSession.stripQuotes("Say \"hi\" now") == "Say \"hi\" now")
    }

    @Test func previewsAreShortAndSingleLine() {
        #expect(GrokSession.preview("short") == "short")
        let long = String(repeating: "word ", count: 30)
        let preview = GrokSession.preview(long, limit: 20)
        #expect(preview.count <= 21)
        #expect(preview.hasSuffix("…"))
        #expect(!GrokSession.preview("a\nb").contains("\n"))
    }
}

struct PageTranslatorTests {
    @Test func batchesRespectSizeLimits() {
        let strings = Array(repeating: String(repeating: "a", count: 1_000), count: 12)
        let batches = PageTranslator.batches(for: strings)
        #expect(batches.flatMap { $0 } == Array(0..<12))
        #expect(batches.allSatisfy { batch in batch.reduce(0) { $0 + strings[$1].count } <= PageTranslator.batchCharacters })

        let many = Array(repeating: "hi", count: 200)
        #expect(PageTranslator.batches(for: many).allSatisfy { $0.count <= PageTranslator.batchCount })
        #expect(PageTranslator.batches(for: []).isEmpty)
    }

    @Test func parseRejectsMisalignedAnswers() {
        #expect(PageTranslator.parse(#"{"translations":["Bonjour","Monde"]}"#, expected: 2) == ["Bonjour", "Monde"])
        #expect(PageTranslator.parse(#"{"translations":["Bonjour"]}"#, expected: 2) == nil)
        #expect(PageTranslator.parse("not json", expected: 1) == nil)
    }

    @Test func requestUsesAStrictSchema() throws {
        let request = PageTranslator.request(["Hello", "World"], language: "French", model: "grok-4.3")
        let body = request.body(stream: false)
        let text = try #require(body["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)
        let input = try #require(body["input"] as? [[String: String]])
        #expect(input[0]["content"]?.contains(#"["Hello","World"]"#) == true)
        #expect(input[0]["content"]?.contains("exactly 2 strings") == true)
    }
}

struct IconToneTests {
    private func image(fill: NSColor, inset: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset)).fill()
            return true
        }
    }

    @Test func detectsGlyphsThatWouldDisappear() {
        #expect(IconTone.measure(image(fill: .black, inset: 14)) == .darkGlyph)
        #expect(IconTone.measure(image(fill: .white, inset: 14)) == .lightGlyph)
        #expect(IconTone.measure(image(fill: .systemOrange, inset: 14)) == .neutral)
        // A full opaque square (no transparency) never needs a plate.
        let square = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill(); return true
        }
        #expect(IconTone.measure(square) == .neutral)
    }
}

struct GrokipediaTests {
    @Test func imageURLsNeverUseTheAPIOrSiteChrome() {
        #expect(GrokipediaArticleClient.normalizeImageURL("./_assets_/Starship_S20.jpg")?.absoluteString
                == "https://assets.grokipedia.com/wiki/images/Starship_S20.jpg")
        #expect(GrokipediaArticleClient.normalizeImageURL("https://grokipedia.com/api/og?title=Starship") == nil)
        #expect(GrokipediaArticleClient.normalizeImageURL("https://grokipedia.com/icon-512x512.png") == nil)
        #expect(GrokipediaArticleClient.normalizeImageURL("//assets.grokipedia.com/wiki/images/A.png")?.scheme == "https")
        #expect(GrokipediaArticleClient.normalizeImageURL("javascript:alert(1)") == nil)
    }

    @Test func cleansArticleText() {
        #expect(GrokipediaArticleClient.cleanupSpacing("SpaceX [1] builds [Starship](/Starship) , a rocket .")
                == "SpaceX builds Starship, a rocket.")
        #expect(GrokipediaArticleClient.cleanupSpacing("[[#History|Early history]] and [[Mars]]") == "Early history and Mars")
    }

    @Test func relevanceGateRejectsSubTopics() {
        #expect(GrokipediaService.subjectMatches(subject: "tor", groups: [["tor", "project"]]))
        #expect(GrokipediaService.subjectMatches(subject: "torproject", groups: [["tor", "project"]]))
        #expect(!GrokipediaService.subjectMatches(subject: "barack obama",
                                                  groups: [["barack", "obama", "2008", "presidential", "campaign"]]))
        #expect(!GrokipediaService.subjectMatches(subject: "", groups: [["anything"]]))
    }

    @Test func typoRescueIsTight() {
        #expect(GrokipediaService.isLikelyTypoCorrection(subject: "elon muskk", title: "Elon Musk"))
        #expect(!GrokipediaService.isLikelyTypoCorrection(subject: "mars", title: "Bars"))
        #expect(!GrokipediaService.isLikelyTypoCorrection(subject: "starship", title: "Starship"))
        #expect(GrokipediaService.editDistance("kitten", "sitting") == 3)
    }

    @Test func topicDetection() {
        #expect(KnowledgeQueryDetector.classify("SpaceX") != .none)
        #expect(KnowledgeQueryDetector.classify("who is elon musk") != .none)
        #expect(KnowledgeQueryDetector.classify("how to fix a flat tire") == .none)
        #expect(KnowledgeQueryDetector.classify("example.com") == .none)
        #expect(KnowledgeQueryDetector.classify("best laptops 2026 for students and gamers alike") == .none)
    }

    @Test func curatedEntitiesDontMisfire() {
        // Agent-only aliases from Searxly ("memphis", "chip facility") must not resolve to a card.
        #expect(OfficialEntityDatabase.entity(for: "memphis") == nil)
        #expect(OfficialEntityDatabase.entity(for: "chip facility") == nil)
        #expect(OfficialEntityDatabase.entity(for: "xai")?.primaryURL == "https://x.ai")
        #expect(EntityQueryMatcher.bestEntity(for: "the official tesla site")?.canonicalKey == "tesla")
    }
}

struct GrokipediaParsingTests {
    @Test func readsNestedSpansInsideTheLead() {
        let html = """
        <!-- Article body --><div class="article-body">\
        <span data-tts-block="true" class="block"><strong>Space Exploration Technologies Corp.</strong>, commonly known as \
        <strong>SpaceX</strong>, is an American company founded in 2002 by <span class="inline">Elon Musk</span>. \
        It designs, manufactures and launches rockets and spacecraft.</span>\
        <span data-tts-block="true"><strong>Founded</strong> March 14, 2002</span></div>
        """
        let blocks = GrokipediaArticleClient.ttsBlocks(in: html, limit: 10)
        #expect(blocks.count == 2)
        #expect(blocks[0].html.contains("Elon Musk</span>. It designs"))
        #expect(blocks[1].html.hasPrefix("<strong>Founded</strong>"))
    }

    /// The card's lead leaves out the article's citation markers, however Grokipedia nests them.
    @Test func leadLeavesOutCitationMarkers() {
        let html = """
        <!-- Article body --><div class="article-body">\
        <span data-tts-block="true" class="block">The <strong>James Webb Space Telescope</strong> is a large, infrared-optimized \
        space observatory, designed to study the early universe.<sup class="text-fg-secondary"><a href="#ref-1"><sup>\
        <a href="#ref-1">1</a></sup></a></sup><sup><a href="#ref-2">2</a></sup> Launched on December 25, 2021, it orbits \
        the Sun at the second Lagrange point.<sup><a href="#ref-3">[3]</a></sup></span></div>
        """
        let lead = GrokipediaArticleClient.extractFirstParagraph(from: html)
        #expect(lead == "The James Webb Space Telescope is a large, infrared-optimized space observatory, designed to study the early universe. Launched on December 25, 2021, it orbits the Sun at the second Lagrange point.")
    }
}

import WebKit

@MainActor
struct TrackerTests {
    @Test func knowsTrackersByAddress() {
        #expect(TrackerList.tracker(for: URL(string: "https://www.google-analytics.com/g/collect?v=2")!)?.company == "Google Analytics")
        #expect(TrackerList.tracker(for: URL(string: "https://stats.g.doubleclick.net/j/collect")!)?.company == "Google Ads")
        #expect(TrackerList.tracker(for: URL(string: "https://connect.facebook.net/en_US/fbevents.js")!)?.company == "Meta Pixel")
        #expect(TrackerList.tracker(for: URL(string: "https://www.facebook.com/tr?id=1&ev=PageView")!)?.company == "Meta Pixel")
        // Facebook's own pages, its login SDK and lookalike domains aren't trackers.
        #expect(TrackerList.tracker(for: URL(string: "https://www.facebook.com/trending")!) == nil)
        #expect(TrackerList.tracker(for: URL(string: "https://connect.facebook.net/en_US/sdk.js")!) == nil)
        #expect(TrackerList.tracker(for: URL(string: "https://notdoubleclick.net/x")!) == nil)
        #expect(TrackerList.tracker(for: URL(string: "https://x.com/home")!) == nil)
    }

    @Test func rulesCompileInWebKit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("maxq-rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try #require(WKContentRuleListStore(url: folder))
        let source = TrackerList.rules(allowing: ["example.com"])
        let compiled: Bool = await withCheckedContinuation { continuation in
            store.compileContentRuleList(forIdentifier: "test", encodedContentRuleList: source) { list, error in
                continuation.resume(returning: list != nil && error == nil)
            }
        }
        #expect(compiled)
    }

    @Test func namesSites() {
        #expect(TrackerBlocker.site("www.theverge.com") == "theverge.com")
        #expect(TrackerBlocker.site("news.bbc.co.uk") == "bbc.co.uk")
        #expect(TrackerBlocker.site(nil) == nil)
    }
}
