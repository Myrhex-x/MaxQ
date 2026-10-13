//
//  SearchEngine.swift
//  Max Q
//
//  The search engines a user can pick. Max Q is the browser's own results page (Grok's answer, web
//  results, Grokipedia and X on one page, drawn natively); the classic engines open their own page
//  in a tab, with Grokipedia beside it. Pure logic, unit-tested.
//

import Foundation

nonisolated enum SearchEngineID: String, CaseIterable, Codable, Identifiable {
    /// Max Q's own results page. Saved as "grok", its name before it was called Max Q.
    case maxq = "grok"
    case duckduckgo, google, brave, bing, startpage, ecosia, custom
    var id: String { rawValue }

    /// Engines whose results are a page on their own site (everything but Max Q's own).
    static var classic: [SearchEngineID] { allCases.filter { $0 != .maxq && $0 != .custom } }
}

nonisolated struct SearchEngine: Equatable {
    let id: SearchEngineID
    let name: String
    /// Results URL with `%s` where the encoded query goes.
    let searchTemplate: String
    /// OpenSearch-style suggestions endpoint (`["q", ["a", "b"]]`), or nil when the engine has none.
    let suggestTemplate: String?

    nonisolated static func builtIn(_ id: SearchEngineID) -> SearchEngine? {
        switch id {
        case .maxq:
            // Max Q's own page. Suggestions come from DuckDuckGo's published suggestion address; its
            // web results come from the Brave Search API with the user's own key.
            return SearchEngine(id: id, name: "Max Q",
                                searchTemplate: "maxq://search?q=%s",
                                suggestTemplate: "https://duckduckgo.com/ac/?q=%s&type=list")
        case .duckduckgo:
            return SearchEngine(id: id, name: "DuckDuckGo",
                                searchTemplate: "https://duckduckgo.com/?q=%s",
                                suggestTemplate: "https://duckduckgo.com/ac/?q=%s&type=list")
        case .google:
            return SearchEngine(id: id, name: "Google",
                                searchTemplate: "https://www.google.com/search?q=%s",
                                suggestTemplate: "https://suggestqueries.google.com/complete/search?client=firefox&q=%s")
        case .brave:
            return SearchEngine(id: id, name: "Brave Search",
                                searchTemplate: "https://search.brave.com/search?q=%s",
                                suggestTemplate: "https://search.brave.com/api/suggest?q=%s")
        case .bing:
            return SearchEngine(id: id, name: "Bing",
                                searchTemplate: "https://www.bing.com/search?q=%s",
                                suggestTemplate: "https://api.bing.com/osjson.aspx?query=%s")
        case .startpage:
            return SearchEngine(id: id, name: "Startpage",
                                searchTemplate: "https://www.startpage.com/do/search?q=%s",
                                suggestTemplate: nil)
        case .ecosia:
            return SearchEngine(id: id, name: "Ecosia",
                                searchTemplate: "https://www.ecosia.org/search?q=%s",
                                suggestTemplate: "https://ac.ecosia.org/autocomplete?q=%s&type=list")
        case .custom:
            return nil
        }
    }

    nonisolated static func custom(template: String) -> SearchEngine? {
        guard isValidTemplate(template) else { return nil }
        let host = URL(string: template.replacingOccurrences(of: "%s", with: "q"))?.host ?? String(localized: "Custom")
        return SearchEngine(id: .custom, name: host, searchTemplate: template, suggestTemplate: nil)
    }

    /// A custom template must be https and contain exactly one `%s`.
    nonisolated static func isValidTemplate(_ template: String) -> Bool {
        let t = template.trimmingCharacters(in: .whitespaces)
        guard t.components(separatedBy: "%s").count == 2,
              let url = URL(string: t.replacingOccurrences(of: "%s", with: "test")),
              url.scheme == "https", url.host?.isEmpty == false else { return false }
        return true
    }

    nonisolated static let queryAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=#?/")
        return set
    }()

    /// Whether results are Max Q's own page rather than a website.
    nonisolated var isMaxQ: Bool { id == .maxq }

    /// Who receives what's typed for suggestions (Max Q's page takes them from DuckDuckGo).
    nonisolated var suggestionProvider: String { isMaxQ ? "DuckDuckGo" : name }

    nonisolated func searchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? query
        return URL(string: searchTemplate.replacingOccurrences(of: "%s", with: encoded))
    }

    nonisolated func suggestURL(for query: String) -> URL? {
        guard let suggestTemplate else { return nil }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? query
        return URL(string: suggestTemplate.replacingOccurrences(of: "%s", with: encoded))
    }

    /// If `url` is this engine's results page, the query it shows. Works for any template by
    /// finding which query parameter carries `%s`.
    nonisolated func query(fromResultsURL url: URL) -> String? {
        guard let template = URLComponents(string: searchTemplate.replacingOccurrences(of: "%s", with: "MAXQ_QUERY")),
              let param = template.queryItems?.first(where: { $0.value == "MAXQ_QUERY" })?.name,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, let templateHost = template.host,
              Self.sameSite(host, templateHost),
              components.path == template.path || (components.path.isEmpty && template.path == "/")
        else { return nil }
        // Results URLs are form-encoded: "+" is a space and a real plus arrives as "%2B", so the
        // pluses have to become spaces before percent-decoding.
        let raw = components.percentEncodedQueryItems?.first(where: { $0.name == param })?.value
        let value = raw?.replacingOccurrences(of: "+", with: " ").removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    nonisolated private static func sameSite(_ a: String, _ b: String) -> Bool {
        func strip(_ h: String) -> String { h.lowercased().hasPrefix("www.") ? String(h.lowercased().dropFirst(4)) : h.lowercased() }
        return strip(a) == strip(b)
    }

    /// Parses an OpenSearch suggestions payload: `["query", ["s1", "s2", ...], ...]`.
    nonisolated static func parseSuggestions(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              root.count >= 2, let list = root[1] as? [Any] else { return [] }
        return list.compactMap { $0 as? String }
    }
}
