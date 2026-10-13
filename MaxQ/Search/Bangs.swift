//
//  Bangs.swift
//  Max Q
//
//  Shortcuts typed into the address bar: "!yt lofi" searches YouTube, "!x starship" opens Max Q's
//  results on its Posts on X tab, "!gp mars" on its Grokipedia tab, "!grok …" asks Grok. The
//  shortcut can come first or last ("lofi !yt"), and a shortcut alone opens the site itself.
//  Pure logic, unit-tested.
//

import Foundation

nonisolated struct Bang: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable {
        /// A site's own search page: `%s` is where the encoded words go. `home` opens when no words
        /// follow the shortcut.
        case site(template: String, home: String)
        /// One of the tabs of Max Q's own results page. With another engine, the site's own search.
        case maxQ(GrokSearchTab)
        /// Grok, in the side panel.
        case askGrok
        /// Grok's research, with a budget.
        case research
        /// Pictures made by Grok.
        case imagine
    }

    /// What follows the "!": "yt".
    let trigger: String
    var aliases: [String] = []
    /// "YouTube".
    let name: String
    /// The site whose icon stands for the shortcut.
    let host: String
    let target: Target

    var id: String { trigger }

    /// Everything that can follow the "!".
    var triggers: [String] { [trigger] + aliases }

    /// The page for `words`, or the site itself when there are none. Max Q's own tabs and Grok
    /// aren't pages: those are handled by the browser.
    func url(for words: String) -> URL? {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        switch target {
        case let .site(template, home):
            guard !trimmed.isEmpty else { return URL(string: home) }
            let encoded = String(trimmed.prefix(500)).addingPercentEncoding(withAllowedCharacters: SearchEngine.queryAllowed) ?? trimmed
            return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
        case .maxQ(let tab):
            // The site's own search, for when Max Q's page isn't the engine.
            switch tab {
            case .x: return trimmed.isEmpty ? XLinks.home : XLinks.search(for: trimmed)
            case .grokipedia: return trimmed.isEmpty ? GrokipediaLinks.home : GrokipediaLinks.search(trimmed)
            case .all: return MaxQScheme.searchURL(for: trimmed)
            case .images: return trimmed.isEmpty ? URL(string: "https://duckduckgo.com/?ia=images") : DuckDuckGoPages.images(trimmed)
            case .news: return trimmed.isEmpty ? URL(string: "https://duckduckgo.com/?ia=news") : DuckDuckGoPages.news(trimmed)
            case .videos: return trimmed.isEmpty ? URL(string: "https://duckduckgo.com/?ia=videos") : DuckDuckGoPages.videos(trimmed)
            }
        case .askGrok, .research, .imagine:
            return nil
        }
    }

    /// The line under the shortcut in the address bar's list.
    func action(for words: String) -> String {
        let empty = words.trimmingCharacters(in: .whitespaces).isEmpty
        switch target {
        case .site: return empty ? String(localized: "Open \(name)") : String(localized: "Search \(name)")
        case .maxQ(.x): return empty ? String(localized: "Open X") : String(localized: "Posts on X, in Max Q")
        case .maxQ(.grokipedia): return empty ? String(localized: "Open Grokipedia") : String(localized: "Grokipedia, in Max Q")
        case .maxQ(.all): return String(localized: "Search with Max Q")
        case .maxQ(.images): return empty ? String(localized: "Open Images") : String(localized: "Images, in Max Q")
        case .maxQ(.news): return empty ? String(localized: "Today's news") : String(localized: "News, in Max Q")
        case .maxQ(.videos): return empty ? String(localized: "Open Videos") : String(localized: "Videos, in Max Q")
        case .askGrok: return empty ? String(localized: "Open Grok") : String(localized: "Ask Grok")
        case .research: return String(localized: "Research with Grok")
        case .imagine: return empty ? String(localized: "Open Imagine") : String(localized: "Imagine this")
        }
    }
}

nonisolated enum Bangs {
    /// The shortcuts Max Q knows, in the order the list offers them.
    static let all: [Bang] = [
        Bang(trigger: "x", aliases: ["twitter"], name: String(localized: "Posts on X"), host: "x.com", target: .maxQ(.x)),
        Bang(trigger: "gp", aliases: ["grokipedia"], name: "Grokipedia", host: "grokipedia.com", target: .maxQ(.grokipedia)),
        Bang(trigger: "grok", aliases: ["ask"], name: "Grok", host: "grok.com", target: .askGrok),
        Bang(trigger: "research", aliases: ["deep"], name: String(localized: "Research"), host: "grok.com", target: .research),
        Bang(trigger: "imagine", aliases: ["draw"], name: String(localized: "Imagine"), host: "grok.com", target: .imagine),
        Bang(trigger: "yt", aliases: ["youtube"], name: "YouTube", host: "youtube.com",
             target: .site(template: "https://www.youtube.com/results?search_query=%s", home: "https://www.youtube.com")),
        Bang(trigger: "w", aliases: ["wiki", "wikipedia"], name: "Wikipedia", host: "wikipedia.org",
             target: .site(template: "https://\(wikipediaLanguage).wikipedia.org/w/index.php?search=%s",
                           home: "https://\(wikipediaLanguage).wikipedia.org")),
        Bang(trigger: "g", aliases: ["google"], name: "Google", host: "google.com",
             target: .site(template: "https://www.google.com/search?q=%s", home: "https://www.google.com")),
        Bang(trigger: "ddg", aliases: ["duckduckgo"], name: "DuckDuckGo", host: "duckduckgo.com",
             target: .site(template: "https://duckduckgo.com/?q=%s", home: "https://duckduckgo.com")),
        Bang(trigger: "i", aliases: ["img", "images"], name: String(localized: "Images"), host: "duckduckgo.com", target: .maxQ(.images)),
        Bang(trigger: "news", aliases: ["n"], name: String(localized: "News"), host: "duckduckgo.com", target: .maxQ(.news)),
        Bang(trigger: "v", aliases: ["vid", "videos", "video"], name: String(localized: "Videos"), host: "duckduckgo.com", target: .maxQ(.videos)),
        Bang(trigger: "m", aliases: ["maps"], name: String(localized: "Maps"), host: "maps.apple.com",
             target: .site(template: "https://maps.apple.com/?q=%s", home: "https://maps.apple.com")),
        Bang(trigger: "r", aliases: ["reddit"], name: "Reddit", host: "reddit.com",
             target: .site(template: "https://www.reddit.com/search/?q=%s", home: "https://www.reddit.com")),
        Bang(trigger: "gh", aliases: ["github"], name: "GitHub", host: "github.com",
             target: .site(template: "https://github.com/search?q=%s", home: "https://github.com")),
        Bang(trigger: "a", aliases: ["amazon"], name: "Amazon", host: amazonHost,
             target: .site(template: "https://www.\(amazonHost)/s?k=%s", home: "https://www.\(amazonHost)")),
        Bang(trigger: "b", aliases: ["bing"], name: "Bing", host: "bing.com",
             target: .site(template: "https://www.bing.com/search?q=%s", home: "https://www.bing.com")),
        Bang(trigger: "brave", name: "Brave Search", host: "search.brave.com",
             target: .site(template: "https://search.brave.com/search?q=%s", home: "https://search.brave.com")),
        Bang(trigger: "so", aliases: ["stackoverflow"], name: "Stack Overflow", host: "stackoverflow.com",
             target: .site(template: "https://stackoverflow.com/search?q=%s", home: "https://stackoverflow.com")),
        Bang(trigger: "mdn", name: "MDN", host: "developer.mozilla.org",
             target: .site(template: "https://developer.mozilla.org/search?q=%s", home: "https://developer.mozilla.org")),
        Bang(trigger: "npm", name: "npm", host: "npmjs.com",
             target: .site(template: "https://www.npmjs.com/search?q=%s", home: "https://www.npmjs.com")),
        Bang(trigger: "hn", name: "Hacker News", host: "news.ycombinator.com",
             target: .site(template: "https://hn.algolia.com/?q=%s", home: "https://news.ycombinator.com")),
        Bang(trigger: "imdb", name: "IMDb", host: "imdb.com",
             target: .site(template: "https://www.imdb.com/find/?q=%s", home: "https://www.imdb.com")),
        Bang(trigger: "spotify", name: "Spotify", host: "open.spotify.com",
             target: .site(template: "https://open.spotify.com/search/%s", home: "https://open.spotify.com")),
        Bang(trigger: "wa", aliases: ["wolfram"], name: "Wolfram|Alpha", host: "wolframalpha.com",
             target: .site(template: "https://www.wolframalpha.com/input?i=%s", home: "https://www.wolframalpha.com")),
        Bang(trigger: "def", aliases: ["define"], name: "Wiktionary", host: "wiktionary.org",
             target: .site(template: "https://\(wikipediaLanguage).wiktionary.org/w/index.php?search=%s",
                           home: "https://\(wikipediaLanguage).wiktionary.org")),
        Bang(trigger: "tr", aliases: ["translate"], name: "DeepL", host: "deepl.com",
             target: .site(template: "https://www.deepl.com/translator#auto/\(translationTarget)/%s", home: "https://www.deepl.com/translator")),
    ]

    private static let byTrigger: [String: Bang] = {
        var map: [String: Bang] = [:]
        for bang in all {
            for trigger in bang.triggers where map[trigger] == nil { map[trigger] = bang }
        }
        return map
    }()

    /// The shortcut named `word` ("yt", "!yt" or "YT").
    static func find(_ word: String) -> Bang? {
        var key = word.lowercased()
        if key.hasPrefix("!") { key.removeFirst() }
        guard !key.isEmpty else { return nil }
        return byTrigger[key]
    }

    /// The shortcut in `text` and the words around it, when the first or the last word is a known
    /// one: "!yt lofi" and "lofi !yt" give YouTube and "lofi". An unknown "!word" isn't one.
    static func parse(_ text: String) -> (bang: Bang, words: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var words = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = words.first else { return nil }
        if first.hasPrefix("!"), first.count > 1, let bang = find(first) {
            words.removeFirst()
            return (bang, words.joined(separator: " "))
        }
        if words.count > 1, let last = words.last, last.hasPrefix("!"), last.count > 1, let bang = find(last) {
            words.removeLast()
            return (bang, words.joined(separator: " "))
        }
        return nil
    }

    /// Shortcuts that start with what's typed after a lone "!" (the list's completions): triggers
    /// first, then names. A bare "!" lists them all.
    static func completions(for typed: String, limit: Int = 7) -> [Bang] {
        var key = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard key.hasPrefix("!"), !key.contains(" ") else { return [] }
        key.removeFirst()
        guard !key.isEmpty else { return Array(all.prefix(limit)) }
        let byTrigger = all.filter { $0.triggers.contains { $0.hasPrefix(key) } }
        let byName = all.filter { bang in
            !byTrigger.contains(bang) && bang.name.lowercased().split(separator: " ").contains { $0.hasPrefix(key) }
        }
        return Array((byTrigger + byName).prefix(limit))
    }

    // MARK: - Local editions

    /// Wikipedia (and Wiktionary) in the Mac's language, when it has one of the larger editions.
    static var wikipediaLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let editions: Set<String> = ["en", "fr", "de", "es", "it", "pt", "nl", "pl", "ru", "ja", "zh", "sv", "uk", "ar", "ko", "tr", "cs", "fi", "no", "he", "id", "vi"]
        return editions.contains(code) ? code : "en"
    }

    /// The Amazon store for the Mac's region.
    static var amazonHost: String {
        let stores: [String: String] = [
            "US": "amazon.com", "GB": "amazon.co.uk", "FR": "amazon.fr", "DE": "amazon.de", "ES": "amazon.es",
            "IT": "amazon.it", "CA": "amazon.ca", "JP": "amazon.co.jp", "IN": "amazon.in", "AU": "amazon.com.au",
            "MX": "amazon.com.mx", "BR": "amazon.com.br", "NL": "amazon.nl", "SE": "amazon.se", "PL": "amazon.pl",
            "BE": "amazon.com.be", "IE": "amazon.co.uk", "AT": "amazon.de", "CH": "amazon.de",
        ]
        return stores[Locale.current.region?.identifier ?? "US"] ?? "amazon.com"
    }

    /// DeepL's code for the Mac's language, the language "!tr" translates into.
    static var translationTarget: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code == "en" ? "en" : code
    }
}
