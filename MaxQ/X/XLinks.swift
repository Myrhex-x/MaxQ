//
//  XLinks.swift
//  Max Q
//
//  Links into x.com that need no API and cost nothing: X's own search page and its share intent
//  (the same "post this" link any website's share button uses), and what an x.com address says.
//

import Foundation

enum XLinks {
    nonisolated static let home = URL(string: "https://x.com")!

    /// x.com's search for `query`; `latest` opens its Latest tab rather than Top.
    nonisolated static func search(for query: String, latest: Bool = false) -> URL? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var components = URLComponents(string: "https://x.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: String(q.prefix(500))),
            URLQueryItem(name: "src", value: "typed_query"),
        ]
        if latest { components.queryItems?.append(URLQueryItem(name: "f", value: "live")) }
        return components.url
    }

    /// What to search on X for posts sharing a page: its address without the parts that differ
    /// from link to link (the scheme, "www.", tracking parameters, a fragment).
    nonisolated static func linkQuery(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), url.scheme == "https" || url.scheme == "http" else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return bare + path
    }

    /// A page's title without the site's name tacked on ("Starship flies again - The Verge").
    nonisolated static func titleQuery(for title: String) -> String? {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" | ", " - ", " \u{2013} ", " \u{2014} ", " · "] {
            if let range = text.range(of: separator, options: .backwards), text.distance(from: text.startIndex, to: range.lowerBound) > 12 {
                text = String(text[..<range.lowerBound])
            }
        }
        guard text.count >= 4 else { return nil }
        return "\"" + String(text.prefix(120)) + "\""
    }

    /// The post's id in an x.com address ("…/status/1234"), or nil for any other page.
    nonisolated static func postID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              ["x.com", "twitter.com", "mobile.twitter.com", "mobile.x.com", "www.x.com", "www.twitter.com"].contains(host) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }), index + 1 < parts.count else { return nil }
        let id = parts[index + 1]
        return id.allSatisfy { $0.isASCII && $0.isNumber } && (1...20).contains(id.count) ? id : nil
    }

    /// Whose post an x.com address is ("SpaceX" in x.com/SpaceX/status/…), from the address alone.
    nonisolated static func handle(ofPost url: URL) -> String? {
        guard postID(from: url) != nil, let first = url.path.split(separator: "/").first.map(String.init),
              first != "i", (1...15).contains(first.count),
              first.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        return first
    }

    /// x.com's share intent, prefilled with the page title and link. The user reviews and posts it
    /// themselves on x.com; Max Q never posts anything.
    nonisolated static func intent(text: String, url: URL?) -> URL? {
        var components = URLComponents(string: "https://x.com/intent/post")!
        var items = url.map { [URLQueryItem(name: "url", value: $0.absoluteString)] } ?? []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.insert(URLQueryItem(name: "text", value: String(trimmed.prefix(200))), at: 0) }
        components.queryItems = items
        return components.url
    }
}

enum GrokipediaLinks {
    nonisolated static let home = URL(string: "https://grokipedia.com")!

    /// The article a grokipedia.com address is ("SpaceX_Starship"), or nil for any other page.
    nonisolated static func page(of url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == "grokipedia.com" || host.hasSuffix(".grokipedia.com"),
              url.path.hasPrefix("/page/") else { return nil }
        let page = String(url.path.dropFirst("/page/".count))
        return page.isEmpty || page.contains("/") ? nil : page
    }

    /// Grokipedia's own search page. Loading it is ordinary browsing of their site.
    nonisolated static func search(_ query: String) -> URL? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var components = URLComponents(string: "https://grokipedia.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: String(q.prefix(200)))]
        return components.url
    }

    nonisolated private static let questionWords: Set<String> = [
        "how", "what", "why", "when", "where", "who", "which", "whose", "is", "are", "was", "were", "can",
        "could", "should", "would", "will", "do", "does", "did", "best", "top", "cheap", "buy", "near",
        "download", "login", "log", "sign", "price", "weather", "vs", "versus", "comment", "pourquoi", "quand",
    ]

    /// True when a query reads like a topic (a person, place, thing or idea) rather than a question
    /// or a task, which is when an encyclopedia article beside the results is actually useful.
    nonisolated static func looksLikeTopic(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty, q.count <= 60, !q.contains("?"), !q.contains("://"), !q.contains("@") else { return false }
        let words = q.split(whereSeparator: { $0 == " " })
        guard (1...5).contains(words.count), let first = words.first.map(String.init) else { return false }
        if questionWords.contains(first) { return false }
        if words.contains(where: { $0 == "vs" || $0 == "versus" || $0 == "near" }) { return false }
        // Mostly letters: skip code, math and order numbers.
        let letters = q.filter { $0.isLetter }.count
        return Double(letters) / Double(max(q.filter { $0 != " " }.count, 1)) > 0.7
    }
}
