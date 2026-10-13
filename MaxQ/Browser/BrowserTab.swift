//
//  BrowserTab.swift
//  Max Q
//
//  One tab: its web view (created lazily, so a new tab costs nothing until it loads a page),
//  the observable state the UI shows, and the WebKit delegates that route navigation, popups,
//  dialogs and permission prompts. Downloads are handled per window (DownloadCoordinator) so
//  they keep reporting after their tab closes.
//

import AppKit
import Observation
import WebKit

struct TabLoadError: Equatable {
    let title: String
    let message: String
    let url: URL?
}

enum TranslationStatus: Equatable {
    case idle
    case translating(done: Int, total: Int)
    case translated
}

@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id = UUID()

    var title: String = String(localized: "New Tab")
    var url: URL?
    var isLoading = false
    var progress: Double = 0
    var canGoBack = false
    var canGoForward = false
    /// True until the tab loads its first page: the tab shows the Max Q home page.
    private(set) var isHome = true
    /// The query shown, when the page is the user's search engine results page.
    var searchQuery: String?
    /// Where the current search runs (the web engine, Grokipedia's search or X's).
    var searchVertical: SearchVertical = .web
    /// Set when this is a pinned site's own tab (Grok, Grokipedia, X): it lives in its tile at
    /// the top of the sidebar rather than in the tab list.
    var pinned: Launcher?
    /// The query of the Grok search page this tab shows, drawn natively over its web view. Set as
    /// soon as Max Q opens the page, and from then on by what the web view commits, so the results
    /// stay up while a clicked result loads, and come back with Back.
    private(set) var nativeSearch: String?
    /// The results tab the page's address asks for ("!x" opens on Posts on X), if any.
    private(set) var nativeSearchTab: GrokSearchTab?
    /// The Grokipedia article a native search opens (a link from another article).
    private(set) var nativeSearchPage: String?
    /// One of Max Q's own other pages (research, a collection, Imagine), drawn over the tab's page.
    private(set) var nativePage: NativePage?
    /// The Grok page on screen was brought back (session restore, Back, Forward) rather than
    /// searched just now: it shows the results but doesn't ask Grok again on its own.
    @ObservationIgnored private(set) var nativeSearchIsRevisit = false
    var loadError: TabLoadError?
    var translation: TranslationStatus = .idle
    /// The trackers this page tried to load from other sites (by who runs them), for the shield.
    var trackers: [String] = []
    /// Set while the page is using the microphone or camera (shown in the sidebar).
    var isUsingMicrophone = false
    var isUsingCamera = false
    /// Bumped when the tab gets its web view, so the page host swaps it in.
    private(set) var webViewVersion = 0
    /// Changes on every committed main-frame navigation. Scripts that remember something about a
    /// page (a selection, translated text) tag it with this, and refuse to act on a different page.
    private(set) var pageToken = UUID().uuidString
    /// Bumped to scroll the new-tab page down to the news ("!news" on its own).
    var showNewsRequest = 0
    /// What the page is playing (sound, video), from its own media.
    var media = TabMedia()
    /// The tab group it's in, if any.
    var group: UUID?
    /// Reader, when it's on: the page's article set like a Grokipedia article.
    var reader: ReaderPhase?
    /// The page has an article Reader can set (checked after each load).
    var readerAvailable = false
    /// A picture of the page from when it was last on screen, for the sidebar's hover preview.
    /// Kept in memory only.
    var snapshot: NSImage?

    @ObservationIgnored private(set) var webView: MaxQWebView?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var controller: TabController?
    @ObservationIgnored weak var browser: BrowserModel?
    /// A restored tab keeps its URL here and only loads when first selected.
    @ObservationIgnored var pendingRestore: (url: URL, title: String)?
    /// The running page translation, cancelled whenever the page changes or the tab closes.
    @ObservationIgnored var translationTask: Task<Void, Never>?
    /// Recent web-content process crashes, to stop a crashing page from reloading forever.
    @ObservationIgnored private var crashTimes: [Date] = []
    /// Set when a background tab's page process ended; it reloads when the tab is next shown.
    @ObservationIgnored var reloadWhenShown = false
    /// The Max Q page (maxq://) this tab itself is about to open. Only Max Q opens those pages: a
    /// website navigating to one is refused.
    @ObservationIgnored var allowedNativeLoad: URL?
    /// Dialog flood protection, reset on every new page.
    @ObservationIgnored var dialogTimes: [Date] = []
    @ObservationIgnored var dialogsBlocked = false

    init(browser: BrowserModel?) {
        self.browser = browser
    }

    /// Tab created for a page that asked WebKit for a new window (target=_blank, window.open).
    /// WebKit requires the returned web view to use the configuration it provides.
    init(browser: BrowserModel?, configuration: WKWebViewConfiguration) {
        self.browser = browser
        makeWebView(configuration: configuration)
        isHome = false
    }

    convenience init(browser: BrowserModel?, restoring url: URL, title: String) {
        self.init(browser: browser)
        pendingRestore = (url, title)
        self.url = url
        self.title = title.isEmpty ? (url.host ?? String(localized: "Page")) : title
        isHome = false
    }

    var host: String? { url?.host }

    /// The count a site puts at the front of its title for what's new ("(3) Home / X").
    var unreadCount: String? { Self.unreadCount(in: title) }

    nonisolated static func unreadCount(in title: String) -> String? {
        guard title.hasPrefix("("), let close = title.firstIndex(of: ")") else { return nil }
        let inside = title[title.index(after: title.startIndex)..<close]
        let digits = inside.hasSuffix("+") ? inside.dropLast() : inside[...]
        guard !digits.isEmpty, digits.count <= 4, digits.allSatisfy(\.isNumber), digits != "0" else { return nil }
        return String(inside)
    }

    var displayTitle: String {
        if isHome { return String(localized: "New Tab") }
        if !title.isEmpty { return title }
        return url?.host ?? String(localized: "Loading")
    }

    /// The tab is the one on screen in its window.
    var isSelected: Bool { browser?.selectedTabID == id }

    /// Takes the hover-preview picture. Only works while the page is on screen.
    func captureSnapshot() {
        guard !isHome, loadError == nil, let webView, webView.window != nil, webView.bounds.width > 0 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        Task { [weak self, weak webView] in
            guard let webView, let image = try? await webView.takeSnapshot(configuration: configuration) else { return }
            self?.snapshot = image
        }
    }

    // MARK: - Navigation

    func load(_ url: URL) {
        pendingRestore = nil
        cancelTranslation()
        let webView = webView ?? makeWebView(configuration: nil)
        isHome = false
        loadError = nil
        self.url = url
        nativeSearchIsRevisit = false
        if let query = MaxQScheme.query(from: url) {
            allowedNativeLoad = url
            nativeSearch = query
            nativeSearchTab = MaxQScheme.tab(from: url)
            nativeSearchPage = MaxQScheme.page(from: url)
        }
        if let page = MaxQScheme.nativePage(from: url) {
            allowedNativeLoad = url
            nativePage = page
            nativeSearch = nil
        }
        if url.isFileURL {
            // A sandboxed app may read only the file the user opened, so grant exactly that file
            // (not its folder, which the sandbox would refuse).
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    /// Loads a restored tab's page the first time the tab is shown (or a crashed page again).
    func restoreIfNeeded() {
        if let pending = pendingRestore {
            pendingRestore = nil
            load(pending.url)
            nativeSearchIsRevisit = true
        } else if reloadWhenShown {
            reloadWhenShown = false
            webView?.reload()
        }
    }

    func goBack() {
        nativeSearchIsRevisit = true
        webView?.goBack()
    }

    func goForward() {
        nativeSearchIsRevisit = true
        webView?.goForward()
    }

    /// History moves that didn't come through goBack/goForward (swipes, the page's own history.back).
    fileprivate func willTraverseHistory() {
        nativeSearchIsRevisit = true
    }

    /// The Grok page has started its search: if it has to be rebuilt later (the window's cache let
    /// it go), it shows the results without asking Grok, and paying, a second time.
    func markNativeSearchStarted() {
        nativeSearchIsRevisit = true
    }

    func reload() {
        loadError = nil
        // Grok's results page searches again rather than reloading its empty page.
        // Only while the web view is still on that page: a result being opened or a failed load
        // reloads as itself.
        if pendingRestore == nil, let query = nativeSearch, MaxQScheme.isNative(webView?.url),
           let search = browser?.searches.existing(for: query, page: nativeSearchPage) {
            search.reload()
            return
        }
        if let pending = pendingRestore {
            pendingRestore = nil
            load(pending.url)
        } else if webView?.url == nil, let url {
            load(url)
        } else {
            webView?.reload()
        }
    }

    /// "Try Again" on the error view: retry the address that failed, not whatever page the web
    /// view fell back to.
    func retry() {
        if let failed = loadError?.url, failed != webView?.url {
            load(failed)
        } else {
            reload()
        }
    }

    func stopLoading() { webView?.stopLoading() }

    func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        if case .translating = translation { translation = .idle }
    }

    /// Releases the web view (and with it the page's process work, media and memory).
    func tearDown() {
        cancelTranslation()
        observations.forEach { $0.invalidate() }
        observations = []
        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.menuHandler = nil
            webView.loadHTMLString("", baseURL: nil)
            webView.removeFromSuperview()
        }
        webView = nil
        controller = nil
    }

    // MARK: - Web view lifecycle

    @discardableResult
    private func makeWebView(configuration: WKWebViewConfiguration?) -> MaxQWebView {
        let webView = WebViewFactory.makeWebView(configuration: configuration,
                                                 dataStore: browser?.websiteDataStore ?? .default())
        let controller = TabController(tab: self)
        webView.navigationDelegate = controller
        webView.uiDelegate = controller
        webView.menuHandler = controller
        webView.tab = self
        self.controller = controller
        self.webView = webView
        observe(webView)
        webViewVersion += 1
        return webView
    }

    private func observe(_ webView: WKWebView) {
        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.titleChanged(view.title ?? "") }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.urlChanged(view.url) }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.progress = view.estimatedProgress }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.microphoneCaptureState, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isUsingMicrophone = view.microphoneCaptureState == .active }
            },
            webView.observe(\.cameraCaptureState, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isUsingCamera = view.cameraCaptureState == .active }
            },
        ]
    }

    private func titleChanged(_ newTitle: String) {
        title = newTitle
        if let url, !newTitle.isEmpty, !(browser?.isPrivate ?? false) {
            HistoryStore.shared.updateTitle(url: url, title: newTitle)
        }
    }

    private func urlChanged(_ newURL: URL?) {
        guard let newURL else { return }
        url = newURL
        refreshSearchQuery()
        browser?.tabURLDidChange(self)
    }

    /// A new page committed in the main frame: anything tied to the previous page is now stale.
    fileprivate func didCommitPage() {
        nativeSearch = MaxQScheme.query(from: webView?.url)
        nativeSearchTab = MaxQScheme.tab(from: webView?.url)
        nativeSearchPage = MaxQScheme.page(from: webView?.url)
        nativePage = MaxQScheme.nativePage(from: webView?.url)
        trackers = []
        pageToken = UUID().uuidString
        dialogTimes = []
        dialogsBlocked = false
        cancelTranslation()
        translation = .idle
        reader = nil
        readerAvailable = false
        media = TabMedia()
    }

    func refreshSearchQuery() {
        guard let url else { searchQuery = nil; return }
        let engine = AppSettings.shared.searchEngine
        if let query = MaxQScheme.query(from: url) {
            // Max Q's own Grok page, whichever engine is now the default.
            searchQuery = query
            searchVertical = .web
        } else if let query = engine.query(fromResultsURL: url) {
            searchQuery = query
            searchVertical = .web
        } else if let match = SearchVertical.detect(url) {
            searchQuery = match.query
            searchVertical = match.vertical
        } else if searchQuery != nil, searchVertical == .web,
                  let results = engine.searchURL(for: "q"),
                  url.host == results.host, url.path == results.path {
            // The results page in a shape we can't read the query from (after a redirect): keep it.
        } else {
            // Any other page, even on the engine's own site, shows its address.
            searchQuery = nil
        }
    }

    fileprivate func didFinishNavigation() {
        loadError = nil
        guard let webView, let url = webView.url else { return }
        let isPrivate = browser?.isPrivate ?? false
        if !isPrivate {
            HistoryStore.shared.recordVisit(url: url, title: webView.title ?? "")
        }
        if let host = url.host, FaviconStore.shared.icon(for: host) == nil {
            Task { [weak webView] in
                guard let webView else { return }
                let links = await PageScripts.run(PageScripts.iconLinks, in: webView) as? [[String: Any]] ?? []
                // Private windows keep icons in memory only: nothing about the visit reaches disk.
                FaviconStore.shared.loadIcon(host: host, candidates: FaviconStore.iconLinks(declared: links),
                                             persist: !isPrivate)
            }
        }
        browser?.tabDidFinishLoading(self)
        // What the page says, kept on this Mac for ⌘K (when that's on), once it has settled.
        if !isPrivate, AppSettings.shared.rememberPages, !PageMemory.isExcluded(url) {
            let token = pageToken
            Task { [weak self, weak webView] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, let webView, self.pageToken == token else { return }
                let hasPassword = await PageScripts.run("return !!document.querySelector('input[type=password]');", in: webView) as? Bool ?? true
                guard !hasPassword else { return }
                let result = await PageScripts.run(PageScripts.visibleText, arguments: ["max": 8_000], in: webView) as? [String: Any]
                guard self.pageToken == token, let text = result?["text"] as? String else { return }
                PageMemory.shared.remember(url: url, title: self.title, text: text)
            }
        }
        // Whether Reader has an article to set here.
        if url.scheme == "https" || url.scheme == "http" {
            let token = pageToken
            Task { [weak self, weak webView] in
                guard let webView else { return }
                let readable = await PageScripts.run(ReaderScripts.readerable, in: webView) as? Bool ?? false
                guard let self, self.pageToken == token else { return }
                self.readerAvailable = readable
            }
        }
    }

    fileprivate func didFail(_ error: Error, url failingURL: URL?) {
        let ns = error as NSError
        // Cancelled loads (a new navigation replaced this one) and policy interruptions (downloads,
        // links opened elsewhere) are not failures.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 204) { return }
        let target = failingURL ?? (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? url
        let message: String
        switch ns.code {
        case NSURLErrorNotConnectedToInternet: message = String(localized: "Your Mac isn't connected to the internet.")
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            let host = target?.host ?? String(localized: "this page")
            message = String(localized: "The server for \(host) can't be found.")
        case NSURLErrorTimedOut: message = String(localized: "The server took too long to respond.")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid,
             NSURLErrorServerCertificateHasUnknownRoot:
            let host = target?.host ?? String(localized: "this site")
            message = String(localized: "A secure connection to \(host) couldn't be made, so Max Q didn't load it.")
        default: message = ns.localizedDescription
        }
        loadError = TabLoadError(title: String(localized: "Can't open this page"), message: message, url: target)
    }

    /// The page's process ended (crash or memory limit). Reload once or twice, then stop: a page
    /// that keeps crashing gets an error view instead of a reload loop.
    fileprivate func contentProcessDidTerminate() {
        let now = Date()
        crashTimes = crashTimes.filter { now.timeIntervalSince($0) < 60 } + [now]
        if crashTimes.count > 2 {
            loadError = TabLoadError(title: String(localized: "This page keeps stopping"),
                                     message: String(localized: "The page stopped working several times in a row, so Max Q stopped reloading it."),
                                     url: url)
            return
        }
        if isSelected {
            webView?.reload()
        } else {
            reloadWhenShown = true
        }
    }

    /// Whether a page may show another dialog right now. More than 3 in 10 seconds blocks the rest
    /// for this page, so a dialog loop can't trap the user.
    fileprivate func allowDialog() -> Bool {
        guard !dialogsBlocked else { return false }
        let now = Date()
        dialogTimes = dialogTimes.filter { now.timeIntervalSince($0) < 10 } + [now]
        if dialogTimes.count > 3 {
            dialogsBlocked = true
            browser?.showToast(String(localized: "This page tried to show too many dialogs. Max Q blocked the rest."))
            return false
        }
        return true
    }
}

// MARK: - WebKit delegates

final class TabController: NSObject, WKNavigationDelegate, WKUIDelegate, PageMenuHandler {
    weak var tab: BrowserTab?

    init(tab: BrowserTab) {
        self.tab = tab
    }

    private var browser: BrowserModel? { tab?.browser }

    // MARK: Navigation policy

    private static let webSchemes: Set<String> = ["http", "https", "about", "blob", "data", "file"]

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow); return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

        if navigationAction.navigationType == .backForward, isMainFrame {
            tab?.willTraverseHistory()
        }

        if scheme == MaxQScheme.scheme {
            // Max Q's own pages: only when Max Q opened them (or the user goes back or forward to
            // one, or reloads it), never because a website asked.
            let ours = isMainFrame && (tab?.allowedNativeLoad == url
                || navigationAction.navigationType == .backForward || navigationAction.navigationType == .reload)
            if tab?.allowedNativeLoad == url { tab?.allowedNativeLoad = nil }
            decisionHandler(ours ? .allow : .cancel)
            return
        }

        if !Self.webSchemes.contains(scheme) {
            // Another app's link: only for a real click, in the main frame, on the tab on screen.
            // Script redirects, timers and background tabs can't launch apps.
            if isMainFrame, navigationAction.navigationType == .linkActivated, tab?.isSelected == true {
                browser?.openExternally(url, fromSite: tab?.host)
            }
            decisionHandler(.cancel)
            return
        }

        // Command-click or middle-click (button mask 4 on macOS) opens a new tab.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 4 {
            browser?.openInNewTab(url, select: navigationAction.modifierFlags.contains(.shift))
            decisionHandler(.cancel)
            return
        }

        if navigationAction.shouldPerformDownload {
            // A download link the user clicked, or one in the main frame (pinned tabs included).
            decisionHandler(isMainFrame || navigationAction.navigationType == .linkActivated ? .download : .cancel)
            return
        }

        // A pinned site stays on its site: a web link to anywhere else opens in a tab of its own.
        if isMainFrame, navigationAction.navigationType == .linkActivated, url.host != nil,
           scheme == "http" || scheme == "https", let launcher = tab?.pinned, !launcher.keepsInPinnedTab(url) {
            browser?.openInNewTab(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let attachment = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased().hasPrefix("attachment") ?? false
        if !navigationResponse.canShowMIMEType || attachment {
            // Files only download from the main frame; an invisible frame can't drop files in Downloads.
            decisionHandler(navigationResponse.isForMainFrame ? .download : .cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        browser?.downloads.track(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        browser?.downloads.track(download)
    }

    // MARK: Navigation lifecycle

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab?.loadError = nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        BotEmailAutofill.shared.pageChanged(in: webView)
        tab?.didCommitPage()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab?.didFinishNavigation()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tab?.didFail(error, url: webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        tab?.didFail(error, url: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.browser.error("Web content process ended")
        tab?.contentProcessDidTerminate()
    }

    // MARK: Windows

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let browser else { return nil }
        let background = navigationAction.modifierFlags.contains(.command)
        return browser.openPopupTab(configuration: configuration, select: !background)
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let tab else { return }
        browser?.closeTab(tab)
    }

    // MARK: Dialogs
    //
    // Never app-modal: dialogs are sheets on the tab's own window. A tab that isn't on screen gets
    // an immediate answer instead (alert dismissed, confirm declined, prompt cancelled), so a
    // background page can never block the app.

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        guard let window = webView.window, tab?.allowDialog() == true else { completionHandler(); return }
        let alert = makeAlert(title: String(localized: "\(Self.siteName(frame)) says"), message: message)
        alert.addButton(withTitle: String(localized: "OK"))
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        guard let window = webView.window, tab?.allowDialog() == true else { completionHandler(false); return }
        let alert = makeAlert(title: String(localized: "\(Self.siteName(frame)) says"), message: message)
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        guard let window = webView.window, tab?.allowDialog() == true else { completionHandler(nil); return }
        let alert = makeAlert(title: String(localized: "\(Self.siteName(frame)) asks"), message: prompt)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    private func makeAlert(title: String, message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(message.prefix(2000))
        return alert
    }

    private static func siteName(_ frame: WKFrameInfo) -> String {
        let host = frame.securityOrigin.host
        return host.isEmpty ? String(localized: "This page") : host
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        guard let window = webView.window else { completionHandler(nil); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        // WebKit shows its own per-site prompt; the site never gets the camera or mic silently.
        decisionHandler(.prompt)
    }

    // MARK: Page context menu

    var searchEngineName: String { AppSettings.shared.searchEngine.name }
    var botEmailAvailable: Bool { AppSettings.shared.botEmailIsValid }
    var collections: [(id: UUID, name: String)] { CollectionStore.shared.collections.map { ($0.id, $0.name) } }

    func webView(_ webView: MaxQWebView, perform action: PageMenuAction) {
        guard let tab, let browser else { return }
        browser.handlePageMenu(action, in: tab, webView: webView)
    }
}

// MARK: - Downloads

/// Owns every download in a window. WKDownload holds its delegate weakly, so this lives as long
/// as the window (not the tab): a download keeps reporting after the tab that started it closes.
@MainActor
final class DownloadCoordinator: NSObject, WKDownloadDelegate {
    weak var browser: BrowserModel?
    private var destinations: [ObjectIdentifier: URL] = [:]
    private var active: [ObjectIdentifier: WKDownload] = [:]

    func track(_ download: WKDownload) {
        download.delegate = self
        active[ObjectIdentifier(download)] = download
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor (URL?) -> Void) {
        let destination = Downloads.uniqueDestination(for: suggestedFilename)
        destinations[ObjectIdentifier(download)] = destination
        browser?.showToast(String(localized: "Downloading \(destination.lastPathComponent)…"))
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        active[key] = nil
        guard let destination = destinations.removeValue(forKey: key) else { return }
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"),
                                                     object: destination.resolvingSymlinksInPath().path)
        browser?.showToast(String(localized: "Downloaded \(destination.lastPathComponent)"), actionTitle: String(localized: "Show in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        active[key] = nil
        let name = destinations.removeValue(forKey: key)?.lastPathComponent
        if (error as NSError).code == NSURLErrorCancelled { return }
        let reason = error.localizedDescription
        browser?.showToast(name.map { String(localized: "\($0) didn't finish: \(reason)") }
                           ?? String(localized: "The download didn't finish: \(reason)"))
    }
}

enum Downloads {
    static var folder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// "report.pdf" → "report 2.pdf" if needed, so a download never overwrites a file.
    static func uniqueDestination(for suggestedName: String) -> URL {
        let cleaned = suggestedName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleaned.isEmpty ? String(localized: "Download") : cleaned
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            index += 1
        }
        return candidate
    }
}
