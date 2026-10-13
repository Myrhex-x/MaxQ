//
//  NewsFeeds.swift
//  Max Q
//
//  News from the outlets' own RSS feeds: what feed readers have always used, published by the
//  outlets for exactly that. The new-tab page's topics, followed searches and the News tab
//  without a search key all read these feeds, in the Mac's language (French outlets on a French
//  Mac), straight from the outlets with no cookies. A feed is read at most every ten minutes.
//

import Foundation

/// An outlet's feed.
nonisolated struct NewsFeedSource: Hashable, Sendable {
    let outlet: String
    let url: URL

    init(_ outlet: String, _ address: String) {
        self.outlet = outlet
        url = URL(string: address)!
    }
}

/// Which feeds make up each topic, by language.
nonisolated enum NewsFeedCatalog {
    static func feeds(for topic: String, language: String = Locale.current.language.languageCode?.identifier ?? "en") -> [NewsFeedSource] {
        let table = language == "fr" ? french : english
        return table[topic] ?? table["top"] ?? []
    }

    /// Every feed for the language, each once (to look through for a followed search).
    static func allFeeds(language: String = Locale.current.language.languageCode?.identifier ?? "en") -> [NewsFeedSource] {
        let table = language == "fr" ? french : english
        var seen = Set<URL>()
        return table.keys.sorted().flatMap { table[$0] ?? [] }.filter { seen.insert($0.url).inserted }
    }

    private static let english: [String: [NewsFeedSource]] = [
        "top": [.init("BBC News", "https://feeds.bbci.co.uk/news/rss.xml"),
                .init("The Guardian", "https://www.theguardian.com/international/rss"),
                .init("The New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml"),
                .init("ABC News", "https://abcnews.go.com/abcnews/topstories"),
                .init("Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml"),
                .init("NPR", "https://feeds.npr.org/1001/rss.xml")],
        "world": [.init("BBC News", "https://feeds.bbci.co.uk/news/world/rss.xml"),
                  .init("The Guardian", "https://www.theguardian.com/world/rss"),
                  .init("France 24", "https://www.france24.com/en/rss"),
                  .init("NPR", "https://feeds.npr.org/1004/rss.xml"),
                  .init("DW", "https://rss.dw.com/rdf/rss-en-world")],
        "politics": [.init("BBC News", "https://feeds.bbci.co.uk/news/politics/rss.xml"),
                     .init("The Guardian", "https://www.theguardian.com/politics/rss"),
                     .init("Politico", "https://rss.politico.com/politics-news.xml"),
                     .init("NPR", "https://feeds.npr.org/1014/rss.xml")],
        "business": [.init("BBC News", "https://feeds.bbci.co.uk/news/business/rss.xml"),
                     .init("The Guardian", "https://www.theguardian.com/business/rss"),
                     .init("CNBC", "https://www.cnbc.com/id/100003114/device/rss/rss.html"),
                     .init("NPR", "https://feeds.npr.org/1006/rss.xml")],
        "technology": [.init("The Verge", "https://www.theverge.com/rss/index.xml"),
                       .init("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index"),
                       .init("TechCrunch", "https://techcrunch.com/feed/"),
                       .init("BBC News", "https://feeds.bbci.co.uk/news/technology/rss.xml"),
                       .init("Wired", "https://www.wired.com/feed/rss")],
        "ai": [.init("The Verge", "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml"),
               .init("TechCrunch", "https://techcrunch.com/category/artificial-intelligence/feed/"),
               .init("MIT Technology Review", "https://www.technologyreview.com/feed/"),
               .init("Ars Technica", "https://arstechnica.com/ai/feed/")],
        "science": [.init("BBC News", "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"),
                    .init("The Guardian", "https://www.theguardian.com/science/rss"),
                    .init("NPR", "https://feeds.npr.org/1007/rss.xml"),
                    .init("ScienceDaily", "https://www.sciencedaily.com/rss/all.xml")],
        "space": [.init("NASA", "https://www.nasa.gov/feed/"),
                  .init("SpaceNews", "https://spacenews.com/feed/"),
                  .init("Spaceflight Now", "https://spaceflightnow.com/feed/"),
                  .init("ESA", "https://www.esa.int/rssfeed/Our_Activities/Space_News")],
        "health": [.init("BBC News", "https://feeds.bbci.co.uk/news/health/rss.xml"),
                   .init("NPR", "https://feeds.npr.org/1128/rss.xml"),
                   .init("STAT", "https://www.statnews.com/feed/")],
        "sports": [.init("BBC Sport", "https://feeds.bbci.co.uk/sport/rss.xml"),
                   .init("ESPN", "https://www.espn.com/espn/rss/news"),
                   .init("The Guardian", "https://www.theguardian.com/sport/rss")],
        "culture": [.init("BBC News", "https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml"),
                    .init("The Guardian", "https://www.theguardian.com/culture/rss"),
                    .init("NPR", "https://feeds.npr.org/1008/rss.xml")],
    ]

    private static let french: [String: [NewsFeedSource]] = [
        "top": [.init("Le Monde", "https://www.lemonde.fr/rss/une.xml"),
                .init("franceinfo", "https://www.francetvinfo.fr/titres.rss"),
                .init("France 24", "https://www.france24.com/fr/rss"),
                .init("Libération", "https://www.liberation.fr/arc/outboundfeeds/rss-all/?outputType=xml"),
                .init("Le Figaro", "https://www.lefigaro.fr/rss/figaro_actualites.xml"),
                .init("20 Minutes", "https://www.20minutes.fr/feeds/rss-une.xml"),
                .init("Ouest-France", "https://www.ouest-france.fr/rss/une")],
        "world": [.init("Le Monde", "https://www.lemonde.fr/international/rss_full.xml"),
                  .init("franceinfo", "https://www.francetvinfo.fr/monde.rss"),
                  .init("Le Figaro", "https://www.lefigaro.fr/rss/figaro_international.xml"),
                  .init("France 24", "https://www.france24.com/fr/rss")],
        "politics": [.init("Le Monde", "https://www.lemonde.fr/politique/rss_full.xml"),
                     .init("franceinfo", "https://www.francetvinfo.fr/politique.rss"),
                     .init("Le Figaro", "https://www.lefigaro.fr/rss/figaro_politique.xml")],
        "business": [.init("Le Monde", "https://www.lemonde.fr/economie/rss_full.xml"),
                     .init("franceinfo", "https://www.francetvinfo.fr/economie.rss"),
                     .init("Le Figaro", "https://www.lefigaro.fr/rss/figaro_economie.xml")],
        "technology": [.init("Le Monde", "https://www.lemonde.fr/pixels/rss_full.xml"),
                       .init("Numerama", "https://www.numerama.com/feed/"),
                       .init("Frandroid", "https://www.frandroid.com/feed"),
                       .init("franceinfo", "https://www.francetvinfo.fr/internet.rss"),
                       .init("01net", "https://www.01net.com/feed/")],
        "ai": [.init("Le Monde", "https://www.lemonde.fr/intelligence-artificielle/rss_full.xml"),
               .init("Numerama", "https://www.numerama.com/tech/intelligence-artificielle/feed/")],
        "science": [.init("Le Monde", "https://www.lemonde.fr/sciences/rss_full.xml"),
                    .init("franceinfo", "https://www.francetvinfo.fr/sciences.rss"),
                    .init("Futura", "https://www.futura-sciences.com/rss/actualites.xml"),
                    .init("Sciences et Avenir", "https://www.sciencesetavenir.fr/rss.xml")],
        "space": [.init("Futura", "https://www.futura-sciences.com/rss/espace/actualites.xml"),
                  .init("Le Monde", "https://www.lemonde.fr/espace/rss_full.xml"),
                  .init("Numerama", "https://www.numerama.com/sciences/espace/feed/")],
        "health": [.init("Le Monde", "https://www.lemonde.fr/sante/rss_full.xml"),
                   .init("franceinfo", "https://www.francetvinfo.fr/sante.rss")],
        "sports": [.init("franceinfo", "https://www.francetvinfo.fr/sports.rss"),
                   .init("Le Monde", "https://www.lemonde.fr/sport/rss_full.xml"),
                   .init("L'Équipe", "https://dwh.lequipe.fr/api/edito/rss?path=/")],
        "culture": [.init("Le Monde", "https://www.lemonde.fr/culture/rss_full.xml"),
                    .init("franceinfo", "https://www.francetvinfo.fr/culture.rss")],
    ]
}

/// Reads feeds, each at most every ten minutes.
nonisolated enum NewsFeedClient {
    private actor Cache {
        var entries: [URL: (items: [NewsItem], date: Date)] = [:]
        func get(_ url: URL) -> [NewsItem]? {
            guard let entry = entries[url], Date().timeIntervalSince(entry.date) < 10 * 60 else { return nil }
            return entry.items
        }
        func set(_ url: URL, _ items: [NewsItem]) { entries[url] = (items, Date()) }
    }

    private static let cache = Cache()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static let userAgent = "MaxQ/0.1 (macOS; news reader; +https://github.com/Myrhex-x/MaxQ)"

    /// One feed's items, newest first.
    static func items(from feed: NewsFeedSource) async -> [NewsItem] {
        if let cached = await cache.get(feed.url) { return cached }
        var request = URLRequest(url: feed.url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        let items = Array(RSSParser.parse(data, outlet: feed.outlet).prefix(30))
        await cache.set(feed.url, items)
        return items
    }

    /// Every item of `feeds`, read two at a time.
    static func items(from feeds: [NewsFeedSource]) async -> [NewsItem] {
        var all: [NewsItem] = []
        for pair in stride(from: 0, to: feeds.count, by: 2).map({ Array(feeds[$0..<min($0 + 2, feeds.count)]) }) {
            await withTaskGroup(of: [NewsItem].self) { group in
                for feed in pair { group.addTask { await items(from: feed) } }
                for await items in group { all += items }
            }
        }
        return all
    }

    /// Stories in the language's feeds that mention every word of `query` (in the title or the
    /// summary), newest first: news for a search without a search key, and for followed searches.
    static func matching(_ query: String, within time: SearchTime = .any) async -> [NewsItem] {
        guard !searchWords(query).isEmpty else { return [] }
        return matching(query, within: time, in: await items(from: NewsFeedCatalog.allFeeds()))
    }

    /// The stories among `items` that mention every word of `query` within `time`, newest first,
    /// each once (its newest copy, when two feeds carry it).
    static func matching(_ query: String, within time: SearchTime, in items: [NewsItem], now: Date = Date()) -> [NewsItem] {
        let words = searchWords(query)
        guard !words.isEmpty else { return [] }
        let oldest: Date? = switch time {
        case .any: nil
        case .day: now.addingTimeInterval(-86_400)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-31 * 86_400)
        case .year: now.addingTimeInterval(-365 * 86_400)
        }
        var seen = Set<String>()
        return items
            .filter { item in
                if let oldest {
                    guard let date = item.date, date >= oldest else { return false }
                }
                return words.isSubset(of: NewsClustering.words(item.title + " " + item.excerpt, minimumLength: 2))
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .filter { seen.insert($0.url.absoluteString).inserted }
    }

    private static func searchWords(_ query: String) -> Set<String> {
        NewsClustering.words(query, minimumLength: 2).subtracting(NewsClustering.stopwords)
    }
}

/// RSS 2.0, RSS 1.0 (RDF) and Atom, into news items.
nonisolated final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [NewsItem] = []
    private let outlet: String
    private var current: [String: String]?
    private var image: URL?
    private var text = ""

    private init(outlet: String) {
        self.outlet = outlet
    }

    static func parse(_ data: Data, outlet: String) -> [NewsItem] {
        let delegate = RSSParser(outlet: outlet)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return delegate.items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let name = elementName.lowercased()
        text = ""
        if name == "item" || name == "entry" {
            current = [:]
            image = nil
            return
        }
        guard current != nil else { return }
        switch name {
        case "link":
            // Atom: <link rel="alternate" href="…"/>.
            if let href = attributes["href"], attributes["rel"] == nil || attributes["rel"] == "alternate" {
                current?["link"] = href
            }
        case "media:content", "media:thumbnail":
            if image == nil, let url = attributes["url"].flatMap(URL.init(string:)),
               attributes["medium"].map({ $0 == "image" }) ?? !(attributes["type"]?.hasPrefix("video") ?? false) {
                image = url
            }
        case "enclosure":
            if image == nil, attributes["type"]?.hasPrefix("image") == true, let url = attributes["url"].flatMap(URL.init(string:)) {
                image = url
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        guard current != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": if current?["title"] == nil { current?["title"] = value }
        case "link": if current?["link"] == nil, !value.isEmpty { current?["link"] = value }
        case "description", "summary": if current?["summary"] == nil { current?["summary"] = value }
        case "content:encoded", "content": if current?["content"] == nil { current?["content"] = value }
        case "pubdate", "published", "updated", "dc:date": if current?["date"] == nil { current?["date"] = value }
        case "item", "entry":
            if let item = makeItem() { items.append(item) }
            current = nil
        default: break
        }
        text = ""
    }

    private func makeItem() -> NewsItem? {
        guard let entry = current, let title = entry["title"].map(WebSearchClient.plainText), !title.isEmpty,
              let link = entry["link"].flatMap(URL.init(string:)), link.scheme?.hasPrefix("http") == true else { return nil }
        let html = entry["summary"] ?? entry["content"] ?? ""
        let picture = image ?? Self.firstImage(in: entry["content"] ?? html)
        let summary = String(WebSearchClient.plainText(html).prefix(400))
        return NewsItem(title: title, url: link, excerpt: summary, source: outlet,
                        date: entry["date"].flatMap(Self.date), image: picture.flatMap { $0.scheme == "https" ? $0 : nil })
    }

    /// The first picture in an item's HTML.
    static func firstImage(in html: String) -> URL? {
        guard let range = html.range(of: #"<img[^>]+src=["']([^"']+)["']"#, options: .regularExpression) else { return nil }
        let tag = String(html[range])
        guard let src = tag.range(of: #"src=["']([^"']+)"#, options: .regularExpression) else { return nil }
        return URL(string: WebSearchClient.decodeEntities(String(tag[src].dropFirst(5))))
    }

    /// RFC 822 ("Sat, 10 Oct 2026 08:30:00 +0200") or ISO 8601.
    static func date(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            iso.formatOptions = options
            if let date = iso.date(from: text) { return date }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z",
                       "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z", "EEE, dd MMM yyyy HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
