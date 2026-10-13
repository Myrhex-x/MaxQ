//
//  WebSearchClient.swift
//  Max Q
//
//  What a web result is, and the text helpers the results page shares: snippets with the matched
//  words in bold, HTML entities, dates as a results page says them. The results themselves come
//  from the search API the user has a key for (BraveSearch.swift); DuckDuckGo's own page is a
//  link away for the same search, and its published suggestions fill "Related searches".
//

import Foundation

nonisolated struct WebResult: Identifiable, Hashable, Sendable {
    var id: String { url.absoluteString }
    let title: String
    let url: URL
    /// The snippet, in runs: the words that match the query are bold.
    let snippet: [SnippetRun]
    /// When the page was published or last changed, when the search knows.
    var date: Date? = nil
    /// `date` is a day, without a time of day.
    var dateIsDay = false
    /// The site's icon, as the search serves it.
    var favicon: URL? = nil
    /// A still for the page (a video's), as the search serves it.
    var still: URL? = nil

    var host: String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The address as a breadcrumb: "en.wikipedia.org › wiki › SpaceX".
    var breadcrumb: String {
        let parts = url.path.split(separator: "/").prefix(3).map { $0.removingPercentEncoding ?? String($0) }
        return ([host] + parts.map { $0.count > 28 ? String($0.prefix(26)) + "…" : $0 }).joined(separator: " › ")
    }

    var plainSnippet: String { snippet.map(\.text).joined() }

    /// The video's id, when the result is a YouTube video.
    var youTubeID: String? {
        guard let host = url.host?.lowercased() else { return nil }
        let id: String?
        if host == "youtu.be" {
            id = url.pathComponents.dropFirst().first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if url.path == "/watch" {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            } else if url.pathComponents.count >= 3, ["shorts", "live", "embed"].contains(url.pathComponents[1]) {
                id = url.pathComponents[2]
            } else {
                id = nil
            }
        } else {
            id = nil
        }
        guard let id, (6...20).contains(id.count),
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    /// A video's still, as the search served it.
    var thumbnail: URL? { youTubeID == nil ? nil : still }
}

nonisolated struct SnippetRun: Hashable, Sendable {
    let text: String
    let bold: Bool
}

nonisolated enum WebSearchError: LocalizedError, Equatable {
    case offline
    case blocked
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .offline: String(localized: "Your Mac isn't connected to the internet.")
        case .blocked: String(localized: "The site asked Max Q to slow down. Try again in a moment.")
        case .failed(let detail): String(localized: "Web results didn't load (\(detail)).")
        }
    }
}

nonisolated enum WebSearchClient {
    /// Where the same search opens as DuckDuckGo's own page.
    static func siteURL(for query: String) -> URL? {
        SearchEngine.builtIn(.duckduckgo)?.searchURL(for: query)
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// DuckDuckGo's suggestions for a search (the address its OpenSearch description publishes for
    /// browsers), through a cookieless session.
    static func suggestions(_ url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }

    static func snippetRuns(_ html: String) -> [SnippetRun] {
        var runs: [SnippetRun] = []
        var bold = false
        var rest = Substring(html)
        while !rest.isEmpty {
            guard let tag = rest.range(of: "<") else {
                append(String(rest), bold: bold, to: &runs)
                break
            }
            append(String(rest[..<tag.lowerBound]), bold: bold, to: &runs)
            guard let close = rest.range(of: ">", range: tag.upperBound..<rest.endIndex) else { break }
            let name = rest[tag.upperBound..<close.lowerBound].lowercased()
            if name == "b" || name == "strong" { bold = true }
            if name == "/b" || name == "/strong" { bold = false }
            rest = rest[close.upperBound...]
        }
        // Tidy whitespace across runs.
        var tidied: [SnippetRun] = []
        for run in runs {
            let collapsed = run.text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if let last = tidied.last, last.bold == run.bold {
                tidied[tidied.count - 1] = SnippetRun(text: last.text + collapsed, bold: run.bold)
            } else {
                tidied.append(SnippetRun(text: collapsed, bold: run.bold))
            }
        }
        if let first = tidied.first {
            tidied[0] = SnippetRun(text: String(first.text.drop(while: \.isWhitespace)), bold: first.bold)
        }
        if let last = tidied.last {
            tidied[tidied.count - 1] = SnippetRun(text: String(last.text.reversed().drop(while: \.isWhitespace).reversed()), bold: last.bold)
        }
        return tidied.filter { !$0.text.isEmpty }
    }

    private static func append(_ html: String, bold: Bool, to runs: inout [SnippetRun]) {
        let text = decodeEntities(html)
        guard !text.isEmpty else { return }
        runs.append(SnippetRun(text: text, bold: bold))
    }

    static func plainText(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(stripped)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let entity = String(after[..<semi])
                if let decoded = decodeEntity(entity) {
                    out += decoded
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        out += rest
        return out
    }

    private static func decodeEntity(_ entity: String) -> String? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " "
        case "hellip": return "…"
        case "mdash": return "\u{2014}"
        case "ndash": return "\u{2013}"
        case "rsquo": return "\u{2019}"
        case "lsquo": return "\u{2018}"
        case "rdquo": return "\u{201D}"
        case "ldquo": return "\u{201C}"
        default: break
        }
        if entity.hasPrefix("#x") || entity.hasPrefix("#X"), let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
            return String(Character(scalar))
        }
        if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
            return String(Character(scalar))
        }
        return nil
    }

}

/// How recent results must be.
nonisolated enum SearchTime: String, CaseIterable, Identifiable, Sendable {
    case any, day, week, month, year
    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: String(localized: "Any time")
        case .day: String(localized: "Past day")
        case .week: String(localized: "Past week")
        case .month: String(localized: "Past month")
        case .year: String(localized: "Past year")
        }
    }
}

/// When a result's page changed, the way a results page says it: "3 hours ago", "yesterday",
/// "5 days ago", then the date.
nonisolated enum ResultDate {
    static func label(_ date: Date, isDay: Bool, now: Date = Date(), locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let relative = RelativeDateTimeFormatter()
        relative.locale = locale
        relative.unitsStyle = .full
        relative.dateTimeStyle = .named
        if isDay {
            // A day, as the search gives it (in UTC): counted in days from today.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC") ?? .current
            let parts = utc.dateComponents([.year, .month, .day], from: date)
            let today = calendar.startOfDay(for: now)
            if let day = calendar.date(from: parts) {
                let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
                if (0...6).contains(days) { return relative.localizedString(from: DateComponents(day: -days)) }
            }
        } else if now.timeIntervalSince(date) < 86_400, now.timeIntervalSince(date) >= 0 {
            return relative.localizedString(for: date, relativeTo: now)
        } else if now.timeIntervalSince(date) < 7 * 86_400, now.timeIntervalSince(date) >= 0 {
            let days = max(1, Int(now.timeIntervalSince(date) / 86_400))
            return relative.localizedString(from: DateComponents(day: -days))
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = isDay ? TimeZone(identifier: "UTC") : .current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
        return formatter.string(from: date)
    }
}
