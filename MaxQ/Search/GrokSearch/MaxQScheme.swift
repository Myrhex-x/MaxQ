//
//  MaxQScheme.swift
//  Max Q
//
//  Max Q's own pages inside a tab. "maxq://search?q=…" is the Grok search page: the tab's web view
//  loads an empty page at that address, so back, forward and reopening tabs treat it like any
//  other page, and Max Q draws the results natively over it.
//
//  Only Max Q can open these pages. A website navigating to one is refused (see TabController), so
//  no page can run searches, or spend the user's Grok credits, on its own.
//

import Foundation
import WebKit

/// Max Q's own pages other than search, each drawn natively over its tab's empty page.
nonisolated enum NativePage: Equatable, Hashable, Sendable {
    /// A research report ("maxq://research?id=…").
    case research(UUID)
    /// A collection ("maxq://collection?id=…").
    case collection(UUID)
    /// Making pictures with Grok ("maxq://imagine").
    case imagine
}

final class MaxQScheme: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "maxq"
    static let shared = MaxQScheme()

    /// The address of one of Max Q's own pages.
    nonisolated static func url(for page: NativePage) -> URL {
        switch page {
        case .research(let id): URL(string: "\(scheme)://research?id=\(id.uuidString)")!
        case .collection(let id): URL(string: "\(scheme)://collection?id=\(id.uuidString)")!
        case .imagine: URL(string: "\(scheme)://imagine")!
        }
    }

    /// The page an address names, for Max Q's own pages other than search.
    nonisolated static func nativePage(from url: URL?) -> NativePage? {
        guard let url, url.scheme?.lowercased() == scheme, let host = url.host else { return nil }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "id" })?.value.flatMap(UUID.init(uuidString:))
        switch host {
        case "research": return id.map(NativePage.research)
        case "collection": return id.map(NativePage.collection)
        case "imagine": return .imagine
        default: return nil
        }
    }

    /// The results page for `query`, opening on `tab` when it isn't the first one ("!x" opens the
    /// Posts on X tab).
    nonisolated static func searchURL(for query: String, tab: GrokSearchTab = .all, page: String? = nil) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Encoded like any engine's query ("+" as %2B), so the address reads back exactly.
        let encoded = String(trimmed.prefix(500)).addingPercentEncoding(withAllowedCharacters: SearchEngine.queryAllowed) ?? trimmed
        let opening = tab == .all ? "" : "&tab=\(tab.rawValue)"
        let article = page.flatMap { $0.addingPercentEncoding(withAllowedCharacters: SearchEngine.queryAllowed) }.map { "&page=\($0)" } ?? ""
        return URL(string: "\(scheme)://search?q=\(encoded)\(opening)\(article)")
    }

    /// The Grokipedia article a results page's address names, when it came from a link in another
    /// article ("&page=SpaceX").
    nonisolated static func page(from url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == scheme, url.host == "search",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "page" })?.value, !value.isEmpty,
              value.count <= 200, !value.contains("/") else { return nil }
        return value
    }

    /// The tab a results page's address asks to open on, when it names one.
    nonisolated static func tab(from url: URL?) -> GrokSearchTab? {
        guard let url, url.scheme?.lowercased() == scheme, url.host == "search",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "tab" })?.value else { return nil }
        return GrokSearchTab(rawValue: value)
    }

    /// The query of a Grok search page's address, or nil for anything else.
    nonisolated static func query(from url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == scheme, url.host == "search",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func isNative(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == scheme
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let query = Self.query(from: url) ?? Self.nativePage(from: url).map(Self.title(for:)) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        // The page under the native results: just a title, and the results' own background so
        // the swipe-back snapshot isn't a white flash.
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>\(Self.escape(query))</title>
        <meta name="color-scheme" content="light dark">
        <style>html,body{margin:0;height:100%;background:#131211}@media (prefers-color-scheme: light){html,body{background:#F9F8F7}}</style>
        </head><body></body></html>
        """
        let data = Data(html.utf8)
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    /// A native page's title, for its tab.
    static func title(for page: NativePage) -> String {
        switch page {
        case .research(let id):
            let report = ResearchStore.shared.report(id)
            return report.map { $0.title.isEmpty ? $0.question : $0.title } ?? String(localized: "Research")
        case .collection(let id):
            return CollectionStore.shared.collection(id)?.name ?? String(localized: "Collection")
        case .imagine:
            return String(localized: "Imagine")
        }
    }

    nonisolated static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension NativePage {
    /// The mark the address bar and tab rows show for the page.
    var icon: MQIcon {
        switch self {
        case .research: .lines
        case .collection: .stack
        case .imagine: .image
        }
    }
}
