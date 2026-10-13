//
//  NewFeaturesTests.swift
//  MaxQTests
//
//  Images, News and Videos; the outlets' feeds; news stories and the timeline; primary-source labels; checks;
//  launches; Reader; link previews; video transcripts; research plans; iCloud merging; the
//  agent's safety rules; Grok's answer on other tabs.
//

import Foundation
import JavaScriptCore
import Testing
@testable import MaxQ

struct VerticalSearchTests {
    @Test func readsBraveNews() {
        let items = BraveSearchClient.parseNews(["results": [
            ["title": "SpaceX&#x27;s Starship flies", "url": "https://www.space.com/starship", "description": "It <strong>flew</strong>.",
             "page_age": "2026-10-09T13:41:00", "meta_url": ["hostname": "www.space.com"], "thumbnail": ["src": "https://imgs.search.brave.com/n/1.jpg"]],
            ["title": "The same report again", "url": "https://www.space.com/starship"],
            ["title": "Named outlet", "url": "https://apnews.com/a", "profile": ["name": "AP News"]],
            ["title": "", "url": "https://example.com/empty"],
            ["title": "Not a web page", "url": "javascript:alert(1)"],
        ]])
        #expect(items.count == 2)
        #expect(items[0].title == "SpaceX's Starship flies")
        #expect(items[0].excerpt == "It flew.")
        #expect(items[0].source == "space.com")
        #expect(items[0].host == "space.com")
        #expect(items[0].date != nil)
        #expect(items[0].image?.absoluteString == "https://imgs.search.brave.com/n/1.jpg")
        #expect(items[1].source == "AP News")
        #expect(items[1].date == nil)
        #expect(items.allSatisfy { $0.viaSearchAPI })
        #expect(BraveSearchClient.parseNews([:]).isEmpty)
    }

    /// Brave's terms allow its results only while they're shown: a saved story, video or result
    /// keeps its link and title, not the search's text or pictures. A feed's story keeps its own.
    @Test @MainActor func keepsOnlyLinksFromTheSearchAPI() {
        let found = BraveSearchClient.parseNews(["results": [
            ["title": "Starship flies", "url": "https://www.space.com/starship", "description": "It flew.",
             "thumbnail": ["src": "https://imgs.search.brave.com/n/1.jpg"], "meta_url": ["hostname": "www.space.com"]],
        ]])
        let saved = found[0].collectionItem
        #expect(saved.title == "Starship flies")
        #expect(saved.link?.absoluteString == "https://www.space.com/starship")
        #expect(saved.text == nil && saved.picture == nil)
        #expect(saved.source == "space.com")

        let fromFeed = RSSParser.parse(Data(NewsFeedTests.rss.utf8), outlet: "BBC News")[0]
        #expect(!fromFeed.viaSearchAPI)
        #expect(fromFeed.collectionItem.text == "The fourteenth flight.")
        #expect(fromFeed.collectionItem.picture?.host == "ichef.bbci.co.uk")
    }

    @Test func readsBravePicturesAndVideos() {
        let images = BraveSearchClient.parseImages(["results": [
            ["title": "A <strong>rocket</strong>", "url": "https://a.example/page",
             "thumbnail": ["src": "https://imgs.search.brave.com/i/1.jpg"],
             "properties": ["url": "https://a.example/big.jpg", "width": 1600, "height": 900]],
            ["title": "Same picture", "url": "https://a.example/other", "thumbnail": ["src": "https://imgs.search.brave.com/i/2.jpg"],
             "properties": ["url": "https://a.example/big.jpg"]],
            ["title": "Size from the thumbnail", "url": "https://b.example/page",
             "thumbnail": ["src": "https://imgs.search.brave.com/i/3.jpg", "width": 300, "height": 400],
             "properties": ["url": "https://b.example/tall.jpg"]],
            ["title": "No page", "thumbnail": ["src": "https://imgs.search.brave.com/i/4.jpg"], "properties": ["url": "https://c.example/c.jpg"]],
            ["title": "No thumbnail", "url": "https://d.example/page", "properties": ["url": "https://d.example/d.jpg"]],
        ]])
        #expect(images.map(\.title) == ["A rocket", "Size from the thumbnail"])
        #expect(abs(images[0].aspect - 16.0 / 9.0) < 0.001)
        #expect(images[0].site == "a.example")
        #expect(images[0].thumbnail.host == "imgs.search.brave.com")
        #expect(images[1].width == 300 && images[1].height == 400)

        let videos = BraveSearchClient.parseVideos(["results": [
            ["title": "Flight 14", "url": "https://www.youtube.com/watch?v=abc123", "description": "The <strong>whole</strong> flight",
             "page_age": "2026-10-06T18:16:41", "thumbnail": ["src": "https://imgs.search.brave.com/v/1.jpg"],
             "video": ["duration": "1:02:05", "views": 120_000, "creator": "SpaceX", "publisher": "YouTube"]],
            ["title": "Views as text", "url": "https://vimeo.com/1",
             "video": ["duration": "", "views": "5400", "author": ["name": "NASA &amp; friends"]]],
            ["title": "", "url": "https://example.com/v"],
        ]])
        #expect(videos.count == 2)
        let video = videos[0]
        #expect(video.summary == "The whole flight")
        #expect(video.still?.absoluteString == "https://imgs.search.brave.com/v/1.jpg")
        #expect(video.views == 120_000)
        #expect(video.duration == "1:02:05")
        #expect(video.uploader == "SpaceX")
        #expect(video.publisher == "YouTube")
        #expect(video.youTubeID == "abc123")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: video.published!)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 6 && parts.hour == 18 && parts.minute == 16)
        #expect(videos[1].views == 5_400)
        #expect(videos[1].duration == nil)
        #expect(videos[1].uploader == "NASA & friends")
        #expect(videos[1].youTubeID == nil)
    }

    @Test func filtersPicturesBySizeAndShape() {
        func item(_ width: Int, _ height: Int) -> ImageItem {
            ImageItem(title: "", image: URL(string: "https://a.example/\(width)x\(height).jpg")!, thumbnail: URL(string: "https://t.example/t.jpg")!,
                      page: URL(string: "https://a.example/")!, width: width, height: height)
        }
        // With no filter, every picture shows, even one whose size isn't known.
        #expect(ImageFilters().matches(item(0, 0)))
        #expect(ImageFilters().isDefault)
        #expect(!ImageFilters(size: .large).matches(item(0, 0)))
        #expect(ImageFilters(size: .small).matches(item(500, 300)))
        #expect(!ImageFilters(size: .small).matches(item(800, 600)))
        #expect(ImageFilters(size: .medium).matches(item(1200, 800)))
        #expect(!ImageFilters(size: .medium).matches(item(1600, 900)))
        #expect(ImageFilters(size: .large).matches(item(1600, 900)))
        #expect(ImageFilters(size: .wallpaper).matches(item(1920, 1080)))
        #expect(!ImageFilters(size: .wallpaper).matches(item(1080, 1920)))
        #expect(ImageFilters(layout: .square).matches(item(1000, 1000)))
        #expect(ImageFilters(layout: .square).matches(item(1100, 1000)))
        #expect(!ImageFilters(layout: .square).matches(item(1200, 1000)))
        #expect(ImageFilters(layout: .tall).matches(item(800, 1200)))
        #expect(!ImageFilters(layout: .tall).matches(item(1200, 800)))
        #expect(ImageFilters(layout: .wide).matches(item(1600, 900)))
        #expect(ImageFilters(size: .large, layout: .wide).matches(item(1920, 1080)))
        #expect(!ImageFilters(size: .large, layout: .tall).matches(item(1920, 1080)))
    }

    @Test func filtersVideosByLength() {
        func video(_ duration: String?) -> VideoItem {
            VideoItem(title: "v", url: URL(string: "https://v.example/1")!, summary: "", still: nil, duration: duration,
                      publisher: nil, uploader: nil, published: nil, views: nil)
        }
        #expect(VideoFilters.seconds("8:39") == 519)
        #expect(VideoFilters.seconds("1:02:05") == 3_725)
        #expect(VideoFilters.seconds("0:00") == 0)
        #expect(VideoFilters.seconds("45") == nil)
        #expect(VideoFilters.seconds("1:xx:30") == nil)
        #expect(VideoFilters.seconds("1::30") == nil)
        #expect(VideoFilters.seconds("") == nil)
        // How recent is Brave's to filter; how long is Max Q's.
        #expect(VideoFilters(time: .day).matches(video(nil)))
        #expect(VideoFilters().matches(video(nil)))
        #expect(!VideoFilters(length: .short).matches(video(nil)))
        #expect(VideoFilters(length: .short).matches(video("3:59")))
        #expect(!VideoFilters(length: .short).matches(video("4:00")))
        #expect(VideoFilters(length: .medium).matches(video("4:00")))
        #expect(VideoFilters(length: .medium).matches(video("20:00")))
        #expect(!VideoFilters(length: .medium).matches(video("20:01")))
        #expect(VideoFilters(length: .long).matches(video("1:02:05")))
        #expect(!VideoFilters(length: .long).matches(video("12:00")))
    }

    @Test func laysPicturesInRows() {
        func item(_ width: Int, _ height: Int, _ index: Int) -> ImageItem {
            ImageItem(title: "", image: URL(string: "https://a.example/\(index).jpg")!, thumbnail: URL(string: "https://t.example/\(index).jpg")!,
                      page: URL(string: "https://a.example/\(index)")!, width: width, height: height)
        }
        let items = (0..<7).map { item($0 == 3 ? 4000 : 1200, $0 == 3 ? 500 : 800, $0) }
        let rows = ImageWall.rows(items, width: 900, target: 200, spacing: 8)
        #expect(rows.flatMap { $0 }.map(\.index) == Array(0..<7))
        // Full rows fill the width (give or take the rounding), at about the target height.
        for row in rows.dropLast() {
            let filled = row.reduce(0) { $0 + $1.width } + 8 * CGFloat(row.count - 1)
            #expect(abs(filled - 900) <= CGFloat(row.count))
            #expect(row[0].height <= 200)
        }
        // A panorama is kept within 2.6 times as wide as tall.
        let panorama = rows.flatMap { $0 }.first { $0.index == 3 }!
        #expect(panorama.width / panorama.height <= 2.61)
        #expect(ImageWall.rows(items, width: 0, target: 200, spacing: 8).isEmpty)
    }
}

struct NewsFeedTests {
    static let rss = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
    <channel>
      <title>BBC News</title>
      <link>https://www.bbc.co.uk/news</link>
      <image><url>https://news.bbcimg.co.uk/logo.gif</url><title>BBC News</title><link>https://www.bbc.co.uk/news</link></image>
      <item>
        <title>An older story</title>
        <link>https://www.bbc.co.uk/news/articles/a2</link>
        <pubDate>Fri, 09 Oct 2026 21:00:00 GMT</pubDate>
        <enclosure url="http://insecure.example/a2.jpg" type="image/jpeg" length="1"/>
      </item>
      <item>
        <title><![CDATA[Starship flies again & lands]]></title>
        <description><![CDATA[<p>The <b>fourteenth</b> flight.</p>]]></description>
        <link>https://www.bbc.co.uk/news/articles/a1</link>
        <pubDate>Sat, 10 Oct 2026 08:30:00 +0200</pubDate>
        <media:thumbnail width="240" height="135" url="https://ichef.bbci.co.uk/a1.jpg"/>
      </item>
      <item>
        <title>No link</title>
      </item>
      <item>
        <title>Picture in the text</title>
        <link>https://www.bbc.co.uk/news/articles/a3</link>
        <content:encoded><![CDATA[<figure><img src="https://example.com/a3.jpg?w=1&amp;h=2" alt=""></figure><p>Body</p>]]></content:encoded>
      </item>
    </channel>
    </rss>
    """

    static let atom = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>The Verge</title>
      <link rel="alternate" href="https://www.theverge.com/"/>
      <entry>
        <title type="html">Apple&#8217;s new Mac</title>
        <link rel="replies" href="https://www.theverge.com/2026/10/9/mac#comments"/>
        <link rel="alternate" type="text/html" href="https://www.theverge.com/2026/10/9/mac"/>
        <published>2026-10-09T14:00:00-04:00</published>
        <updated>2026-10-10T09:00:00-04:00</updated>
        <summary type="html">A &lt;em&gt;faster&lt;/em&gt; chip.</summary>
      </entry>
    </feed>
    """

    static let rdf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel rdf:about="https://www.dw.com/"><title>DW</title><link>https://www.dw.com/</link></channel>
      <item rdf:about="https://www.dw.com/en/a-1">
        <title>Germany votes</title>
        <link>https://www.dw.com/en/a-1</link>
        <description>Polls closed.</description>
        <dc:date>2026-10-10T07:15:00Z</dc:date>
      </item>
    </rdf:RDF>
    """

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func readsRSS() throws {
        let items = RSSParser.parse(Data(Self.rss.utf8), outlet: "BBC News")
        #expect(items.map(\.url.lastPathComponent) == ["a1", "a2", "a3"])
        let first = items[0]
        #expect(first.title == "Starship flies again & lands")
        #expect(first.excerpt == "The fourteenth flight.")
        #expect(first.source == "BBC News")
        #expect(first.image?.absoluteString == "https://ichef.bbci.co.uk/a1.jpg")
        let date = try #require(first.date)
        #expect(utc.dateComponents([.day, .hour, .minute], from: date) == DateComponents(day: 10, hour: 6, minute: 30))
        // Pictures over http aren't shown.
        #expect(items[1].image == nil)
        #expect(items[2].image?.absoluteString == "https://example.com/a3.jpg?w=1&h=2")
        #expect(items[2].excerpt == "Body")
        #expect(items[2].date == nil)
    }

    @Test func readsAtomAndRDF() throws {
        let atom = RSSParser.parse(Data(Self.atom.utf8), outlet: "The Verge")
        #expect(atom.count == 1)
        #expect(atom.first?.title == "Apple\u{2019}s new Mac")
        #expect(atom.first?.url.absoluteString == "https://www.theverge.com/2026/10/9/mac")
        #expect(atom.first?.excerpt == "A faster chip.")
        let published = try #require(atom.first?.date)
        #expect(utc.dateComponents([.day, .hour], from: published) == DateComponents(day: 9, hour: 18))

        let rdf = RSSParser.parse(Data(Self.rdf.utf8), outlet: "DW")
        #expect(rdf.map(\.title) == ["Germany votes"])
        #expect(rdf.first?.excerpt == "Polls closed.")
        #expect(rdf.first?.date != nil)
        #expect(RSSParser.parse(Data("not a feed".utf8), outlet: "x").isEmpty)
    }

    @Test func readsFeedDates() throws {
        let rfc = try #require(RSSParser.date("Sat, 10 Oct 2026 08:30:00 +0200"))
        #expect(utc.dateComponents([.day, .hour, .minute], from: rfc) == DateComponents(day: 10, hour: 6, minute: 30))
        let gmt = try #require(RSSParser.date("Fri, 09 Oct 2026 21:00:00 GMT"))
        #expect(utc.dateComponents([.day, .hour], from: gmt) == DateComponents(day: 9, hour: 21))
        #expect(RSSParser.date("Fri, 9 Oct 2026 21:00:00 +0000") != nil)
        #expect(RSSParser.date("2026-10-10T07:15:00.123Z") != nil)
        #expect(RSSParser.date("yesterday") == nil)
        #expect(RSSParser.firstImage(in: #"<p>Hi</p><img alt="x" src='https://a.example/i.png'>"#)?.absoluteString == "https://a.example/i.png")
        #expect(RSSParser.firstImage(in: "<p>No picture</p>") == nil)
    }

    @Test func findsStoriesForASearch() {
        let now = Date(timeIntervalSince1970: 1_791_633_600)  // 10 Oct 2026, noon UTC
        func item(_ title: String, _ path: String, hoursAgo: Double?, excerpt: String = "") -> NewsItem {
            NewsItem(title: title, url: URL(string: "https://news.example/\(path)")!, excerpt: excerpt, source: "Example",
                     date: hoursAgo.map { now.addingTimeInterval(-$0 * 3_600) }, image: nil)
        }
        let items = [
            item("Élection présidentielle : le premier tour", "a", hoursAgo: 2),
            item("Starship flies again", "b", hoursAgo: 30, excerpt: "SpaceX's rocket"),
            item("Starship news roundup", "c", hoursAgo: 3),
            item("Starship flies again (updated)", "b", hoursAgo: 1),
            item("Starship, undated", "e", hoursAgo: nil),
            item("Stars align", "f", hoursAgo: 1),
        ]
        func paths(_ query: String, _ time: SearchTime) -> [String] {
            NewsFeedClient.matching(query, within: time, in: items, now: now).map(\.url.lastPathComponent)
        }
        // Every word of the search, without accents or case; each story once; newest first.
        #expect(paths("starship", .any) == ["b", "c", "e"])
        #expect(paths("starship", .day) == ["b", "c"])
        #expect(paths("Starship SpaceX", .any) == ["b"])
        #expect(paths("election presidentielle", .any) == ["a"])
        #expect(paths("the", .any).isEmpty)
        #expect(paths("", .any).isEmpty)
    }

    @Test @MainActor func everyTopicHasItsOwnFeeds() {
        for language in ["en", "fr"] {
            let top = NewsFeedCatalog.feeds(for: "top", language: language)
            #expect(!top.isEmpty)
            for topic in HomeNewsFeed.topics where topic.id != "top" {
                let feeds = NewsFeedCatalog.feeds(for: topic.id, language: language)
                #expect(!feeds.isEmpty && feeds != top, "\(topic.id) in \(language)")
            }
            #expect(NewsFeedCatalog.feeds(for: "nothing", language: language) == top)
            let all = NewsFeedCatalog.allFeeds(language: language)
            #expect(Set(all.map(\.url)).count == all.count)
            #expect(all.allSatisfy { $0.url.scheme == "https" })
        }
        #expect(NewsFeedCatalog.feeds(for: "space", language: "fr").map(\.outlet).contains("Futura"))
        #expect(NewsFeedClient.userAgent.hasPrefix("MaxQ/"))
    }
}

struct NewsStoryTests {
    private func item(_ title: String, _ source: String, _ path: String, minutesAgo: Double = 30) -> NewsItem {
        NewsItem(title: title, url: URL(string: "https://\(source.lowercased()).example/\(path)")!, excerpt: "", source: source,
                 date: Date().addingTimeInterval(-minutesAgo * 60), image: nil)
    }

    @Test func groupsReportsOfOneEvent() {
        let items = [
            item("Starship completes its first orbital flight test", "Reuters", "a"),
            item("Starship completes first orbital flight test, SpaceX says", "AP", "b"),
            item("NASA picks a new lunar lander for Artemis", "Space", "c"),
            item("SpaceX Starship completes orbital flight test", "Reuters", "d"),
        ]
        let stories = NewsClustering.stories(items, query: "starship")
        #expect(stories.count == 2)
        #expect(stories[0].lead.source == "Reuters")
        // One report per outlet: the second from Reuters isn't listed again.
        #expect(stories[0].others.map(\.source) == ["AP"])
        #expect(stories[1].sourceCount == 1)
    }

    @Test func comparesWordsWithoutAccentsOrCase() {
        #expect(NewsClustering.words("Élection présidentielle: le PREMIER tour", minimumLength: 3)
            == ["election", "presidentielle", "premier", "tour"])
        #expect(NewsClustering.similarity(["a", "b", "c"], ["a", "b", "c", "d"]) == 1)
        #expect(NewsClustering.similarity(["a"], ["b"]) == 0)
        #expect(NewsClustering.similarity([], ["b"]) == 0)
    }

    @Test func callsSeveralRecentOutletsBreaking() {
        let lead = item("Engine fire at the launch site", "Reuters", "1", minutesAgo: 20)
        let others = [item("Fire at the launch site", "AP", "2", minutesAgo: 40), item("Launch site fire", "BBC", "3", minutesAgo: 50)]
        #expect(NewsStory(lead: lead, others: others).isBreaking)
        #expect(!NewsStory(lead: lead, others: []).isBreaking)
    }

    @Test func groupsTheTimelineByDayThenMonth() {
        let now = Date()
        func entry(_ id: String, daysAgo: Double) -> TimelineEntry {
            let news = NewsItem(title: id, url: URL(string: "https://n.example/\(id)")!, excerpt: "", source: "N", date: nil, image: nil)
            return TimelineEntry(id: id, date: now.addingTimeInterval(-daysAgo * 86_400), isDay: false, kind: .news(news))
        }
        let groups = NewsTimeline.groups([entry("a", daysAgo: 0), entry("b", daysAgo: 0.01), entry("c", daysAgo: 1), entry("d", daysAgo: 60)], now: now)
        #expect(groups.first?.title == String(localized: "Today"))
        #expect(groups.first?.entries.count == 2)
        #expect(groups.last?.isMonth == true)
    }
}

struct SourceLabelTests {
    @Test func marksPrimarySources() {
        func label(_ address: String, query: String = "", official: Set<String> = []) -> SourceLabel? {
            SourceLabels.label(for: URL(string: address)!, query: query, officialHosts: official)
        }
        #expect(label("https://www.spacex.com/vehicles/starship/", official: ["spacex.com"]) == .official)
        #expect(label("https://openai.com/index", query: "Open AI") == .official)
        #expect(label("https://www.nasa.gov/artemis") == .government)
        #expect(label("https://www.service-public.fr/particuliers") == .government)
        #expect(label("https://www.who.int/news") == .international)
        #expect(label("https://arxiv.org/abs/2401.00001") == .paper)
        #expect(label("https://www.nature.com/articles/s41586-024-1") == .paper)
        #expect(label("https://www.nature.com/news") == nil)
        #expect(label("https://www.prnewswire.com/news-releases/x.html") == .pressRelease)
        #expect(label("https://www.theverge.com/2026/10/1/starship") == nil)
    }

    @Test func readsRegisteredDomains() {
        #expect(SourceLabels.registeredDomain("www.bbc.co.uk") == "bbc.co.uk")
        #expect(SourceLabels.registeredDomain("news.example.com") == "example.com")
        #expect(SourceLabels.registeredDomain("www.impots.gouv.fr") == "impots.gouv.fr")
        #expect(SourceLabels.registeredDomain("localhost") == "localhost")
    }
}

struct ClaimCheckTests {
    @Test func readsAVerdictAndItsPoints() {
        let text = """
        **Verdict:** Mostly supported
        Summary: The flight happened, but not on the date the post gives.
        + SpaceX's own page confirms the flight [[1]](https://spacex.com).
        - The date was a day later [[2]](https://example.com).
        ~ The post is from a fan account.
        """
        let parsed = ClaimCheck.parse(text, finished: true)
        #expect(parsed.verdict == .mostlySupported)
        #expect(parsed.summary.hasPrefix("The flight happened"))
        #expect(parsed.points.map(\.stance) == [.supports, .contradicts, .context])
    }

    @Test func leavesAHalfWrittenLineForLater() {
        let parsed = ClaimCheck.parse("Verdict: False\nSummary: No.\n+ Half a sen", finished: false)
        #expect(parsed.verdict == .contradicted)
        #expect(parsed.points.isEmpty)
    }

    @Test func readsVerdictsInOtherWords() {
        #expect(ClaimVerdict(parsing: "TRUE.") == .supported)
        #expect(ClaimVerdict(parsing: "Missing context") == .misleading)
        #expect(ClaimVerdict(parsing: "insufficient evidence") == .unverified)
        #expect(ClaimVerdict(parsing: "probably") == nil)
    }
}

struct LaunchTests {
    @Test func noticesLaunchSearches() {
        #expect(LaunchQuery.detect("next starship launch") == "starship")
        #expect(LaunchQuery.detect("when is the next falcon 9") == "falcon 9")
        #expect(LaunchQuery.detect("prochain lancement") == "")
        #expect(LaunchQuery.detect("upcoming launches") == "")
        #expect(LaunchQuery.detect("starship engine design") == nil)
        #expect(LaunchQuery.detect("pizza near me") == nil)
    }

    @Test func readsLaunchLibrary() {
        let json: [String: Any] = ["results": [
            ["id": "b", "name": "Falcon 9 | Starlink", "net": "2026-11-02T10:00:00Z",
             "net_precision": ["abbrev": "MIN", "name": "Minute"], "status": ["abbrev": "Go", "name": "Go for Launch"],
             "launch_service_provider": ["name": "SpaceX"], "rocket": ["configuration": ["full_name": "Falcon 9 Block 5"]],
             "mission": ["name": "Starlink Group 12", "orbit": ["name": "Low Earth Orbit"]],
             "pad": ["name": "SLC-40", "location": ["name": "Cape Canaveral, FL, USA"]],
             "image": ["thumbnail_url": "https://img.example/f9.jpg"],
             "vid_urls": [["url": "https://youtube.com/b2", "priority": 5], ["url": "https://youtube.com/b1", "priority": 1]]],
            ["id": "a", "name": "Starship | Flight 15", "net": "2026-10-30T12:00:00Z", "net_precision": ["abbrev": "MONTH"]],
            ["id": "x", "name": "No date"],
        ]]
        let launches = LaunchClient.parse(json)
        #expect(launches.map(\.id) == ["a", "b"])
        #expect(launches[0].hasFirmTime == false)
        let falcon = launches[1]
        #expect(falcon.hasFirmTime)
        #expect(falcon.rocket == "Falcon 9 Block 5")
        #expect(falcon.orbit == "Low Earth Orbit")
        #expect(falcon.location == "Cape Canaveral, FL, USA")
        #expect(falcon.image?.absoluteString == "https://img.example/f9.jpg")
        #expect(falcon.webcast?.absoluteString == "https://youtube.com/b1")
    }
}

struct ReaderAndPreviewTests {
    @Test func makesAnArticleFromThePage() {
        let paragraph = Array(repeating: "word", count: 50).joined(separator: " ")
        let json: [String: Any] = [
            "title": "A long read", "site": "Example News", "lang": "en-GB", "published": "2026-10-01T08:00:00Z",
            "blocks": [
                ["k": "h", "t": "The start", "l": 2],
                ["k": "p", "r": [["t": paragraph], ["t": " a link", "href": "https://example.com/x"], ["t": " bad", "href": "javascript:x"]]],
                ["k": "h", "t": "The start", "l": 7],
                ["k": "ul", "items": [[["t": paragraph]], []]],
                ["k": "img", "src": "https://example.com/pic.jpg", "w": 1200, "h": 600, "cap": "A picture"],
                ["k": "img", "src": "data:image/png;base64,xx"],
                ["k": "table", "head": ["A", "B"], "rows": [["1", "2"]]],
            ],
        ]
        let document = ReaderDocument.make(json, url: URL(string: "https://www.example.com/read")!)!
        #expect(document.title == "A long read")
        #expect(document.site == "Example News")
        #expect(document.language == "en")
        #expect(document.published != nil)
        let headings = document.article.blocks.compactMap { block -> GrokipediaHeading? in
            if case .heading(let heading) = block { heading } else { nil }
        }
        // The same heading twice gets two ids, and levels stay between 2 and 4.
        #expect(Set(headings.map(\.id)).count == 2)
        #expect(headings.map(\.level) == [2, 4])
        #expect(document.article.blocks.count == 6)
        if case .paragraph(_, let runs) = document.article.blocks[1] {
            #expect(runs.count == 3)
            #expect(runs[2].kind == .text)
        }
        // Too short to be an article.
        #expect(ReaderDocument.make(["blocks": [["k": "p", "r": [["t": "Hello"]]]]], url: URL(string: "https://a.example")!) == nil)
    }

    @Test func readsLinkPreviewMetadata() {
        let html = """
        <html><head><title>Fallback title</title>
        <meta property="og:title" content="Starship &amp; Super Heavy">
        <meta content="The whole stack." name="description">
        <meta property="og:image" content="/images/stack.jpg">
        <meta property="og:site_name" content="SpaceX">
        </head><body>
        """
        let info = LinkPreviewClient.parse(html, url: URL(string: "https://www.spacex.com/vehicles/starship/")!)
        #expect(info?.title == "Starship & Super Heavy")
        #expect(info?.summary == "The whole stack.")
        #expect(info?.image?.absoluteString == "https://www.spacex.com/images/stack.jpg")
        #expect(info?.site == "SpaceX")
        let plain = LinkPreviewClient.parse("<title>Only a title</title>", url: URL(string: "https://www.example.org/a")!)
        #expect(plain?.title == "Only a title")
        #expect(plain?.site == "example.org")
        #expect(LinkPreviewClient.parse("<p>No title</p>", url: URL(string: "https://example.org")!) == nil)
    }

    @Test func readsVideoTranscripts() {
        #expect(VideoTranscript.stamp(190) == "03:10")
        #expect(VideoTranscript.stamp(3725) == "1:02:05")
        #expect(VideoTranscript.stamp(-4) == "00:00")
        let transcript = VideoTranscript(videoID: "x", title: "t", author: nil, language: "en", length: 60, segments: [
            .init(start: 0, text: "hello"), .init(start: 5, text: "there"), .init(start: 20, text: "later"),
        ])
        #expect(transcript.lines() == "[00:00] hello there\n[00:20] later")
        #expect(VideoPages.isVideo(URL(string: "https://www.youtube.com/watch?v=abc")))
        #expect(VideoPages.isVideo(URL(string: "https://youtube.com/shorts/abc")))
        #expect(!VideoPages.isVideo(URL(string: "https://www.youtube.com/@SpaceX")))
        #expect(!VideoPages.isVideo(URL(string: "https://vimeo.com/1")))
    }

    @Test func readsResearchPlans() {
        let plan = ResearchStore.parsePlan(#"{"title":"Starship","questions":["What is it?"," ","When does it fly?"]}"#, fallback: "starship")
        #expect(plan.title == "Starship")
        #expect(plan.questions == ["What is it?", "When does it fly?"])
        let broken = ResearchStore.parsePlan("not json", fallback: "starship")
        #expect(broken.title == "starship" && broken.questions == ["starship"])
    }
}

struct NewBangTests {
    @Test func opensMaxQsOwnTabs() {
        #expect(Bangs.find("i")?.target == .maxQ(.images))
        #expect(Bangs.find("img")?.target == .maxQ(.images))
        #expect(Bangs.find("news")?.target == .maxQ(.news))
        #expect(Bangs.find("n")?.target == .maxQ(.news))
        #expect(Bangs.find("v")?.target == .maxQ(.videos))
        #expect(Bangs.find("research")?.target == .research)
        #expect(Bangs.find("deep")?.target == .research)
        #expect(Bangs.find("imagine")?.target == .imagine)
        #expect(Bangs.parse("!i saturn v")?.words == "saturn v")
    }
}

struct CloudSyncTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func entry(_ text: String, _ seconds: Double) -> SyncDocument.Entry {
        SyncDocument.Entry(data: Data(text.utf8), modified: t0.addingTimeInterval(seconds))
    }

    @Test func mergesItemByItem() {
        var a = SyncDocument()
        a.entries = ["x": entry("x from A", 10), "y": entry("y", 0)]
        var b = SyncDocument()
        b.entries = ["x": entry("x from B", 20), "z": entry("z", 0)]
        b.removed = ["y": t0.addingTimeInterval(5)]
        let merged = SyncDocument.merge(a, b, now: t0.addingTimeInterval(30))
        #expect(merged.entries["x"]?.data == Data("x from B".utf8))
        #expect(merged.entries["z"] != nil)
        // Removed after its last change: gone.
        #expect(merged.entries["y"] == nil)
        #expect(merged.removed["y"] != nil)
        // The same both ways round.
        #expect(SyncDocument.merge(b, a, now: t0.addingTimeInterval(30)) == merged)
    }

    @Test func aChangeAfterARemovalKeepsTheItem() {
        var a = SyncDocument()
        a.entries = ["x": entry("changed", 50)]
        var b = SyncDocument()
        b.removed = ["x": t0.addingTimeInterval(40)]
        #expect(SyncDocument.merge(a, b, now: t0.addingTimeInterval(60)).entries["x"] != nil)
    }

    @Test func forgetsOldRemovals() {
        var a = SyncDocument()
        a.removed = ["old": t0]
        let merged = SyncDocument.merge(a, SyncDocument(), now: t0.addingTimeInterval(100 * 86_400))
        #expect(merged.removed.isEmpty)
    }

    @Test func notesWhatChangedHere() {
        var known = SyncDocument()
        known.entries = ["keep": entry("same", 0), "edit": entry("old", 0), "gone": entry("bye", 0), "newer": entry("{\"a\":1,\"extra\":2}", 0)]
        let now = t0.addingTimeInterval(100)
        // "newer" reads as {"a":1} on this Mac (a field it doesn't know): not a change.
        let normalize: (Data) -> Data? = { data in
            let text = String(decoding: data, as: UTF8.self)
            return text.contains("extra") ? Data("{\"a\":1}".utf8) : data
        }
        let updated = known.updated(with: ["keep": Data("same".utf8), "edit": Data("new".utf8), "add": Data("hi".utf8),
                                           "newer": Data("{\"a\":1}".utf8)], now: now, normalize: normalize)
        #expect(updated.entries["keep"]?.modified == t0)
        #expect(updated.entries["edit"]?.modified == now)
        #expect(updated.entries["add"]?.modified == now)
        #expect(updated.entries["newer"]?.data == Data("{\"a\":1,\"extra\":2}".utf8))
        #expect(updated.entries["gone"] == nil)
        #expect(updated.removed["gone"] == now)
        // An item this Mac can't read isn't removed for not being here.
        var foreign = SyncDocument()
        foreign.entries = ["future": entry("from a newer Max Q", 0)]
        #expect(foreign.updated(with: [:], now: now, normalize: { _ in nil }).entries["future"] != nil)
    }

    @Test func encodesTheSameItemTheSameWay() {
        let bookmark = Bookmark(url: "https://example.com", title: "Example", folder: "Bar")
        #expect(SyncCoding.encode(bookmark) == SyncCoding.encode(bookmark))
        #expect(SyncCoding.decode(Bookmark.self, SyncCoding.encode(bookmark)) == bookmark)
    }
}

@MainActor
struct AgentSafetyTests {
    private func target(_ label: String, tag: String = "BUTTON", role: String = "", type: String = "", href: String = "",
                        submits: Bool = false, searchy: Bool = false, sensitive: Bool = false) -> AgentTarget {
        AgentTarget(json: ["label": label, "tag": tag, "role": role, "type": type, "href": href,
                           "submits": submits, "searchy": searchy, "sensitive": sensitive])!
    }

    @Test func asksBeforeWhatCantBeUndone() {
        #expect(AgentSafety.approval(forClicking: target("Place your order")) != nil)
        #expect(AgentSafety.approval(forClicking: target("Delete account")) != nil)
        #expect(AgentSafety.approval(forClicking: target("Post")) != nil)
        #expect(AgentSafety.approval(forClicking: target("Tout accepter")) != nil)
        #expect(AgentSafety.approval(forClicking: target("S’inscrire")) != nil)
        #expect(AgentSafety.approval(forClicking: target("Supprimer")) != nil)
        // A form that isn't a search.
        #expect(AgentSafety.approval(forClicking: target("Next", submits: true)) != nil)
        // A link that signs out, whatever it says.
        #expect(AgentSafety.approval(forClicking: target("Me", tag: "A", href: "https://example.com/logout")) != nil)
    }

    @Test func letsOrdinaryStepsThrough() {
        #expect(AgentSafety.approval(forClicking: target("Next page")) == nil)
        #expect(AgentSafety.approval(forClicking: target("Search", submits: true, searchy: true)) == nil)
        // Action words only count on buttons: a link reading "Follow the guide" opens a page.
        #expect(AgentSafety.approval(forClicking: target("Follow the guide", tag: "A", href: "https://example.com/guide")) == nil)
        #expect(AgentSafety.approval(forClicking: target("Size", tag: "SELECT")) == nil)
        // Whole words only: "Postcards" isn't "post".
        #expect(AgentSafety.approval(forClicking: target("Postcards")) == nil)
    }

    @Test func staysOffBanksAndPasswords() {
        #expect(AgentSafety.isOffLimits(URL(string: "https://www.boursorama.com/compte")))
        #expect(AgentSafety.isOffLimits(URL(string: "https://secure.mybank.com")))
        #expect(AgentSafety.isOffLimits(URL(string: "https://www.labanquepostale.fr")))
        #expect(AgentSafety.isOffLimits(URL(string: "https://vault.bitwarden.com")))
        #expect(AgentSafety.isOffLimits(URL(string: "https://accounts.google.com/signin")))
        #expect(!AgentSafety.isOffLimits(URL(string: "https://html.duckduckgo.com/html/?q=bank")))
        #expect(!AgentSafety.isOffLimits(URL(string: "https://news.ycombinator.com")))
        #expect(!AgentSafety.isOffLimits(nil))
        #expect(AgentSafety.offLimits(URL(string: "https://www.boursorama.com/compte")) == .sensitive)
    }

    @Test func staysOffSitesThatForbidAutomation() {
        for address in ["https://x.com/SpaceX", "https://mobile.twitter.com/a", "https://grok.com/", "https://console.x.ai",
                        "https://www.youtube.com/watch?v=abc", "https://youtu.be/abc", "https://www.amazon.fr/dp/1",
                        "https://www.amazon.co.uk/", "https://www.linkedin.com/in/a", "https://www.facebook.com/a",
                        "https://www.instagram.com/a", "https://www.threads.net/@a", "https://old.reddit.com/r/space",
                        "https://www.tiktok.com/@a", "https://www.google.com/search?q=starship", "https://www.google.fr/search?q=x"] {
            #expect(AgentSafety.offLimits(URL(string: address)) == .noAutomation, "\(address)")
        }
        // Google's other pages, and sites that only share a word with one of these, are fine.
        #expect(!AgentSafety.isOffLimits(URL(string: "https://www.google.com/maps")))
        #expect(!AgentSafety.isOffLimits(URL(string: "https://grokipedia.com/page/Mars")))
        #expect(!AgentSafety.isOffLimits(URL(string: "https://www.xbox.com/")))
        #expect(!AgentSafety.isOffLimits(URL(string: "https://redditinc.com/")))
        #expect(AgentSafety.offLimitsMessage(.noAutomation).contains("terms"))
    }

    @Test func readsWhatGrokWrote() {
        #expect(AgentSession.int(3) == 3)
        #expect(AgentSession.int(3.0) == 3)
        #expect(AgentSession.int("[12]") == 12)
        #expect(AgentSession.int("x") == nil)
        #expect(AgentSession.webAddress("example.com/page")?.absoluteString == "https://example.com/page")
        #expect(AgentSession.webAddress("javascript:alert(1)") == nil)
        #expect(AgentSession.webAddress("file:///etc/passwd") == nil)
        #expect(AgentSession.webAddress("localhost") == nil)
        #expect(AgentSession.domains(in: "Find a hotel on Booking.com and compare with www.airbnb.fr") == ["booking.com", "airbnb.fr"])
        #expect(AgentSession.quoted(String(repeating: "a", count: 80)).count == 60)
    }

    @Test func comparesLinksLikeClicks() {
        #expect(AgentSession.normalized(URL(string: "HTTPS://Example.COM/a/#top")!) == "https://example.com/a")
        let redirect = "https://duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.spacex.com%2Fstarship%2F&rut=1"
        #expect(AgentSession.destinations(redirect).contains("https://www.spacex.com/starship"))
    }

    @Test func describesThePageForGrok() {
        let text = AgentScripts.describe([
            "url": "https://example.com", "title": "Example", "scroll": 40, "more": true,
            "elements": [
                ["ref": 1, "role": "link", "label": "More information", "href": "https://iana.org", "inView": true],
                ["ref": 2, "role": "textbox", "label": "Password", "sensitive": true, "inView": false],
                ["ref": 3, "role": "menu", "label": "Size", "options": ["S", "M"], "value": "S", "inView": true],
            ],
            "text": "Example Domain",
        ])
        #expect(text.contains("Scrolled 40% down; the page goes on below."))
        #expect(text.contains("[1] link \"More information\" → https://iana.org"))
        #expect(text.contains("(password or payment field: you may not type here) (off screen)"))
        #expect(text.contains("[3] menu \"Size\" value=\"S\" options: S | M"))
        #expect(text.hasSuffix("Text around the screen:\nExample Domain"))
    }
}

struct DigestAndMemoryTests {
    @Test func digestsGrokAnswerAsPlainWords() {
        let answer = """
        **Starship** is SpaceX's [fully reusable](https://spacex.com) rocket [[1]](https://a.example).

        - It flew in *2023* [[2]](https://b.example).
        ---follow-ups---
        What next?
        """
        #expect(AnswerDigest.digest(answer) == "Starship is SpaceX's fully reusable rocket.\n• It flew in 2023.")
        #expect(AnswerDigest.digest("   ") == nil)
        let long = Array(repeating: String(repeating: "word ", count: 30), count: 5).joined(separator: "\n\n")
        #expect((AnswerDigest.digest(long)?.count ?? 0) <= 480)
    }

    @Test func neverKeepsPrivatePages() {
        #expect(PageMemory.isExcluded(URL(string: "https://mail.google.com/mail/u/0")!))
        #expect(PageMemory.isExcluded(URL(string: "https://www.paypal.com/myaccount")!))
        #expect(PageMemory.isExcluded(URL(string: "https://shop.example.com/checkout/1")!))
        #expect(PageMemory.isExcluded(URL(string: "file:///Users/me/notes.txt")!))
        #expect(!PageMemory.isExcluded(URL(string: "https://en.wikipedia.org/wiki/Heat_shield")!))
        #expect(abs(PageMemory.cosine([1, 0], [1, 0]) - 1) < 0.0001)
        #expect(abs(PageMemory.cosine([1, 0], [0, 1])) < 0.0001)
        #expect(PageMemory.cosine([1], [1, 2]) == 0)
    }

    @Test @MainActor func groupsTabsBySiteWithoutTheModel() {
        let groups = OnDevice.bySite([("A", "github.com"), ("B", "x.com"), ("C", "github.com"), ("D", "")])
        #expect(groups.count == 1)
        #expect(groups[0].name == "github.com")
        #expect(groups[0].members == [0, 2])
    }
}

/// The page script behind "Passkeys aren't available in this copy of Max Q", run in JavaScriptCore.
struct PasskeyNoticeTests {
    @Test func reportsOnlyWhenASiteAsksForAPasskey() throws {
        let context = try #require(JSContext())
        context.evaluateScript("""
            var reports = [], calls = 0;
            var window = { webkit: { messageHandlers: { maxqPasskey: { postMessage: function (m) { reports.push(m); } } } } };
            var navigator = { credentials: {
              get: function (o) { calls++; return 'got'; },
              create: function (o) { calls++; return 'made'; } } };
            """)
        context.evaluateScript(PasskeyNotice.source)
        func count(_ name: String) -> Int32 { context.evaluateScript(name)?.toInt32() ?? -1 }

        // The quiet passkey autofill a sign-in page asks for as it loads isn't a request.
        context.evaluateScript("navigator.credentials.get({ publicKey: {}, mediation: 'conditional' })")
        #expect(count("reports.length") == 0)
        // Asking for a passkey (signing in or making one) is, and the call still goes through as it was.
        #expect(context.evaluateScript("navigator.credentials.get({ publicKey: {} })")?.toString() == "got")
        #expect(context.evaluateScript("navigator.credentials.create({ publicKey: {} })")?.toString() == "made")
        #expect(count("reports.length") == 2)
        // A saved password isn't a passkey.
        context.evaluateScript("navigator.credentials.get({ password: true })")
        #expect(count("reports.length") == 2)
        #expect(count("calls") == 4)
        #expect(PasskeyNotice.source.contains("messageHandlers.\(PasskeyNotice.handlerName)"))
    }

    @Test func builtFromSourceThereAreNoPasskeys() {
        // The test host isn't signed with Apple's browser approval.
        #expect(!PasskeyNotice.passkeysAllowed)
    }
}

