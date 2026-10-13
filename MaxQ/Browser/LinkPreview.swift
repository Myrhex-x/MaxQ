//
//  LinkPreview.swift
//  Max Q
//
//  A look at where a link goes before going there. In the readers (Grokipedia's and any page's), a
//  link the pointer rests on shows a card: another Grokipedia article's picture and opening lines,
//  or a web page's title, site, summary and picture. On any web page, holding ⌥ over a link does
//  the same.
//
//  A web page's card is read from the page's own metadata (its title and the summary it gives for
//  sharing), fetched without cookies, only when asked: by resting on a link in a reader, or by
//  holding ⌥ on a page.
//

import AppKit
import SwiftUI
import WebKit

/// What a card shows about a link.
nonisolated struct LinkPreviewInfo: Equatable, Sendable {
    let url: URL
    var title: String
    var summary: String?
    var image: URL?
    var site: String
    /// A Grokipedia article (its title in the serif).
    var isArticle = false
}

nonisolated enum LinkPreviewClient {
    private actor Cache {
        var entries: [URL: LinkPreviewInfo] = [:]
        func get(_ url: URL) -> LinkPreviewInfo? { entries[url] }
        func set(_ url: URL, _ info: LinkPreviewInfo) {
            if entries.count > 150 { entries.removeAll() }
            entries[url] = info
        }
    }

    private static let cache = Cache()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// The page's title, summary and picture, from its metadata.
    static func info(for url: URL) async -> LinkPreviewInfo? {
        if let cached = await cache.get(url) { return cached }
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        var request = URLRequest(url: url)
        request.setValue(WebViewFactory.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              (http.value(forHTTPHeaderField: "Content-Type") ?? "text/html").contains("html") else { return nil }
        // The head is enough: stop after half a megabyte, or once the body starts.
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > 512_000 { break }
                if data.count % 4_096 == 0, String(decoding: data.suffix(8_192), as: UTF8.self).lowercased().contains("<body") { break }
            }
        } catch {
            return nil
        }
        let html = String(decoding: data, as: UTF8.self)
        let info = parse(html, url: http.url ?? url)
        if let info { await cache.set(url, info) }
        return info
    }

    /// Reads og:title, og:description, og:image and og:site_name (or the page's title and
    /// description).
    static func parse(_ html: String, url: URL) -> LinkPreviewInfo? {
        func meta(_ names: [String]) -> String? {
            for name in names {
                for pattern in [#"<meta[^>]+(?:property|name)=["']\#(name)["'][^>]*content=["']([^"']*)["']"#,
                                #"<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']\#(name)["']"#] {
                    if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                        let tag = String(html[range])
                        if let content = tag.range(of: #"content=["']([^"']*)["']"#, options: [.regularExpression, .caseInsensitive]) {
                            let value = String(tag[content]).dropFirst(9).dropLast()
                            let clean = WebSearchClient.decodeEntities(String(value)).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty { return clean }
                        }
                    }
                }
            }
            return nil
        }
        let title = meta(["og:title", "twitter:title"])
            ?? html.range(of: #"<title[^>]*>([^<]*)</title>"#, options: [.regularExpression, .caseInsensitive])
                .map { WebSearchClient.plainText(String(html[$0])) }
        guard let title, !title.isEmpty else { return nil }
        let image = meta(["og:image", "og:image:url", "twitter:image"]).flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
        let host = url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        return LinkPreviewInfo(url: url, title: title, summary: meta(["og:description", "description", "twitter:description"]),
                               image: image, site: meta(["og:site_name"]) ?? host)
    }
}

/// Shows a link's card after the pointer has rested on it a moment, and takes it away when the
/// pointer leaves.
@MainActor
final class LinkPreviewPresenter {
    static let shared = LinkPreviewPresenter()

    private var pending: Task<Void, Never>?
    private var shown: (url: URL, controller: PopoverController)?

    /// The pointer is on `url` at `rect` (or left the link: nil).
    func hover(_ url: URL?, at rect: NSRect, in window: NSWindow?, open: @escaping (URL) -> Void) {
        pending?.cancel()
        guard let url, let window, rect.width > 0 else {
            hide()
            return
        }
        if shown?.url == url { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            let info = await Self.info(for: url)
            guard !Task.isCancelled, let info else { return }
            self.hide()
            let controller = PopoverController.show(at: rect, in: window, placement: .below(.leading)) {
                LinkPreviewCard(info: info) { open(url) }
            }
            self.shown = (url, controller)
        }
    }

    func hide() {
        pending?.cancel()
        if let shown {
            shown.controller.dismiss()
            self.shown = nil
        }
    }

    /// A Grokipedia article's card, or a web page's.
    private static func info(for url: URL) async -> LinkPreviewInfo? {
        if url.scheme == ArticleLinks.articleScheme, let (page, title) = ArticleLinks.article(from: url) {
            guard let card = await GrokipediaService.card(forPage: page, query: title) else { return nil }
            return LinkPreviewInfo(url: card.articleURL, title: card.title, summary: card.summary, image: card.imageCandidates.first,
                                   site: "Grokipedia", isArticle: true)
        }
        if url.scheme == ArticleLinks.citationScheme { return nil }
        return await LinkPreviewClient.info(for: url)
    }
}

struct LinkPreviewCard: View {
    let info: LinkPreviewInfo
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = info.image {
                FillImage(candidates: [image],
                          referer: info.isArticle ? "https://grokipedia.com/" : nil)
                    .frame(width: 340, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 6) {
                if info.isArticle { Icon(.book, size: 13) } else { ResultIcon(host: info.url.host ?? "", size: 13) }
                Text(info.site)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            Text(info.title)
                .font(info.isArticle ? .serif(20, weight: .medium) : .system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = info.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(info.isArticle ? "Click to read the article" : (info.url.host ?? info.url.absoluteString))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textQuaternary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 368, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
        .onTapGesture(perform: open)
    }
}

// MARK: - Holding ⌥ on a page

/// The page script: holding ⌥ over a link (or pressing ⌥ while over one) asks for its card.
/// Runs in Max Q's isolated world, so the page can neither see it nor call it.
enum LinkPreviewScript {
    static let handlerName = "maxqLinkPreview"

    static let source = """
    (function () {
      if (window.__maxqLinkPreview) return;
      window.__maxqLinkPreview = true;
      var current = null, timer = null;
      function post(message) { try { window.webkit.messageHandlers.\(handlerName).postMessage(message); } catch (e) {} }
      function linkAt(node) {
        while (node && node.nodeType === 1 && node.tagName !== 'A') node = node.parentElement;
        return node && node.tagName === 'A' && /^https?:/.test(node.href) ? node : null;
      }
      function send(a) {
        var r = a.getBoundingClientRect();
        post({ href: a.href, x: r.left, y: r.top, w: r.width, h: r.height });
      }
      document.addEventListener('mouseover', function (e) {
        var a = linkAt(e.target);
        if (a === current) return;
        if (current && !a) post({ href: null });
        current = a;
        clearTimeout(timer);
        if (a && e.altKey) timer = setTimeout(function () { send(a); }, 250);
      }, true);
      document.addEventListener('keydown', function (e) { if (e.key === 'Alt' && current) send(current); }, true);
      document.addEventListener('keyup', function (e) { if (e.key === 'Alt') post({ href: null }); }, true);
      window.addEventListener('scroll', function () { if (current) post({ href: null }); }, { passive: true, capture: true });
    })();
    """

    static func install(in configuration: WKWebViewConfiguration) {
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(LinkPreviewHandler.shared, contentWorld: .defaultClient, name: handlerName)
    }
}

final class LinkPreviewHandler: NSObject, WKScriptMessageHandler {
    static let shared = LinkPreviewHandler()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard AppSettings.shared.linkPreviews, let webView = message.webView as? MaxQWebView,
              let browser = webView.tab?.browser, webView.tab?.isSelected == true,
              let body = message.body as? [String: Any] else { return }
        guard let href = body["href"] as? String, let url = URL(string: href),
              let x = (body["x"] as? NSNumber)?.doubleValue, let y = (body["y"] as? NSNumber)?.doubleValue,
              let w = (body["w"] as? NSNumber)?.doubleValue, let h = (body["h"] as? NSNumber)?.doubleValue,
              let rect = webView.screenRect(forPage: CGRect(x: x, y: y, width: w, height: h)) else {
            LinkPreviewPresenter.shared.hide()
            return
        }
        LinkPreviewPresenter.shared.hover(url, at: rect, in: browser.window) { url in
            LinkPreviewPresenter.shared.hide()
            browser.openInNewTab(url)
        }
    }
}
