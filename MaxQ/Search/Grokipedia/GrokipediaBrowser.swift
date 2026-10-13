//
//  GrokipediaBrowser.swift
//  Max Q
//
//  How Max Q reads Grokipedia: the way a browser does. An article, or Grokipedia's own search
//  page, loads in WebKit in a web view of its own (nothing kept on disk, one page at a time,
//  only when a search or a click asks for it), and Max Q reads the page as it was shown, the way
//  Reader does. Nothing goes to Grokipedia's API, which its robots.txt keeps off limits, and no
//  addresses are guessed: an article is found through Grokipedia's own search.
//

import Foundation
import WebKit

/// A Grokipedia page as it loaded.
nonisolated struct LoadedPage: Sendable {
    let status: Int
    let html: String
    let url: URL?
}

@MainActor
final class GrokipediaBrowser: NSObject, WKNavigationDelegate {
    static let shared = GrokipediaBrowser()

    private var webView: WKWebView?
    private var last: Task<Void, Never>?
    private var finished: CheckedContinuation<Bool, Never>?
    private var status = 0
    /// Which load the pending timeout belongs to, so a late one can't end the next load.
    private var loadID = 0

    /// Loads `url` (after any page already loading) and returns it as shown, once `selector`
    /// matches when one is given, or nil when it didn't load in time.
    func load(_ url: URL, waitFor selector: String? = nil, timeout: Double = 15) async -> LoadedPage? {
        let previous = last
        let task = Task { @MainActor () -> LoadedPage? in
            await previous?.value
            return await self.perform(url, selector: selector, timeout: timeout)
        }
        last = Task { _ = await task.value }
        return await task.value
    }

    private func perform(_ url: URL, selector: String?, timeout: Double) async -> LoadedPage? {
        let webView = self.webView ?? makeWebView()
        status = 0
        let deadline = Date().addingTimeInterval(timeout)
        loadID += 1
        let id = loadID
        let loaded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            finished = continuation
            webView.load(URLRequest(url: url))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, self.loadID == id else { return }
                self.resume(false)
            }
        }
        guard loaded else {
            webView.stopLoading()
            return nil
        }
        if let selector {
            while Date() < deadline {
                let found = (try? await webView.evaluateJavaScript("!!document.querySelector(\(Self.quoted(selector)))")) as? Bool ?? false
                if found { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        let html = (try? await webView.evaluateJavaScript("document.documentElement.outerHTML")) as? String ?? ""
        let page = LoadedPage(status: status, html: html, url: webView.url)
        // Nothing keeps running once the page is read.
        webView.loadHTMLString("", baseURL: nil)
        return page
    }

    private func makeWebView() -> WKWebView {
        let configuration = WebViewFactory.makeConfiguration(dataStore: .nonPersistent(), forTabs: false)
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    private func resume(_ loaded: Bool) {
        finished?.resume(returning: loaded)
        finished = nil
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse {
            status = http.statusCode
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Grokipedia's own pages only: a link or a redirect elsewhere isn't followed.
        guard let host = navigationAction.request.url?.host?.lowercased(), navigationAction.targetFrame?.isMainFrame ?? false else {
            return .allow
        }
        return host == "grokipedia.com" || host.hasSuffix(".grokipedia.com") ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.absoluteString != "about:blank" else { return }
        resume(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resume(false)
    }
}

/// One result of Grokipedia's own search.
nonisolated struct GrokipediaSearchResult: Equatable, Sendable {
    let slug: String
    let title: String
    let snippet: String

    var url: URL? { URL(string: GrokipediaSlugCatalog.pageURL(for: slug)) }
}

/// Grokipedia's own search, read from its page as a browser shows it, and kept a few minutes so
/// the card and the list under the article share one search.
nonisolated enum GrokipediaSearchClient {
    private actor Cache {
        var entries: [String: (results: [GrokipediaSearchResult], date: Date)] = [:]
        func get(_ key: String) -> [GrokipediaSearchResult]? {
            guard let entry = entries[key], Date().timeIntervalSince(entry.date) < 10 * 60 else { return nil }
            return entry.results
        }
        func set(_ key: String, _ results: [GrokipediaSearchResult]) {
            if entries.count > 60 { entries.removeAll() }
            entries[key] = (results, Date())
        }
    }

    private static let cache = Cache()

    static func results(for query: String) async -> [GrokipediaSearchResult] {
        let key = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        if let cached = await cache.get(key) { return cached }
        guard let url = GrokipediaLinks.search(query),
              let page = await GrokipediaBrowser.shared.load(url, waitFor: "a[data-search-result-link]", timeout: 12),
              (200..<300).contains(page.status) || page.status == 0 else { return [] }
        let results = parse(page.html)
        await cache.set(key, results)
        return results
    }

    /// The results of a search page: each `<a data-search-result-link … data-slug="…">` with its
    /// heading and its snippet.
    static func parse(_ html: String) -> [GrokipediaSearchResult] {
        var results: [GrokipediaSearchResult] = []
        var seen = Set<String>()
        for block in html.components(separatedBy: "<a ").dropFirst() {
            guard let end = block.range(of: "</a>") else { continue }
            let anchor = String(block[..<end.lowerBound])
            let tag = " " + openingTag(anchor)
            guard tag.contains("data-search-result-link"), let slug = attribute("data-slug", in: tag).map(WebSearchClient.decodeEntities),
                  !slug.isEmpty,
                  seen.insert(slug.lowercased()).inserted else { continue }
            let heading = anchor.range(of: #"(?s)<h3[^>]*>(.*?)</h3>"#, options: [.regularExpression])
                .map { WebSearchClient.plainText(String(anchor[$0])) } ?? ""
            let snippet = attribute("data-search-snippet", in: tag).map(text(ofAttribute:)) ?? ""
            let title = heading.isEmpty ? slug.replacingOccurrences(of: "_", with: " ") : heading
            results.append(GrokipediaSearchResult(slug: slug, title: title, snippet: snippet))
        }
        return results
    }

    /// The attributes of a tag, up to its `>` (one inside a quoted value doesn't count).
    private static func openingTag(_ text: String) -> String {
        var quoted = false
        for index in text.indices {
            if text[index] == "\"" { quoted.toggle() }
            if text[index] == ">", !quoted { return String(text[..<index]) }
        }
        return text
    }

    /// What an attribute says: its entities read once, any markup in it left out.
    private static func text(ofAttribute value: String) -> String {
        WebSearchClient.decodeEntities(value)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An attribute's value as written (entities and all).
    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: #"\s"# + name + #"=""#, options: .regularExpression) else { return nil }
        let rest = tag[range.upperBound...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }
}
