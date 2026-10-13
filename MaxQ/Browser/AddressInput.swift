//
//  AddressInput.swift
//  Max Q
//
//  Decides what the user meant when they press Return in the address bar: open a URL, or search.
//  Pure logic, no UI, unit-tested in MaxQTests.
//

import Foundation

nonisolated enum AddressInput: Equatable {
    case url(URL)
    case search(String)

    /// Schemes that may never be launched from the address bar. Typing `javascript:` into a URL
    /// bar is a classic self-XSS trick, and `data:` can render a convincing fake page.
    nonisolated static let blockedSchemes: Set<String> = ["javascript", "data", "vbscript", "blob"]

    nonisolated static func classify(_ raw: String) -> AddressInput? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Anything with an inner space is a search (URLs never contain raw spaces).
        if text.contains(where: { $0 == " " || $0 == "\t" || $0 == "\n" }) {
            return .search(text)
        }

        let lower = text.lowercased()

        // Explicit scheme: "https://…", "about:blank", "mailto:…".
        if let schemeEnd = lower.firstIndex(of: ":") {
            let scheme = String(lower[..<schemeEnd])
            let looksLikeScheme = !scheme.isEmpty
                && scheme.first!.isLetter
                && scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
            if looksLikeScheme {
                if blockedSchemes.contains(scheme) { return .search(text) }
                let rest = lower[lower.index(after: schemeEnd)...]
                // "localhost:3000" and "example.com:8080/x" are host:port, not a scheme.
                let isHostPort = rest.first?.isNumber == true && (scheme == "localhost" || scheme.contains("."))
                if !isHostPort {
                    if scheme == "http" || scheme == "https" {
                        guard rest.hasPrefix("//"), let url = URL(string: text), url.host?.isEmpty == false else {
                            return .search(text)
                        }
                        return .url(url)
                    }
                    if scheme == "about" || scheme == "mailto" || rest.hasPrefix("//") {
                        if let url = URL(string: text) { return .url(url) }
                    }
                    // "word:thing" without "//" (e.g. "define:grok") reads as a search.
                    return .search(text)
                }
            }
        }

        // No scheme. Split off the host part.
        let hostPart = String(lower.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first ?? "")
        let host = hostPart.split(separator: ":").first.map(String.init) ?? hostPart

        if host == "localhost" || host.hasSuffix(".localhost") {
            return URL(string: "http://" + text).map(AddressInput.url) ?? .search(text)
        }
        if isIPv4(host) {
            return URL(string: "http://" + text).map(AddressInput.url) ?? .search(text)
        }
        if looksLikeDomain(host) {
            return URL(string: "https://" + text).map(AddressInput.url) ?? .search(text)
        }
        return .search(text)
    }

    nonisolated static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber), let n = Int(part) else { return false }
            return n <= 255
        }
    }

    /// True when `host` is a plausible domain: dot-separated labels and a TLD we recognize, so
    /// "node.js" or "1.5" search instead of failing to load.
    nonisolated static func looksLikeDomain(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let tld = labels.last.map(String.init) else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63,
                  label.first != "-", label.last != "-",
                  label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return false }
        }
        if tld.hasPrefix("xn--") { return true }
        return KnownTLDs.contains(tld)
    }
}

/// A compact TLD list: every ISO country code plus the generic TLDs people actually type.
/// Not the full IANA list on purpose; an unknown TLD just becomes a search, and typing the
/// scheme ("https://site.weird") always works.
enum KnownTLDs {
    nonisolated static func contains(_ tld: String) -> Bool {
        let t = tld.lowercased()
        if t.count == 2 { return countryCodes.contains(t) }
        return generic.contains(t)
    }

    nonisolated private static let generic: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int", "info", "biz", "name", "pro", "aero", "coop", "museum",
        "app", "dev", "io", "ai", "xyz", "online", "site", "tech", "store", "shop", "blog", "cloud", "page",
        "news", "media", "live", "world", "today", "space", "website", "design", "studio", "agency", "games",
        "art", "club", "fun", "life", "email", "link", "click", "help", "wiki", "zone", "network", "systems",
        "solutions", "services", "software", "digital", "social", "global", "group", "company", "center",
        "academy", "education", "school", "university", "science", "health", "care", "bank", "money",
        "finance", "capital", "fund", "law", "legal", "realty", "estate", "house", "home", "travel", "tours",
        "photo", "photos", "pics", "video", "film", "movie", "music", "audio", "radio", "tv", "chat", "team",
        "work", "works", "jobs", "careers", "events", "party", "love", "family", "kids", "dog", "cat", "eco",
        "green", "earth", "energy", "solar", "auto", "car", "cars", "bike", "run", "fit", "fitness", "golf",
        "football", "soccer", "bet", "poker", "casino", "win", "vip", "top", "best", "new", "plus", "one",
        "me", "mobi", "asia", "africa", "berlin", "london", "paris", "nyc", "tokyo", "amsterdam", "brussels",
        "quebec", "scot", "wales", "eus", "gal", "bzh", "corsica", "alsace", "swiss", "rocks", "ninja",
        "guru", "expert", "codes", "build", "tools", "computer", "community", "foundation", "gives",
        "charity", "ngo", "ong", "church", "faith", "bible", "lgbt", "gay", "inc", "llc", "ltd", "gmbh",
        "sarl", "srl", "sas", "ventures", "holdings", "partners", "consulting", "marketing", "management",
        "exchange", "trade", "market", "markets", "crypto", "nft", "dao", "eth", "sol", "local", "internal",
        "lan", "test", "example", "invalid", "onion", "google", "apple", "microsoft", "amazon", "youtube",
        "gmail", "android", "chrome", "play", "zip", "mov", "foo", "bar", "baz", "ink", "wtf", "lol", "gg",
    ]

    nonisolated private static let countryCodes: Set<String> = Set("""
    ac ad ae af ag ai al am ao aq ar as at au aw ax az ba bb bd be bf bg bh bi bj bm bn bo br bs bt bw by bz \
    ca cc cd cf cg ch ci ck cl cm cn co cr cu cv cw cx cy cz de dj dk dm do dz ec ee eg er es et eu fi fj fk \
    fm fo fr ga gb gd ge gf gg gh gi gl gm gn gp gq gr gs gt gu gw gy hk hm hn hr ht hu id ie il im in io iq \
    ir is it je jm jo jp ke kg kh ki km kn kp kr kw ky kz la lb lc li lk lr ls lt lu lv ly ma mc md me mg mh \
    mk ml mm mn mo mp mq mr ms mt mu mv mw mx my mz na nc ne nf ng ni nl no np nr nu nz om pa pe pf pg ph pk \
    pl pm pn pr ps pt pw py qa re ro rs ru rw sa sb sc sd se sg sh si sk sl sm sn so sr ss st su sv sx sy sz \
    tc td tf tg th tj tk tl tm tn to tr tt tv tw tz ua ug uk us uy uz va vc ve vg vi vn vu wf ws ye yt za zm zw
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))
}
