//
//  UnifiedSearchTests.swift
//  Max Q
//
//  The results page's sources: web results from the Brave Search API and when their pages
//  changed, Grokipedia's own search, and whole Grokipedia articles.
//

import Foundation
import Testing
@testable import MaxQ

struct ResultDateTests {
    @Test func readsWhenPagesChanged() throws {
        let results = BraveSearchClient.parseWeb(["web": ["results": [
            ["title": "SpaceX Starship", "url": "https://en.wikipedia.org/wiki/SpaceX_Starship", "page_age": "2026-10-05T00:00:00"],
            ["title": "Starship reaches Texas", "url": "https://www.caller.com/story", "page_age": "2026-10-09T13:41:00"],
            ["title": "No date", "url": "https://example.com/"],
        ]]]).results
        #expect(results.count == 3)
        // Midnight on the dot is a day, not a moment.
        let day = try #require(results[0].date)
        #expect(results[0].dateIsDay)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(utc.dateComponents([.year, .month, .day], from: day) == DateComponents(year: 2026, month: 10, day: 5))
        let moment = try #require(results[1].date)
        #expect(!results[1].dateIsDay)
        #expect(utc.dateComponents([.hour, .minute], from: moment) == DateComponents(hour: 13, minute: 41))
        #expect(results[2].date == nil)
        #expect(!results[2].dateIsDay)
    }

    @Test func saysWhenLikeAResultsPage() {
        let now = Date(timeIntervalSince1970: 1_791_633_600)  // 10 Oct 2026, noon UTC
        let english = Locale(identifier: "en_US"), french = Locale(identifier: "fr_FR")
        #expect(ResultDate.label(now.addingTimeInterval(-3 * 3_600), isDay: false, now: now, locale: english) == "3 hours ago")
        #expect(ResultDate.label(now.addingTimeInterval(-3 * 3_600), isDay: false, now: now, locale: french) == "il y a 3 heures")
        #expect(ResultDate.label(now.addingTimeInterval(-40 * 86_400), isDay: true, now: now, locale: english) == "Aug 31")
        #expect(ResultDate.label(now.addingTimeInterval(-400 * 86_400), isDay: true, now: now, locale: english) == "Sep 5, 2025")
    }

    @Test func timeFilterUsesBravesValues() {
        #expect(SearchTime.any.freshness == nil)
        #expect(SearchTime.allCases.compactMap(\.freshness) == ["pd", "pw", "pm", "py"])
    }

    @Test func readsBravesDates() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        // Without a zone, Brave's times are UTC.
        let plain = try #require(BraveSearchClient.date("2026-10-06T18:16:41"))
        #expect(utc.dateComponents(parts, from: plain) == DateComponents(year: 2026, month: 10, day: 6, hour: 18, minute: 16))
        let zoned = try #require(BraveSearchClient.date("2026-10-06T18:16:41+02:00"))
        #expect(utc.dateComponents(parts, from: zoned) == DateComponents(year: 2026, month: 10, day: 6, hour: 16, minute: 16))
        #expect(BraveSearchClient.date("2026-10-06") != nil)
        #expect(BraveSearchClient.date("last week") == nil)
        #expect(BraveSearchClient.date("") == nil)
        #expect(BraveSearchClient.date(nil) == nil)
        // A date years ahead is a mistake, not a page from the future.
        #expect(BraveSearchClient.date("2099-01-01T00:00:00") == nil)
        #expect(BraveSearchClient.isDay("2026-10-05T00:00:00"))
        #expect(BraveSearchClient.isDay("2026-10-05T00:00:00.000Z"))
        #expect(BraveSearchClient.isDay("2026-10-05"))
        #expect(!BraveSearchClient.isDay("2026-10-05T00:00:01"))
        #expect(!BraveSearchClient.isDay(nil))
    }
}

struct BraveWebTests {
    static let page: [String: Any] = [
        "query": ["original": "starship", "more_results_available": true,
                  "related_queries": ["starship <strong>launch</strong>", "starship flight 14", ""]],
        "web": ["results": [
            ["title": "SpaceX &amp; Starship", "url": "https://www.spacex.com/vehicles/starship/",
             "description": "<strong>SpaceX&#x27;s</strong> <strong>Starship</strong> spacecraft and Super Heavy rocket",
             "page_age": "2026-10-09T13:41:00", "meta_url": ["hostname": "www.spacex.com", "favicon": "https://imgs.search.brave.com/fav/spacex.png"]],
            ["title": "Flight 14", "url": "https://www.youtube.com/watch?v=abc123def",
             "thumbnail": ["src": "https://imgs.search.brave.com/th/abc.jpg"]],
            ["title": "The same page again", "url": "https://www.spacex.com/vehicles/starship/"],
            ["title": "", "url": "https://example.com/empty"],
            ["title": "Not a web page", "url": "javascript:alert(1)"],
            ["title": "No address"],
        ]],
    ]

    @Test func readsWebResults() throws {
        let page = BraveSearchClient.parseWeb(Self.page)
        #expect(page.results.count == 2)
        let first = page.results[0]
        #expect(first.title == "SpaceX & Starship")
        #expect(first.host == "spacex.com")
        #expect(first.snippet.first == SnippetRun(text: "SpaceX's", bold: true))
        #expect(first.plainSnippet == "SpaceX's Starship spacecraft and Super Heavy rocket")
        #expect(first.favicon?.absoluteString == "https://imgs.search.brave.com/fav/spacex.png")
        #expect(first.date != nil)
        // A video's still shows only for videos.
        #expect(first.thumbnail == nil)
        #expect(page.results[1].youTubeID == "abc123def")
        #expect(page.results[1].thumbnail?.absoluteString == "https://imgs.search.brave.com/th/abc.jpg")
        #expect(page.related == ["starship launch", "starship flight 14"])
        #expect(page.moreAvailable)
    }

    @Test func readsAnEmptyAnswer() {
        let page = BraveSearchClient.parseWeb([:])
        #expect(page.results.isEmpty)
        #expect(page.related.isEmpty)
        #expect(!page.moreAvailable)
    }

    /// Brave's answers when something's wrong, as it sends them (checked 2026-10-11).
    @Test func readsBravesErrors() {
        let wrongKey: [String: Any] = ["type": "ErrorResponse", "error": [
            "status": 422, "code": "SUBSCRIPTION_TOKEN_INVALID", "detail": "The provided API key is invalid.",
            "meta": ["component": "authentication"]]]
        #expect(BraveSearchClient.error(status: 422, json: wrongKey) == .invalidKey)
        #expect(BraveSearchClient.error(status: 401, json: [:]) == .invalidKey)
        #expect(BraveSearchClient.error(status: 429, json: ["error": ["code": "QUOTA_LIMITED"]]) == .outOfCredit)
        #expect(BraveSearchClient.error(status: 429, json: ["error": ["code": "RATE_LIMITED"]]) == .rateLimited)
        #expect(BraveSearchClient.error(status: 402, json: [:]) == .outOfCredit)
        #expect(BraveSearchClient.error(status: 422, json: ["error": ["code": "VALIDATION"]]) == .failed("HTTP 422"))
        #expect(BraveSearchClient.error(status: 500, json: [:]) == .failed("HTTP 500"))
        #expect(BraveSearchClient.error(status: 200, json: [:]) == nil)
    }
}

struct GrokipediaSearchTests {
    static let page = """
    <main><a href="/" class="logo">Grokipedia</a>
    <a data-slug="SpaceX" href="/page/SpaceX" data-search-result-link="" class="block" data-search-snippet="Space Exploration Technologies Corp. &amp; its &lt;b&gt;rockets&lt;/b&gt; &amp;amp; more">
      <h3 class="text-lg"><span>Space<span class="hl">X</span></span></h3>
      <p>Space Exploration Technologies…</p></a>
    <a href="/page/SpaceX_Starship" data-search-result-link="" data-slug="SpaceX_Starship" data-note="a > b" data-search-snippet="Fully reusable">
      <h3>
        SpaceX Starship
      </h3></a>
    <a href="/page/spacex" data-search-result-link="" data-slug="spacex"><h3>SpaceX again</h3></a>
    <a href="/page/Starbase" data-search-result-link="" data-slug="Starbase_(Texas)"></a>
    <a href="/page/Elsewhere" data-slug="Elsewhere"><h3>Not a result</h3></a>
    </main>
    """

    @Test func readsGrokipediasOwnSearch() {
        let results = GrokipediaSearchClient.parse(Self.page)
        #expect(results.map(\.slug) == ["SpaceX", "SpaceX_Starship", "Starbase_(Texas)"])
        #expect(results[0].title == "SpaceX")
        // Each entity is read once: "&amp;amp;" is a written "&amp;", and markup is dropped.
        #expect(results[0].snippet == "Space Exploration Technologies Corp. & its rockets &amp; more")
        #expect(results[0].url?.absoluteString == "https://grokipedia.com/page/SpaceX")
        // A heading over several lines, and a ">" inside an attribute, read as they should.
        #expect(results[1].title == "SpaceX Starship")
        #expect(results[1].snippet == "Fully reusable")
        // No heading: the title comes from the address.
        #expect(results[2].title == "Starbase (Texas)")
        #expect(results[2].snippet == "")
        #expect(GrokipediaSearchClient.parse("<p>No results</p>").isEmpty)
    }
}

struct GrokipediaArticleTests {
    static let page = """
    <html><head><script type="application/ld+json">{"dateModified":"2026-10-10T09:10:11.000Z"}</script></head><body>
    <aside class="infobox mb-8"> <div class="band"> <span class="block">SpaceX Starship</span> </div>
      <figure class="m-0"> <img src="https://assets.grokipedia.com/wiki/images/ceaf.jpg" alt="Launch">
      <figcaption class="px-3"> Starship ascending </figcaption> </figure>
      <dl class="m-0"> <div class="ib-row grid"> <dt class="font-medium">Height</dt> <dd class="m-0"> 120–150 m </dd> </div><div class="ib-row grid"> <dt>Variants</dt> <dd> <ul class="m-0"> <li class="ib-line"> tanker </li><li class="ib-line"> crew </li> </ul> </dd> </div> </dl>
    </aside>
    <!-- Article body — pre-rendered HTML, zero client JS --><div class="article-body"><span data-tts-block="true" class="mb-4 block"><a href="/page/SpaceX" class="text-blue-500">SpaceX</a> Starship is a <strong>fully reusable</strong> rocket.<sup class="text-fg-secondary"><a href="#ref-1"><sup class="text-fg-secondary"><a href="#ref-1">[1]</a></sup></a></sup><sup><a href="#ref-2"><sup><a href="#ref-2">[2]</a></sup></a></sup> It flies from <a href="https://www.starbase.texas.gov/">Starbase</a>.</span>
    <h2 id="design" class="group">Design<span class="ml-2"><button type="button" aria-label="Copy link"><svg><path d="M1"/></svg></button></span></h2>
    <h3 id="booster" class="group">Super Heavy &amp; Raptor</h3>
    <figure data-tts-block="true" class="mx-auto"><div class="relative"><img src="https://assets.grokipedia.com/wiki/images/43cd.jpg" alt="Engines" width="4096" height="2731" /></div><figcaption class="text-fg-secondary">The engine cluster</figcaption></figure>
    <div class="overflow-x-auto"><table class="w-full"><thead><tr><th><span>Flight</span></th><th><span>Date</span></th></tr></thead><tbody><tr><td><span>14</span></td><td><span>Sep 28, 2026</span></td></tr></tbody></table></div>
    <ul><li>First point with <em>emphasis</em></li><li>Second point</li></ul>
    </div><!-- Citations --><section id="references" class="references"><ol>
    <li id="ref-1" class="ref-row"><a href="#ref-1" class="ref-num">1<span>↑</span></a><div><a href="https://www.spacex.com/vehicles/starship" class="ref-link text-fg-secondary">SpaceX Starship Vehicle Page</a><span class="type-hint ml-1.5">spacex.com</span></div></li>
    <li id="ref-2" class="ref-row"><a href="#ref-2" class="ref-num">2</a><div><a href="https://www.faa.gov/x" class="ref-link">FAA licence</a><span class="type-hint">faa.gov</span></div></li>
    </ol></section></body></html>
    """

    @Test func readsTheWholeArticle() throws {
        let article = try #require(GrokipediaArticleParser.parse(Self.page))
        #expect(article.blocks.count == 6)
        guard case .paragraph(_, let runs) = article.blocks[0] else { Issue.record("no lead"); return }
        #expect(runs.first == GrokipediaRun(text: "SpaceX", kind: .article("SpaceX")))
        #expect(runs.contains(GrokipediaRun(text: "fully reusable", bold: true)))
        // Grokipedia nests each citation twice: each counts once, glued to its word.
        let citations = runs.compactMap { if case .citation(let number) = $0.kind { number } else { nil } }
        #expect(citations == [1, 2])
        #expect(runs.contains { $0.text == " rocket." })
        #expect(runs.contains { $0.kind == .link(URL(string: "https://www.starbase.texas.gov/")!) })
        #expect(article.blocks[1] == .heading(GrokipediaHeading(id: "design", level: 2, text: "Design")))
        #expect(article.blocks[2] == .heading(GrokipediaHeading(id: "booster", level: 3, text: "Super Heavy & Raptor")))
        guard case let .figure(_, image, caption, aspect) = article.blocks[3] else { Issue.record("no figure"); return }
        #expect(image.absoluteString == "https://assets.grokipedia.com/wiki/images/43cd.jpg")
        #expect(caption == "The engine cluster")
        #expect(aspect.map { abs($0 - 4096.0 / 2731.0) < 0.001 } == true)
        guard case let .table(_, header, rows) = article.blocks[4] else { Issue.record("no table"); return }
        #expect(header == ["Flight", "Date"])
        #expect(rows == [["14", "Sep 28, 2026"]])
        guard case let .list(_, ordered, items) = article.blocks[5] else { Issue.record("no list"); return }
        #expect(!ordered)
        #expect(items.count == 2)
        #expect(items[0].contains(GrokipediaRun(text: "emphasis", italic: true)))
        #expect(article.outline.map(\.id) == ["design", "booster"])
    }

    @Test func readsSourcesAndInfobox() throws {
        let article = try #require(GrokipediaArticleParser.parse(Self.page))
        #expect(article.references.map(\.number) == [1, 2])
        #expect(article.references[0].title == "SpaceX Starship Vehicle Page")
        #expect(article.references[0].site == "spacex.com")
        #expect(article.references[1].url?.host == "www.faa.gov")
        let infobox = try #require(article.infobox)
        #expect(infobox.title == "SpaceX Starship")
        #expect(infobox.image?.lastPathComponent == "ceaf.jpg")
        #expect(infobox.caption == "Starship ascending")
        #expect(infobox.facts == [KnowledgeFact(label: "Height", value: "120–150 m"), KnowledgeFact(label: "Variants", value: "tanker\ncrew")])
        #expect(article.wordCount > 10)
    }

    @Test func linksToArticlesReadBack() throws {
        let link = try #require(ArticleLinks.article("Raptor_(rocket_engine)", title: "Raptor"))
        let (page, title) = try #require(ArticleLinks.article(from: link))
        #expect(page == "Raptor_(rocket_engine)")
        #expect(title == "Raptor")
        #expect(ArticleLinks.citation(from: try #require(ArticleLinks.citation(12))) == 12)
        let url = try #require(MaxQScheme.searchURL(for: "Raptor", tab: .grokipedia, page: "Raptor_(rocket_engine)"))
        #expect(MaxQScheme.query(from: url) == "Raptor")
        #expect(MaxQScheme.tab(from: url) == .grokipedia)
        #expect(MaxQScheme.page(from: url) == "Raptor_(rocket_engine)")
        #expect(MaxQScheme.page(from: MaxQScheme.searchURL(for: "Raptor")) == nil)
    }
}
