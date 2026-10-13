//
//  GrokWebPanel.swift
//  Max Q
//
//  grok.com in the side panel, signed in with the user's own account (the same website data as
//  their tabs). Free for anyone with a Grok account, no API key needed. It's a plain web view:
//  Max Q doesn't script or automate grok.com, it only opens it, optionally with a question.
//

import AppKit
import SwiftUI
import WebKit

@MainActor
final class GrokWebPanel: NSObject, WKNavigationDelegate, WKUIDelegate {
    nonisolated static let home = URL(string: "https://grok.com")!

    /// Hosts the panel may navigate within (grok.com plus the sign-in flows it uses).
    nonisolated static let allowedHosts = [
        "grok.com", "x.ai", "accounts.x.ai", "x.com", "twitter.com", "api.x.com",
        "accounts.google.com", "appleid.apple.com", "challenges.cloudflare.com",
    ]

    private let dataStore: WKWebsiteDataStore
    private(set) lazy var webView: WKWebView = makeWebView()
    /// Holds grok.com and, over it, any sign-in window it opens (Google, Apple, X), so those
    /// sign-ins keep their link back to the page that opened them.
    private(set) lazy var container: NSView = {
        let view = NSView()
        view.wantsLayer = true
        pin(webView, in: view)
        return view
    }()
    private var popups: [WKWebView] = []
    private var closeButton: NSView?
    /// Called for links that should leave the panel and open as a normal tab.
    var openInTab: ((URL) -> Void)?
    private var loaded = false

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
    }

    private func makeWebView() -> WKWebView {
        let configuration = WebViewFactory.makeConfiguration(dataStore: dataStore, forTabs: false)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        webView.load(URLRequest(url: Self.home))
    }

    /// Opens grok.com with the question filled in, the same link grok.com uses for searches.
    func ask(_ question: String) {
        loaded = true
        var components = URLComponents(url: Self.home, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: String(question.prefix(1500)))]
        webView.load(URLRequest(url: components.url ?? Self.home))
    }

    /// SpaceXAI's sign-in page, returning to grok.com.
    func goToSignIn() {
        loaded = true
        webView.load(URLRequest(url: GrokWebAccount.signInURL))
    }

    func goHome() {
        loaded = true
        webView.load(URLRequest(url: Self.home))
    }

    nonisolated static func isAllowed(_ url: URL) -> Bool {
        if url.absoluteString == "about:blank" { return true }
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        // The panel has no address bar, so it only ever shows grok.com and its sign-in pages.
        // Anything else (a clicked link, a redirect, a script navigation) opens as a normal tab.
        if ["about", "blob", "data"].contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.allow)
            return
        }
        if isMainFrame, !GrokSignInController.isAllowed(url) {
            if url.scheme == "https" || url.scheme == "http" { openInTab?(url) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func pin(_ child: NSView, in parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let blank = url.absoluteString.isEmpty || url.absoluteString == "about:blank"
        if blank || Self.isSignInWindow(url) {
            // A sign-in window (Google, Apple, X): over the panel, closing itself when done, with
            // a Close button in case it doesn't.
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            pin(popup, in: container)
            popups.append(popup)
            showCloseButton()
            return popup
        }
        if let host = url.host?.lowercased(), url.scheme == "https", host == "grok.com" || host.hasSuffix(".grok.com") {
            webView.load(URLRequest(url: url))
        } else if url.scheme == "https" || url.scheme == "http" {
            // Anything else grok.com opens (a cited post, a source) is a tab of its own. Never
            // another scheme: a page can't open Max Q's own pages this way.
            openInTab?(url)
        }
        return nil
    }

    /// The pages sign-in windows show: the identity providers', never a site at large.
    nonisolated static func isSignInWindow(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        let providers = ["accounts.google.com", "accounts.youtube.com", "appleid.apple.com", "idmsa.apple.com",
                         "appleid.cdn-apple.com", "accounts.x.ai", "api.x.com", "api.twitter.com"]
        if providers.contains(host) { return true }
        if ["x.com", "twitter.com"].contains(host) {
            let path = url.path.lowercased()
            return path.hasPrefix("/i/oauth2") || path.hasPrefix("/oauth") || path.hasPrefix("/i/flow/login")
        }
        return false
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let index = popups.firstIndex(where: { $0 === webView }) else { return }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        popups.remove(at: index)
        if popups.isEmpty {
            closeButton?.removeFromSuperview()
            closeButton = nil
        }
    }

    /// Closes the sign-in window on top.
    func closeTopPopup() {
        if let popup = popups.last { webViewDidClose(popup) }
    }

    private func showCloseButton() {
        let button = closeButton ?? NSHostingView(rootView: PopupCloseButton { [weak self] in self?.closeTopPopup() })
        button.removeFromSuperview()
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
        ])
        closeButton = button
    }
}

/// Over a sign-in window in the panel: closes it.
private struct PopupCloseButton: View {
    let close: () -> Void

    var body: some View {
        Button(action: close) {
            HStack(spacing: 5) {
                Icon(.close, size: 12)
                Text("Close")
            }
        }
        .pill(.secondary, size: .mini)
        .elevation(.menu)
        .fixedSize()
        .accessibilityLabel("Close sign-in window")
    }
}
