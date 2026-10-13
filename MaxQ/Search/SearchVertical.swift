//
//  SearchVertical.swift
//  Max Q
//
//  Where a search runs: the chosen web search engine, Grokipedia's own search, or X's. A search
//  keeps its query across them, so one question can be looked at on the web, in Grokipedia and on
//  X with a click (the results pages are the sites' own).
//

import Foundation

nonisolated enum SearchVertical: String, CaseIterable, Identifiable, Sendable {
    case web, grokipedia, x

    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: String(localized: "Web")
        case .grokipedia: "Grokipedia"
        case .x: "X"
        }
    }

    /// The site whose own icon stands for this vertical (the web uses the search engine's).
    var iconSite: URL? {
        switch self {
        case .web: nil
        case .grokipedia: GrokipediaLinks.home
        case .x: XLinks.home
        }
    }

    @MainActor
    func url(for query: String) -> URL? {
        switch self {
        case .web: AppSettings.shared.searchEngine.searchURL(for: query)
        case .grokipedia: GrokipediaLinks.search(query)
        case .x: XLinks.search(for: query)
        }
    }

    /// Recognizes Grokipedia's and X's own search pages and reads their query.
    static func detect(_ url: URL) -> (vertical: SearchVertical, query: String)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(), components.path == "/search" else { return nil }
        let vertical: SearchVertical
        if host == "grokipedia.com" || host.hasSuffix(".grokipedia.com") {
            vertical = .grokipedia
        } else if ["x.com", "twitter.com", "www.x.com", "mobile.x.com"].contains(host) {
            vertical = .x
        } else {
            return nil
        }
        let raw = components.percentEncodedQueryItems?.first(where: { $0.name == "q" })?.value
        let query = raw?.replacingOccurrences(of: "+", with: " ").removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let query, !query.isEmpty else { return nil }
        return (vertical, query)
    }
}
