//
//  WebViewFactory.swift
//  Max Q
//
//  Builds the WKWebView configuration every tab and the grok.com panel share. One persistent
//  website data store, so signing in to x.com or grok.com in a tab also signs in the panel.
//

import WebKit

enum WebViewFactory {
    /// Tabs report as desktop Safari. WKWebView's default UA lacks the "Version/x Safari/x" token,
    /// which marks the client as an embedded app: some sign-in pages (Google, X) refuse those, and
    /// it's a fingerprinting signal. Safari's version tracks the OS major version since 26.
    nonisolated static var safariVersionToken: String {
        let major = max(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        return "Version/\(major).0 Safari/605.1.15"
    }

    nonisolated static var safariUserAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) \(safariVersionToken)"
    }

    /// `forTabs` adds what only tabs use: Max Q's own pages (the Grok search page) and the
    /// Grok Bot email suggestion in forms.
    static func makeConfiguration(dataStore: WKWebsiteDataStore = .default(), forTabs: Bool = true) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        if forTabs {
            configuration.setURLSchemeHandler(MaxQScheme.shared, forURLScheme: MaxQScheme.scheme)
            BotEmailAutofill.install(in: configuration)
            TrackerBlocker.shared.install(in: configuration)
            LinkPreviewScript.install(in: configuration)
            MediaScript.install(in: configuration)
        }
        PasskeyNotice.install(in: configuration)
        configuration.applicationNameForUserAgent = safariVersionToken
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsAirPlayForMediaPlayback = true

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences
        return configuration
    }

    static func makeWebView(configuration: WKWebViewConfiguration? = nil,
                            dataStore: WKWebsiteDataStore = .default()) -> MaxQWebView {
        let webView = MaxQWebView(frame: .zero, configuration: configuration ?? makeConfiguration(dataStore: dataStore))
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        return webView
    }
}
