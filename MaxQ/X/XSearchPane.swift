//
//  XSearchPane.swift
//  Max Q
//
//  The "Posts on X" tab of Grok's results page: x.com's own search for the same words, in the
//  user's own X account (the window's website data, as in any tab), shown as X serves it. Max Q
//  reads nothing out of it and changes nothing on it. It only hands links back to the browser: a
//  post, a profile or any other part of X opens in the tab (Back returns to the results), ⌘-click
//  opens a new tab, and x.com's own search tabs (Top, Latest, People, Media) stay in place.
//  One pane per window, moved to whichever results page shows it.
//

import AppKit
import SwiftUI
import WebKit

@MainActor
@Observable
final class XSearchPane: NSObject {
    enum State: Equatable {
        case idle, loading, ready
        /// x.com wants the user signed in before it searches.
        case needsSignIn
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var query: String?
    /// Posts open in a tab of their own (the side panel's pane), rather than in the tab on screen.
    var linksOpenInNewTab = false
    @ObservationIgnored private var latest = false

    @ObservationIgnored private weak var browser: BrowserModel?
    @ObservationIgnored private var view: WKWebView?
    @ObservationIgnored private var urlObservation: NSKeyValueObservation?
    @ObservationIgnored private var readyTimer: Task<Void, Never>?

    static let handlerName = "maxqXPane"

    init(browser: BrowserModel) {
        self.browser = browser
    }

    var webView: WKWebView {
        if let view { return view }
        let configuration = WebViewFactory.makeConfiguration(dataStore: browser?.websiteDataStore ?? .default(), forTabs: false)
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: .defaultClient))
        controller.add(WeakScriptHandler(self), contentWorld: .defaultClient, name: Self.handlerName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            let url = webView.url
            MainActor.assumeIsolated { self?.urlChanged(url) }
        }
        view = webView
        return webView
    }

    /// Shows x.com's search for `query` (on its Latest tab with `latest`), loading it unless it's
    /// already there.
    func show(query: String, latest: Bool = false) {
        let webView = webView
        let retry = state == .needsSignIn || state.isFailure
        guard query != self.query || latest != self.latest || retry || webView.url == nil else { return }
        guard let url = XLinks.search(for: query, latest: latest) else { return }
        self.query = query
        self.latest = latest
        state = .loading
        webView.load(URLRequest(url: url))
        // x.com fills the page after it loads; never leave the placeholder up for long.
        readyTimer?.cancel()
        readyTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled, self.state == .loading else { return }
            self.state = .ready
        }
    }

    func reload() {
        guard let query else { return }
        self.query = nil
        show(query: query, latest: latest)
    }

    // MARK: - Where x.com goes

    nonisolated static func isX(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return ["x.com", "twitter.com", "www.x.com", "mobile.x.com", "www.twitter.com", "mobile.twitter.com"].contains(host)
    }

    /// x.com's sign-in pages, where a signed-out search ends up.
    nonisolated static func isSignIn(_ url: URL?) -> Bool {
        guard let url, isX(url.host) else { return false }
        let path = url.path.lowercased()
        return path.hasPrefix("/i/flow/login") || path.hasPrefix("/i/flow/signup") || path == "/login"
            || path.hasPrefix("/i/jf/onboarding")
    }

    private func urlChanged(_ url: URL?) {
        if Self.isSignIn(url) {
            state = .needsSignIn
            view?.stopLoading()
        }
    }

    fileprivate func received(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, Self.isX(message.frameInfo.securityOrigin.host),
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            if state == .loading { state = .ready }
        case "signedOut":
            state = .needsSignIn
        case "open":
            guard let href = body["href"] as? String, let url = URL(string: href), url.scheme == "https",
                  Self.isX(url.host), let browser else { return }
            if body["newTab"] as? Bool == true {
                browser.openInNewTab(url, select: body["select"] as? Bool == true)
            } else if linksOpenInNewTab {
                browser.openInNewTab(url, select: true)
            } else {
                browser.navigate(.url(url))
            }
        default:
            break
        }
    }

    /// Tells Max Q when x.com's search is up or wants a sign-in, and passes links back to it. Runs in
    /// Max Q's own script world, out of the page's reach; x.com's page itself is left as it is.
    private static let script = #"""
    (() => {
      if (window.top !== window) return;

      const post = (body) => { try { window.webkit.messageHandlers.maxqXPane.postMessage(body); } catch (_) {} };

      const ready = () => !!document.querySelector('article[data-testid="tweet"], [data-testid="emptyState"], [data-testid="UserCell"]');
      // Signed out, x.com sends a search to its sign-in pages (or puts a sign-in sheet over it).
      const signedOut = () => /^\/(i\/flow\/(login|signup)|i\/jf\/onboarding|login)/.test(location.pathname) ||
        !!document.querySelector('input[autocomplete~="username"], input[name="username_or_email"], input[type="password"]');
      let announced = false;
      const watch = new MutationObserver(() => {
        if (signedOut()) { post({ type: 'signedOut' }); watch.disconnect(); }
        else if (!announced && ready()) { announced = true; post({ type: 'ready' }); }
      });
      // Watch for a sign-in sheet a little longer than for the first posts.
      setTimeout(() => watch.disconnect(), 20000);
      const startWatching = () => watch.observe(document.documentElement, { childList: true, subtree: true });
      if (document.documentElement) startWatching(); else document.addEventListener('DOMContentLoaded', startWatching);

      const isX = (host) => /^(www\.|mobile\.)?(x|twitter)\.com$/i.test(host);
      document.addEventListener('click', (event) => {
        if (event.button !== 0 || !event.isTrusted) return;
        const target = event.target instanceof Element ? event.target : null;
        if (!target) return;
        let href = null;
        const anchor = target.closest('a[href]');
        if (anchor) {
          const url = new URL(anchor.getAttribute('href'), location.href);
          if (!isX(url.hostname)) return;
          // x.com's own search tabs, hashtags and sign-in stay here; the rest of X opens in the tab.
          if (url.pathname === '/search' || url.pathname.startsWith('/hashtag/') || url.pathname.startsWith('/i/flow/')) return;
          href = url.href;
        } else {
          if (target.closest('button, [role="button"], [role="menuitem"], [role="tab"], input, textarea, video, [data-testid="videoPlayer"]')) return;
          const article = target.closest('article');
          const permalink = article && article.querySelector('a[href*="/status/"] time');
          if (!permalink || !permalink.parentElement) return;
          href = new URL(permalink.parentElement.getAttribute('href'), location.href).href;
        }
        event.preventDefault();
        event.stopImmediatePropagation();
        post({ type: 'open', href, newTab: event.metaKey, select: event.shiftKey });
      }, true);
    })();
    """#
}

extension XSearchPane: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if ["about", "blob", "data"].contains(url.scheme ?? "") { decisionHandler(.allow); return }
        // Frames inside x.com (video players, embeds) load as they would in a tab.
        guard navigationAction.targetFrame?.isMainFrame ?? false else { decisionHandler(.allow); return }
        if Self.isX(url.host) || url.host?.hasSuffix(".twimg.com") == true {
            if Self.isSignIn(url) { state = .needsSignIn; decisionHandler(.cancel); return }
            decisionHandler(.allow)
            return
        }
        // Anywhere else on the web opens in a tab of its own, as a link out of a post does on x.com.
        if navigationAction.navigationType == .linkActivated, url.scheme == "https" || url.scheme == "http" {
            browser?.openInNewTab(url, select: !navigationAction.modifierFlags.contains(.command))
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    private func failed(_ error: Error) {
        let code = (error as NSError).code
        // A load replaced by another one isn't a failure.
        guard code != NSURLErrorCancelled, code != 102, state != .needsSignIn else { return }
        state = .failed(code == NSURLErrorNotConnectedToInternet ? String(localized: "Your Mac isn't connected to the internet.") : String(localized: "x.com didn't load."))
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Links x.com opens in a new window (a post's outbound links) open in a new tab.
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme ?? "") {
            browser?.openInNewTab(url, select: !navigationAction.modifierFlags.contains(.command))
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }
}

extension XSearchPane.State {
    var isFailure: Bool { if case .failed = self { true } else { false } }
}

/// Holds a script message handler weakly, so the web view's controller doesn't keep it alive.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var pane: XSearchPane?

    init(_ pane: XSearchPane) { self.pane = pane }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { pane?.received(message) }
    }
}

/// Hosts the pane's web view inside a results page. Hidden while its page is off to the side, so
/// it never draws outside the page during a slide.
struct XSearchHost: NSViewRepresentable {
    let pane: XSearchPane
    let visible: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if pane.webView.superview !== container { attach(to: container) }
        pane.webView.isHidden = !visible
    }

    private func attach(to container: NSView) {
        let webView = pane.webView
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
