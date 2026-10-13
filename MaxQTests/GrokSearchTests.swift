//
//  GrokSearchTests.swift
//  Max Q
//

import Foundation
import Testing
@testable import MaxQ

struct WebSearchParsingTests {
    @Test func readsSnippetsWithTheMatchedWordsInBold() {
        let runs = WebSearchClient.snippetRuns("<strong>SpaceX&#x27;s</strong> <strong>Starship</strong> spacecraft   and Super Heavy rocket ")
        #expect(runs.first == SnippetRun(text: "SpaceX's", bold: true))
        #expect(runs.last == SnippetRun(text: " spacecraft and Super Heavy rocket", bold: false))
        #expect(runs.map(\.text).joined() == "SpaceX's Starship spacecraft and Super Heavy rocket")
        #expect(WebSearchClient.snippetRuns("  ").isEmpty)
        #expect(WebSearchClient.plainText("<p>Fourteen <b>flights</b>\n  so far &amp; counting</p>") == "Fourteen flights so far & counting")
    }

    @Test func decodesEntities() {
        #expect(WebSearchClient.decodeEntities("a &amp; b &lt;c&gt; &#x27;d&#39; &hellip;") == "a & b <c> 'd' …")
        #expect(WebSearchClient.decodeEntities("AT&T &unknown;") == "AT&T &unknown;")
    }

    @Test func breadcrumbs() {
        let result = WebResult(title: "t", url: URL(string: "https://en.wikipedia.org/wiki/SpaceX")!, snippet: [])
        #expect(result.breadcrumb == "en.wikipedia.org › wiki › SpaceX")
    }
}

struct XLinkTests {
    @Test func readsPostAddresses() {
        #expect(XLinks.postID(from: URL(string: "https://x.com/SpaceX/status/1975123456789012345")!) == "1975123456789012345")
        #expect(XLinks.postID(from: URL(string: "https://twitter.com/i/web/status/123?s=20")!) == "123")
        #expect(XLinks.postID(from: URL(string: "https://mobile.x.com/nasa/status/42/photo/1")!) == "42")
        #expect(XLinks.postID(from: URL(string: "https://x.com/SpaceX")!) == nil)
        #expect(XLinks.postID(from: URL(string: "https://example.com/a/status/1")!) == nil)
        #expect(XLinks.postID(from: URL(string: "https://x.com/a/status/12a")!) == nil)
        // Digits from other scripts aren't a post's id.
        #expect(XLinks.postID(from: URL(string: "https://x.com/a/status/%D9%A1%D9%A2")!) == nil)
    }

    @Test func namesWhosePostItIs() {
        #expect(XLinks.handle(ofPost: URL(string: "https://x.com/SpaceX/status/1")!) == "SpaceX")
        #expect(XLinks.handle(ofPost: URL(string: "https://twitter.com/elon_musk2/status/1")!) == "elon_musk2")
        #expect(XLinks.handle(ofPost: URL(string: "https://x.com/i/web/status/1")!) == nil)
        #expect(XLinks.handle(ofPost: URL(string: "https://x.com/SpaceX")!) == nil)
        #expect(XLinks.handle(ofPost: URL(string: "https://x.com/%C3%A9lan/status/1")!) == nil)
    }
}

@MainActor
struct GrokSearchBehaviourTests {
    @Test func skipsAnswersForSiteNames() {
        #expect(!GrokSearch.wantsAnswer("youtube"))
        #expect(!GrokSearch.wantsAnswer("gmail login"))
        #expect(!GrokSearch.wantsAnswer("apple.com"))
        #expect(GrokSearch.wantsAnswer("when is the next starship launch"))
        #expect(GrokSearch.wantsAnswer("mars"))
    }

    @Test func searchPagesRoundTrip() {
        for query in ["c++ tutorial", "what's 2+2?", "café & crème", "a/b?c=d#e"] {
            let url = MaxQScheme.searchURL(for: query)
            #expect(MaxQScheme.query(from: url) == query, "\(query)")
            #expect(SearchEngine.builtIn(.maxq)?.query(fromResultsURL: url!) == query, "\(query)")
        }
        #expect(MaxQScheme.query(from: URL(string: "maxq://search?q=")) == nil)
        #expect(MaxQScheme.query(from: URL(string: "https://search?q=x")) == nil)
        #expect(SessionStore.isRestorable(MaxQScheme.searchURL(for: "mars")!))
        #expect(!SessionStore.isRestorable(URL(string: "maxq://other")!))
    }

    @Test func pinnedSitesKeepTheirOwnLinks() {
        #expect(Launcher.x.keepsInPinnedTab(URL(string: "https://x.com/SpaceX")!))
        #expect(Launcher.x.keepsInPinnedTab(URL(string: "https://accounts.google.com/o/oauth2")!))
        #expect(!Launcher.x.keepsInPinnedTab(URL(string: "https://t.co/abc")!))
        #expect(!Launcher.grok.keepsInPinnedTab(URL(string: "https://x.com/SpaceX/status/1")!))
        #expect(Launcher.grok.keepsInPinnedTab(URL(string: "https://x.com/i/oauth2/authorize?x=1")!))
        #expect(Launcher.grokipedia.keepsInPinnedTab(URL(string: "https://grokipedia.com/page/Mars")!))
        #expect(!Launcher.grokipedia.keepsInPinnedTab(URL(string: "https://en.wikipedia.org/wiki/Mars")!))
        #expect(Launcher.x.isFrontPage(URL(string: "https://x.com/home")!))
        #expect(!Launcher.x.isFrontPage(URL(string: "https://x.com/SpaceX")!))
    }

    @Test func namesAreTidied() {
        #expect(AppSettings.cleanName("  Myrhex \n") == "Myrhex")
        #expect(AppSettings.cleanName(String(repeating: "a", count: 50)).count == 32)
    }
}

struct GrokWebSessionTests {
    private func cookie(_ name: String, _ domain: String, expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "token", .domain: domain, .path: "/"]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }

    @Test func recognisesAGrokSession() {
        let now = Date()
        #expect(GrokWebAccount.hasSession([cookie("sso", ".grok.com", expires: now.addingTimeInterval(3_600))], now: now))
        #expect(GrokWebAccount.hasSession([cookie("sso-rw", ".x.ai")], now: now))
        #expect(!GrokWebAccount.hasSession([cookie("sso", ".grok.com", expires: now.addingTimeInterval(-60))], now: now))
        #expect(!GrokWebAccount.hasSession([cookie("sso", ".evilgrok.com")], now: now))
        #expect(!GrokWebAccount.hasSession([cookie("session", ".grok.com")], now: now))
    }
}

struct GrokAnswerFormattingTests {
    @Test func citationsBecomeNamedChips() {
        let text = "Starship flew[[1]](https://www.spacex.com/a)[[2]](https://x.com/i/status/9) today. Then[[3]](https://en.wikipedia.org/wiki/X)."
        let converted = MarkdownParser.chipMarkers(text)
        #expect(converted == "Starship flew [\u{2063}SpaceX\u{00A0}+1](https://www.spacex.com/a) today. Then [\u{2063}Wikipedia](https://en.wikipedia.org/wiki/X).")
        let parsed = MarkdownParser.answerInline(text, chipSize: 13)
        let links = parsed.text.runs.compactMap { $0.link }
        #expect(links.map(\.absoluteString) == ["https://www.spacex.com/a", "https://en.wikipedia.org/wiki/X"])
        let plain = String(parsed.text.characters)
        #expect(plain.contains("flew \u{00A0}\u{00A0}SpaceX\u{00A0}+1\u{00A0}\u{00A0} today"))
        #expect(parsed.chips.count == 2)
        let first = parsed.chips[0]
        let chars = Array(plain)
        #expect(String(chars[first]) == "\u{00A0}\u{00A0}SpaceX\u{00A0}+1\u{00A0}\u{00A0}")
    }

    @Test func namesSourcesTheWayGrokDoes() {
        #expect(CitationLabel.label(for: URL(string: "https://techcrunch.com/2026/06/11/a")!) == "TechCrunch")
        #expect(CitationLabel.label(for: URL(string: "https://www.thinkgeoenergy.com/x")!) == "Thinkgeoenergy")
        #expect(CitationLabel.label(for: URL(string: "https://www.bbc.co.uk/news")!) == "BBC")
        #expect(CitationLabel.label(for: URL(string: "https://x.com/SpaceX/status/1")!) == "@SpaceX")
        #expect(CitationLabel.label(for: URL(string: "https://x.com/i/status/1")!) == "X")
        #expect(CitationLabel.label(for: URL(string: "https://x.com/i/status/1")!, handles: ["https://x.com/i/status/1": "@nasa"]) == "@nasa")
        #expect(CitationLabel.label(for: URL(string: "https://fr.wikipedia.org/wiki/A")!) == "Wikipedia")
    }

    @Test func holdsBackHalfAMarker() {
        #expect(MarkdownParser.withoutPartialCitation("It launched[[1]](https://spa") == "It launched")
        #expect(MarkdownParser.withoutPartialCitation("It launched[[") == "It launched")
        #expect(MarkdownParser.withoutPartialCitation("It launched[[1]](https://a.b)") == "It launched[[1]](https://a.b)")
        #expect(MarkdownParser.withoutPartialCitation("Plain text") == "Plain text")
    }

    @Test func citationNumbersAreNotTitles() {
        let numbered = GrokClient.citation(from: ["type": "url_citation", "url": "https://x.ai/news", "title": "3"])
        #expect(numbered?.title == nil)
        let titled = GrokClient.citation(from: ["url": "https://x.ai/news", "title": "News"])
        #expect(titled?.title == "News")
    }

    @Test func showsWhatGrokSearches() {
        let x = GrokClient.searchStatus(type: "response.custom_tool_call_input.done",
                                        json: ["input": #"{"query":"starship from:SpaceX filter:media","limit":20}"#])
        #expect(x == "Searching X for “starship”")
        let web = GrokClient.searchStatus(type: "response.output_item.done",
                                          json: ["item": ["type": "web_search_call", "action": ["type": "search", "query": "starship flight 14"]]])
        #expect(web == "Searched the web for “starship flight 14”")
        #expect(GrokClient.searchStatus(type: "response.custom_tool_call_input.done", json: ["input": #"{"query":"from:xai"}"#]) == nil)
    }
}

struct FollowUpTests {
    @Test func splitsSuggestionsFromTheAnswer() {
        let raw = """
        Starship is SpaceX's rocket.

        - It's the largest ever flown.
        ---follow-ups---
        1. When is the next launch?
        - How big is it?
        * Who builds it?
        A fourth one?
        """
        let split = GrokSearch.splitFollowUps(raw, finished: true)
        #expect(split.body == "Starship is SpaceX's rocket.\n\n- It's the largest ever flown.")
        #expect(split.questions == ["When is the next launch?", "How big is it?", "Who builds it?"])
    }

    @Test func holdsBackAMarkerStillStreaming() {
        #expect(GrokSearch.splitFollowUps("Answer.\n---fol").body == "Answer.")
        #expect(GrokSearch.splitFollowUps("Answer.\n- a bullet").body == "Answer.\n- a bullet")
        #expect(GrokSearch.splitFollowUps("Answer.\n---fol", finished: true).body == "Answer.\n---fol")
    }

    @Test func acceptsLooserMarkers() {
        #expect(GrokSearch.splitFollowUps("A.\n**Follow-ups:**\nWhy is that so?").questions == ["Why is that so?"])
        #expect(GrokSearch.splitFollowUps("A.\n--- Follow-ups ---\nWhy is that so?").questions == ["Why is that so?"])
        #expect(GrokSearch.splitFollowUps("Follow the money.\nWhy is that so?").questions.isEmpty)
    }
}

struct RichResultTests {
    private func result(_ address: String) -> WebResult {
        WebResult(title: "t", url: URL(string: address)!, snippet: [])
    }

    @Test func knowsVideos() {
        #expect(result("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3").youTubeID == "dQw4w9WgXcQ")
        #expect(result("https://youtu.be/dQw4w9WgXcQ").youTubeID == "dQw4w9WgXcQ")
        #expect(result("https://m.youtube.com/shorts/abcDEF12345").youTubeID == "abcDEF12345")
        #expect(result("https://www.youtube.com/@SpaceX").youTubeID == nil)
        #expect(result("https://example.com/watch?v=dQw4w9WgXcQ").youTubeID == nil)
        // A video's still is the search's own copy; nothing is fetched from YouTube for it.
        #expect(result("https://youtu.be/dQw4w9WgXcQ").thumbnail == nil)
        var video = result("https://youtu.be/dQw4w9WgXcQ")
        video.still = URL(string: "https://imgs.search.brave.com/v.jpg")
        #expect(video.thumbnail?.host == "imgs.search.brave.com")
        var page = result("https://example.com/a")
        page.still = URL(string: "https://imgs.search.brave.com/p.jpg")
        #expect(page.thumbnail == nil)
    }
}
