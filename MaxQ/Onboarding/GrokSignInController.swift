//
//  GrokSignInController.swift
//  Max Q
//
//  The web view behind setup's "Sign in to grok.com" card. It shows SpaceXAI's own sign-in page in
//  the browser's normal, persistent website data, so the session it creates is the one the tabs and
//  the Grok panel use, and it lasts like any site's. Max Q doesn't script the page or read what's
//  typed; GrokWebAccount notices the session cookie once SpaceXAI sets it.
//
//  Sign in with Google, Apple or X may open a window: it opens over the page, inside the card, and
//  closes itself when done.
//

import AppKit
import Observation
import WebKit

@MainActor
@Observable
final class GrokSignInController: NSObject, WKNavigationDelegate, WKUIDelegate {
    @ObservationIgnored let container = NSView()
    private(set) var isLoading = false
    /// Links that leave the sign-in pages (terms, privacy) open as a browser tab.
    @ObservationIgnored var openElsewhere: ((URL) -> Void)?

    /// Set once the sign-in comes back to grok.com itself (past SpaceXAI's sign-in pages): the
    /// account is signed in, whatever the session cookie turns out to be called.
    private(set) var landedOnGrok = false

    @ObservationIgnored private var webViews: [WKWebView] = []
    @ObservationIgnored private var loadingObservation: NSKeyValueObservation?
    @ObservationIgnored private var urlObservation: NSKeyValueObservation?
    @ObservationIgnored private var visitedSignIn = false

    override init() {
        super.init()
        container.wantsLayer = true
    }

    /// Opens SpaceXAI's sign-in page, once. Kept out of init: SwiftUI may build (and throw away)
    /// the view holding this controller several times, and each of those must stay cheap.
    func start() {
        guard webViews.isEmpty else { return }
        let configuration = WebViewFactory.makeConfiguration(dataStore: .default(), forTabs: false)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let main = WKWebView(frame: .zero, configuration: configuration)
        push(main)
        loadingObservation = main.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.isLoading = view.isLoading }
        }
        urlObservation = main.observe(\.url, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.urlChanged(view.url) }
        }
        main.load(URLRequest(url: GrokWebAccount.signInURL))
    }

    private func push(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        webViews.append(webView)
    }

    private func urlChanged(_ url: URL?) {
        guard let url, let host = url.host?.lowercased() else { return }
        if host.hasSuffix("x.ai") { visitedSignIn = true }
        let path = url.path.lowercased()
        if visitedSignIn, host == "grok.com" || host.hasSuffix(".grok.com"),
           !path.hasPrefix("/sign-in"), !path.hasPrefix("/sign-up") {
            landedOnGrok = true
            Task { await GrokWebAccount.shared.refresh() }
        }
    }

    func tearDown() {
        urlObservation = nil
        loadingObservation = nil
        for webView in webViews {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
        }
        webViews = []
    }

    /// Hosts the sign-in may pass through: SpaceXAI's and the sign-in providers'.
    nonisolated static func isAllowed(_ url: URL) -> Bool {
        if GrokWebPanel.isAllowed(url) { return true }
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        let more = ["accounts.youtube.com", "idmsa.apple.com", "appleid.cdn-apple.com"]
        return more.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if ["about", "blob", "data"].contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.allow)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame, !Self.isAllowed(url) {
            if url.scheme == "https" || url.scheme == "http" { openElsewhere?(url) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme?.hasPrefix("http") == true, !Self.isAllowed(url) {
            openElsewhere?(url)
            return nil
        }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        push(popup)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView !== webViews.first else { return }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        webViews.removeAll { $0 === webView }
    }
}
