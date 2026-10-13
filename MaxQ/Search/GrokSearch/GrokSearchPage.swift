//
//  GrokSearchPage.swift
//  Max Q
//
//  Max Q's results page, drawn natively over the tab's empty maxq:// page, out of SpaceXAI's
//  products. x.com's search tabs run across the top: All, Grokipedia, Posts on X. The three pages
//  sit side by side on one grid (a reading column and a column beside it) and slide under the tabs
//  in the direction of the tab chosen, each keeping its place, so moving between them shows the
//  path from one to the other (Benji Taylor's rule). Beside the tabs, each page's own control.
//
//    All: everything on the search in one place. Grok's answer as grok.com sets it, then the web
//         results with when each page changed, videos together, the way to Posts on X, and
//         beside it all the Grokipedia article.
//    Grokipedia: the whole article, in a reader, as grokipedia.com sets it.
//    Posts on X: x.com's own search page, as X serves it, across the page.
//

import AppKit
import SwiftUI

struct GrokSearchPage: View {
    @Bindable var browser: BrowserModel
    @Bindable var tab: BrowserTab
    let query: String
    /// The tab the page's address opens on ("!x" opens Posts on X).
    var opening: GrokSearchTab? = nil

    @State private var search: GrokSearch?
    @State private var keyboard = ResultsKeyboard()
    @State private var showsKeys = false
    @State private var lightbox = Lightbox()

    /// Two columns once the page has room for results and the column beside them.
    static let twoColumnWidth: CGFloat = 980
    static let mainWidth: CGFloat = 660
    static let sideWidth: CGFloat = 340
    static let gap: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= Self.twoColumnWidth
            ZStack(alignment: .top) {
                if let search {
                    SearchPages(browser: browser, search: search, wide: wide, width: proxy.size.width)
                        .id(search.id)
                        .transition(.opacity)
                }
                SearchTabBar(selection: selection, wide: wide, lastMore: search?.lastMore ?? .images) { search?.prepare($0) } accessory: {
                    if let search, wide {
                        TabAccessory(search: search)
                    }
                }
                if showsKeys {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture { toggleKeys() }
                        .transition(.opacity)
                    ResultsKeysSheet { toggleKeys() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.asymmetric(insertion: .pop(anchor: .center, scale: 0.96).combined(with: .blurFade(radius: 3)),
                                                removal: .opacity.combined(with: .scale(scale: 0.98))))
                }
                LightboxOverlay(lightbox: lightbox, size: proxy.size) { openFromResults($0, browser: browser) }
            }
            .coordinateSpace(.named(resultsPageSpace))
            .environment(\.lightbox, lightbox)
            .environment(\.collectionName, query)
        }
        .background(Theme.surface)
        .onAppear {
            keyboard.browser = browser
            keyboard.tab = tab
            keyboard.toggleKeys = { toggleKeys() }
            keyboard.keysShown = { showsKeys || lightbox.item != nil }
            keyboard.start()
        }
        .onDisappear { keyboard.stop() }
        .onChange(of: search?.id) { _, _ in keyboard.search = search }
        .task(id: "\(query)\u{0}\(opening?.rawValue ?? "")\u{0}\(tab.nativeSearchPage ?? "")") {
            let found = browser.searches.search(for: query, answering: !tab.nativeSearchIsRevisit, on: opening ?? .all,
                                                page: tab.nativeSearchPage)
            if let opening, found.tab != opening, !tab.nativeSearchIsRevisit {
                found.prepare(opening)
                found.tab = opening
            }
            search = found
            tab.markNativeSearchStarted()
        }
    }

    private func toggleKeys() {
        withAnimation(Motion.menu) { showsKeys.toggle() }
    }

    private var selection: Binding<GrokSearchTab> {
        Binding {
            search?.tab ?? .all
        } set: { newValue in
            search?.prepare(newValue)
            search?.tab = newValue
        }
    }
}

extension GrokSearch {
    /// Moves the page to `tab`, as clicking it in the tab bar does.
    func show(_ tab: GrokSearchTab) {
        prepare(tab)
        withAnimation(Motion.page) { self.tab = tab }
    }

    /// Opens the Grokipedia tab at one of the article's sections.
    func jumpToSection(_ id: String) {
        articleJump = ArticleJump(id: id, serial: (articleJump?.serial ?? 0) + 1)
        if tab != .grokipedia { show(.grokipedia) }
    }
}

/// The control beside the tabs, for the page on show: All's time filter, the Grokipedia article's
/// fact-check line, News's views. It changes with a quick blur as the page does. Posts on X has
/// none: x.com's own tabs are on its page.
private struct TabAccessory: View {
    let search: GrokSearch

    var body: some View {
        ZStack(alignment: .trailing) {
            switch search.tab {
            case .all:
                TimeFilterMenu(search: search)
                    .transition(.blurFade(radius: 3))
            case .grokipedia:
                if case .ready(let card) = search.pad {
                    FactCheckLine(card: card, size: 12, detailed: false)
                        .transition(.blurFade(radius: 3))
                }
            case .news:
                NewsAccessory(search: search)
                    .transition(.blurFade(radius: 3))
            case .x, .images, .videos:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(Motion.standard(0.2), value: search.tab)
    }
}

/// Opens a link from the results page: in this tab (Back returns to the results), or with ⌘ in a
/// new tab, as a page's own links do. A Grokipedia article opens in Max Q's own reader, unless
/// `natively` is false (the way to grokipedia.com itself).
@MainActor
func openFromResults(_ url: URL, browser: BrowserModel, natively: Bool = true) {
    if natively, let page = GrokipediaLinks.page(of: url) {
        let title = page.replacingOccurrences(of: "_", with: " ")
        openGrokipediaArticle(page, title: title.removingPercentEncoding ?? title, browser: browser)
        return
    }
    let flags = NSApp.currentEvent?.modifierFlags ?? []
    if flags.contains(.command) {
        browser.openInNewTab(url, select: flags.contains(.shift))
    } else if let partner = browser.splitPartner, browser.selectedTab?.nativeSearch != nil {
        // Results beside a page: a result opens in the other pane, and the results stay.
        partner.load(url)
        browser.select(partner)
    } else {
        browser.navigate(.url(url))
    }
}

// MARK: - Pages

/// The three pages side by side, the one chosen in view. Each keeps its own scroll position, and a
/// page is only built once its tab has been opened (or the pointer reached it).
private struct SearchPages: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let wide: Bool
    let width: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            page(.all) { AllPage(browser: browser, search: search, wide: wide) }
            page(.grokipedia) { GrokipediaPage(browser: browser, search: search, wide: wide) }
            page(.x) { XPostsPage(browser: browser, search: search, active: search.tab == .x) }
            moreSlot
        }
        .frame(width: width, alignment: .leading)
        .offset(x: -CGFloat(search.tab.index) * width)
        .clipped()
    }

    /// The fourth place in the strip, shared by Images, News and Videos: the one chosen, or the
    /// last one opened while another tab is on show. Moving between them crossfades.
    private var moreSlot: some View {
        let shown = search.tab.isMore ? search.tab : search.lastMore
        return ZStack {
            if search.visited.contains(shown) {
                Group {
                    switch shown {
                    case .images: ImagesPage(browser: browser, search: search, wide: wide)
                    case .videos: VideosPage(browser: browser, search: search, wide: wide)
                    default: NewsPage(browser: browser, search: search, wide: wide)
                    }
                }
                .id(shown)
                .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .animation(Motion.standard(0.2), value: shown)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .allowsHitTesting(search.tab.isMore)
        .accessibilityHidden(!search.tab.isMore)
    }

    private func page<Content: View>(_ tab: GrokSearchTab, @ViewBuilder content: () -> Content) -> some View {
        Group {
            if search.visited.contains(tab) {
                content()
            } else {
                Color.clear
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .allowsHitTesting(search.tab == tab)
        .accessibilityHidden(search.tab != tab)
    }
}

extension View {
    /// The page's columns (a reading column, and the column beside it on wide pages), centered:
    /// the same grid on every tab.
    func pageColumns(wide: Bool) -> some View {
        self
            .padding(.horizontal, wide ? 40 : 28)
            .padding(.top, 26)
            .padding(.bottom, 56)
            .frame(maxWidth: GrokSearchPage.mainWidth + (wide ? GrokSearchPage.gap + GrokSearchPage.sideWidth + 80 : 56))
            .frame(maxWidth: .infinity)
    }

    /// A page's scroll view, starting under the tab bar (which the page scrolls beneath).
    func pageScroll() -> some View {
        self
            .contentMargins(.top, searchTabBarHeight, for: .scrollContent)
            .contentMargins(.top, searchTabBarHeight, for: .scrollIndicators)
            .scrollEdgeFade()
    }
}

// MARK: - All

private struct AllPage: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let wide: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: GrokSearchPage.gap) {
                    VStack(alignment: .leading, spacing: 0) {
                        SinceLastVisit(items: search.sinceLastVisit, since: search.sinceDate, browser: browser)
                        QuickAnswerView(search: search)
                        GrokAnswerSection(browser: browser, search: search)
                        LaunchModule(browser: browser, search: search)
                        if !wide {
                            NarrowExtras(browser: browser, search: search)
                                .padding(.top, 26)
                        }
                        AllResults(browser: browser, search: search, wide: wide)
                            .padding(.top, 22)
                    }
                    .frame(maxWidth: GrokSearchPage.mainWidth, alignment: .leading)
                    if wide {
                        SideColumn(browser: browser, search: search)
                            .frame(width: GrokSearchPage.sideWidth)
                    }
                }
                .pageColumns(wide: wide)
            }
            .pageScroll()
            .onChange(of: search.picked[.all]) { _, index in
                let list = search.listResults
                guard let index, list.indices.contains(index) else { return }
                withAnimation(Motion.smooth) { proxy.scrollTo(list[index].id) }
            }
            .onChange(of: search.followUps.last?.id) { _, id in
                // A follow-up just asked: bring its question to the top of the page.
                guard let id else { return }
                withAnimation(Motion.page) { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }
}

// MARK: Results, with the modules among them

/// The web results, with the posts on X, the article's pictures and the videos spread among them,
/// as one list.
private struct AllResults: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let wide: Bool
    @Namespace private var pick

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !wide {
                HStack {
                    Spacer()
                    TimeFilterMenu(search: search)
                }
                .padding(.bottom, 4)
            }
            switch search.web {
            case .loading:
                ResultsSkeleton()
                    .transition(.opacity)
            case .failed(let message):
                failure(message)
            case .needsKey:
                SearchKeyPrompt(browser: browser, site: WebSearchClient.siteURL(for: search.query))
                if !search.related.isEmpty {
                    RelatedSearches(search: search) { browser.navigate(.search($0)) }
                        .padding(.top, 26)
                }
            case .ready:
                if search.results.isEmpty {
                    empty
                } else {
                    list
                    moreButton
                    if !search.related.isEmpty {
                        RelatedSearches(search: search) { browser.navigate(.search($0)) }
                            .padding(.top, 34)
                            .transition(.opacity)
                    }
                    SourceFootnote(text: "This search on DuckDuckGo", link: "Open there") {
                        if let url = WebSearchClient.siteURL(for: search.query) { openFromResults(url, browser: browser) }
                    }
                    .padding(.top, 28)
                    Text("Press ? for keyboard shortcuts")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textQuaternary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
            }
        }
        .animation(Motion.standard(0.25), value: search.web)
    }

    /// The pages Grok's answers cite, so their rows can say so.
    private var cited: Set<String> {
        Set((search.citations + search.followUps.flatMap(\.citations)).map(\.url.citationKey))
    }

    private var list: some View {
        let rows = search.listResults
        let fresh = Date().timeIntervalSince(search.resultsArrived) < 1.5
        let cited = cited
        // The modules spread through the list: posts after the third result, the article's
        // pictures after the fifth, videos after the seventh (or together at the end of a short list).
        let postsAfter = min(2, rows.count - 1)
        let imagesAfter = min(4, rows.count - 1)
        let videosAfter = min(6, rows.count - 1)
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, result in
                row(result, index: index, animated: fresh, cited: cited.contains(result.url.citationKey))
                    .id(result.id)
                if index == postsAfter {
                    PostsModule(browser: browser, search: search)
                }
                if index == imagesAfter {
                    ArticleImagesModule(search: search)
                }
                if index == videosAfter, !search.videoResults.isEmpty {
                    VideosModule(browser: browser, videos: search.videoResults)
                }
            }
        }
        .animation(Motion.smooth, value: search.picked[.all])
    }

    @ViewBuilder
    private func row(_ result: WebResult, index: Int, animated: Bool, cited: Bool) -> some View {
        let picked = search.picked[.all] == index
        if GrokipediaResultRow.isArticle(result.url) {
            GrokipediaResultRow(result: result, order: index % 10, animated: animated, picked: picked, pick: pick) {
                openGrokipediaResult(result.url, title: result.title, browser: browser)
            }
        } else {
            WebResultRow(result: result, order: index % 10, animated: animated, cited: cited,
                         label: SourceLabels.label(for: result.url, query: search.query, officialHosts: search.officialHosts),
                         picked: picked, pick: pick) {
                openFromResults($0, browser: browser)
            } newTab: {
                browser.openInNewTab($0, select: false)
            } besideResults: {
                browser.openBeside($0)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(search.time == .any ? String(localized: "No web results for “\(search.query)”.")
                                     : String(localized: "No web results for “\(search.query)” from the \(search.time.title.lowercased())."))
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            if search.time != .any {
                Button("Any time") { withAnimation(Motion.smooth) { search.setTime(.any) } }
                    .pill(.secondary, size: .small)
            }
        }
        .padding(.vertical, 20)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Button("Try again") { search.reload() }
                    .pill(.secondary, size: .small)
                if let url = WebSearchClient.siteURL(for: search.query) {
                    Button("Open on DuckDuckGo") { openFromResults(url, browser: browser) }
                        .pill(.ghost, size: .small)
                }
            }
        }
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var moreButton: some View {
        if search.canLoadMore || search.loadingMore {
            HStack {
                Spacer()
                Button {
                    search.loadMore()
                } label: {
                    HStack(spacing: 8) {
                        if search.loadingMore {
                            ShimmerText(text: String(localized: "Loading more"), font: .system(size: 14, weight: .medium))
                        } else {
                            Text(search.moreFailed ? "Try again" : "More results")
                        }
                        // The chevron gathers into three dots while the next page loads.
                        MorphIcon(search.loadingMore ? .dots : .chevronDown, size: 14, weight: 2.4)
                            .opacity(search.loadingMore ? 0.6 : 1)
                    }
                    .animation(Motion.spring(0.3), value: search.loadingMore)
                }
                .pill(.outline, size: .regular)
                .disabled(search.loadingMore)
                Spacer()
            }
            .padding(.top, 24)
        }
    }
}

/// One result, set like a row of Grokipedia's search list: the site's icon, name, address and
/// when the page changed, the title, two lines of the page with the words that matched in full
/// strength, a hairline under it. On hover the title steps back to grey, the chevron comes forward
/// 2 points and a button to read it beside the results appears. Rows rise into place 60 ms apart.
private struct WebResultRow: View {
    let result: WebResult
    /// Position within its page of results, for the staggered entrance.
    let order: Int
    /// Rise into place (results that just arrived), or simply be there (coming back to the page).
    let animated: Bool
    /// Grok's answer cites this page.
    var cited = false
    /// What kind of primary source the page is, if it's one.
    var label: SourceLabel? = nil
    /// The row J and K are on: a veil that glides from row to row.
    var picked = false
    var pick: Namespace.ID? = nil
    let open: (URL) -> Void
    let newTab: (URL) -> Void
    var besideResults: (URL) -> Void = { _ in }

    @State private var hovering = false
    @Environment(\.collectionName) private var collectionName

    var body: some View {
        Button { open(result.url) } label: {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SiteLine(result: result, cited: cited, label: label)
                        .padding(.bottom, 2)
                    Text(result.title)
                        .font(.system(size: 18, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !result.snippet.isEmpty {
                        Text(snippet)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(5)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let still = result.thumbnail {
                    VideoStill(url: still, hovering: hovering)
                }
                Icon(.chevronRight, size: 16)
                    .foregroundStyle(hovering || picked ? Theme.textPrimary : Theme.textQuaternary)
                    .offset(x: hovering || picked ? 2 : 0)
                    .frame(width: 18)
            }
            .padding(.vertical, 18)
            .background {
                if picked, let pick { PickVeil(namespace: pick) }
            }
            .rowHairline()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { besideResults(result.url) } label: { Icon(.splitView, size: 15) }
                    .iconButton(size: 28)
                    .tip("Open beside the results")
                    .accessibilityLabel("Open Beside the Results")
                    .padding(.top, 14)
                    .padding(.trailing, -6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.standard(0.17), value: hovering)
        .animation(Motion.standard(0.17), value: picked)
        .riseIn(order: order, animated: animated)
        .contextMenu {
            Button("Open Link in New Tab") { newTab(result.url) }
            Button("Open Beside the Results") { besideResults(result.url) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.url.absoluteString, forType: .string)
            }
            Divider()
            AddToCollectionMenu(item: {
                // The link and its title, like a bookmark: the search's own text and pictures
                // aren't kept (Brave's terms allow them only while they're shown).
                CollectionItem(kind: .result, title: result.title, url: result.url, source: result.host)
            }, suggestedName: collectionName.isEmpty ? result.host : collectionName)
        }
        .draggable(result.url)
        .accessibilityElement(children: .combine)
        .accessibilityHint(result.url.absoluteString)
    }

    private var snippet: AttributedString {
        var text = AttributedString()
        for run in result.snippet {
            var piece = AttributedString(run.text)
            if run.bold {
                piece.foregroundColor = Theme.textPrimary
                piece.font = .system(size: 14, weight: .medium)
            }
            text += piece
        }
        return text
    }
}

/// A result's site: its icon in a circle, its name, then the address and when the page changed.
private struct SiteLine: View {
    let result: WebResult
    var cited = false
    var label: SourceLabel? = nil

    var body: some View {
        HStack(spacing: 8) {
            ResultIcon(host: result.url.host ?? "", size: 16)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.hover))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Text(CitationLabel.siteName(result.url.host ?? result.host))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let label {
                        // The source itself: the subject's site, a government, a paper.
                        SourceChip(label: label)
                    }
                    if cited {
                        // The answer above leans on this page.
                        Text("Cited by Grok")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Capsule().fill(Theme.hover))
                            .overlay(Capsule().strokeBorder(Theme.chipBorder, lineWidth: 1))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                HStack(spacing: 5) {
                    Text(result.breadcrumb)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let date = result.date {
                        Text("·").foregroundStyle(Theme.textQuaternary)
                        Text(ResultDate.label(date, isDay: result.dateIsDay))
                            .fixedSize()
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// What kind of primary source a result is: a small mark and its name, explained on hover.
struct SourceChip: View {
    let label: SourceLabel

    var body: some View {
        HStack(spacing: 3) {
            Icon(label.icon, size: 11)
            Text(label.title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 6)
        .frame(height: 17)
        .background(Capsule().fill(Theme.hover))
        .overlay(Capsule().strokeBorder(Theme.chipBorder, lineWidth: 1))
        .fixedSize()
        .tip(verbatim: label.explanation)
    }
}

/// A Grokipedia article among the web results, set as Grokipedia sets its own list: the book, the
/// title in the serif. It opens natively, in the Grokipedia tab's reader.
private struct GrokipediaResultRow: View {
    let result: WebResult
    let order: Int
    let animated: Bool
    var picked = false
    var pick: Namespace.ID? = nil
    let open: () -> Void
    @State private var hovering = false

    static func isArticle(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), host == "grokipedia.com" || host.hasSuffix(".grokipedia.com") else { return false }
        return url.path.hasPrefix("/page/")
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Icon(.book, size: 15)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Theme.hover))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Grokipedia")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            HStack(spacing: 5) {
                                Text("Article")
                                if let date = result.date {
                                    Text("·").foregroundStyle(Theme.textQuaternary)
                                    Text(ResultDate.label(date, isDay: result.dateIsDay))
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.bottom, 2)
                    Text(GrokSearch.articleTitle(result.title))
                        .font(.serif(21, weight: .medium))
                        .tracking(-21 * 0.018)
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !result.snippet.isEmpty {
                        Text(result.plainSnippet)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(5)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chevronRight, size: 16)
                    .foregroundStyle(hovering || picked ? Theme.textPrimary : Theme.textQuaternary)
                    .offset(x: hovering || picked ? 2 : 0)
                    .frame(width: 18)
            }
            .padding(.vertical, 18)
            .background {
                if picked, let pick { PickVeil(namespace: pick) }
            }
            .rowHairline()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.standard(0.17), value: hovering)
        .riseIn(order: order, animated: animated)
        .accessibilityElement(children: .combine)
    }
}

/// A video's still at the end of its row, 16:9 with the corners of the page's cards and a play
/// mark that comes forward on hover.
private struct VideoStill: View {
    let url: URL
    let hovering: Bool
    var width: CGFloat = 128
    @State private var failed = false

    var body: some View {
        if !failed {
            FillImage(candidates: [url]) { failed = true }
                .frame(width: width, height: width * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                .overlay {
                    PlayMark()
                        .scaleEffect(hovering ? 1.08 : 1)
                        .opacity(hovering ? 1 : 0.85)
                }
                .animation(Motion.spring(0.3), value: hovering)
                .transition(.opacity)
        }
    }
}

/// A play mark: a soft dark disc with a rounded triangle.
private struct PlayMark: View {
    var size: CGFloat = 26

    var body: some View {
        Icon(.play, size: size * 0.5)
            .foregroundStyle(Color.white)
            .offset(x: size * 0.03)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.black.opacity(0.55)))
    }
}

// MARK: Posts on X, among the results

/// The way to Posts on X, on All among the results and at the end of the Grokipedia article: one
/// row that opens the tab, where x.com shows its own search.
struct PostsModule: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        if search.web != .loading {
            PostsDoor(query: search.query) { search.show(.x) }
                .padding(.vertical, 22)
                .rowHairline()
                .transition(.opacity)
        }
    }
}

/// The way to the Posts on X tab: one quiet row.
private struct PostsDoor: View {
    let query: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(.bubble, size: 17)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.hover))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Posts on X")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("What X is saying about “\(query)”")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Icon(.chevronRight, size: 16)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textQuaternary)
                    .offset(x: hovering ? 2 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

// MARK: Images

/// Pictures from the Grokipedia article on the search, with their captions: on-topic, and opened
/// in the photo viewer, which pages through them all.
private struct ArticleImagesModule: View {
    let search: GrokSearch

    private var figures: [(url: URL, caption: String, aspect: Double?)] {
        guard case .ready(let card) = search.pad, let article = card.article else { return [] }
        return article.blocks.compactMap { block in
            if case let .figure(_, image, caption, aspect) = block { (image, caption, aspect) } else { nil }
        }
    }

    var body: some View {
        let figures = figures
        if figures.count >= 3 {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader(title: "Images", detail: String(localized: "From Grokipedia"), more: "See the article") {
                    search.show(.grokipedia)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(figures.prefix(8).enumerated()), id: \.offset) { index, figure in
                            ImageTile(url: figure.url)
                                .opensInLightbox(figures.map(\.url), index: index, captions: figures.map(\.caption),
                                                 aspects: figures.map(\.aspect), referer: "https://grokipedia.com/")
                                .help(figure.caption)
                                .riseIn(order: index)
                        }
                    }
                }
                .rowEdgeFade()
            }
            .padding(.vertical, 22)
            .rowHairline()
            .transition(.opacity)
        }
    }
}

private struct ImageTile: View {
    let url: URL
    @State private var hovering = false
    @State private var failed = false

    var body: some View {
        if !failed {
            FillImage(candidates: [url], referer: "https://grokipedia.com/") { failed = true }
                .scaleEffect(hovering ? 1.04 : 1)
                .frame(width: 156, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                .onHover { hovering = $0 }
                .animation(Motion.spring(0.35), value: hovering)
        }
    }
}

// MARK: Videos

/// Videos among the results, side by side: stills at 16:9, the title, the channel's site and when.
private struct VideosModule: View {
    @Bindable var browser: BrowserModel
    let videos: [WebResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader(title: "Videos", detail: String(localized: "\(videos.count) videos"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        VideoCard(result: video) { openFromResults(video.url, browser: browser) }
                            .riseIn(order: index)
                    }
                }
            }
            .rowEdgeFade()
        }
        .padding(.vertical, 22)
        .rowHairline()
    }
}

private struct VideoCard: View {
    let result: WebResult
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.hover)
                    if let still = result.thumbnail {
                        FillImage(candidates: [still])
                            .scaleEffect(hovering ? 1.03 : 1)
                    }
                    PlayMark(size: 34)
                        .scaleEffect(hovering ? 1.08 : 1)
                }
                .frame(width: 206, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                Text(result.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 206, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    ResultIcon(host: result.url.host ?? "", size: 12)
                    Text(CitationLabel.siteName(result.url.host ?? result.host))
                    if let date = result.date {
                        Text("·").foregroundStyle(Theme.textQuaternary)
                        Text(ResultDate.label(date, isDay: result.dateIsDay))
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .frame(width: 206, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.3), value: hovering)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Related searches

/// Searches like this one, at the foot of the results, in two columns: the words the search
/// shares quiet, the new ones in full strength.
private struct RelatedSearches: View {
    let search: GrokSearch
    let run: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModuleHeader(title: "Related searches")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 8) {
                ForEach(search.related, id: \.self) { suggestion in
                    RelatedSearchChip(text: suggestion, query: search.query) { run(suggestion) }
                }
            }
        }
    }
}

private struct RelatedSearchChip: View {
    let text: String
    let query: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(.search, size: 14)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
                styled
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(hovering ? Theme.selected : Theme.hover))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }

    /// The words that were already in the search, quiet; the new ones in full strength.
    private var styled: Text {
        let known = Set(query.lowercased().split(separator: " ").map(String.init))
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var result = Text("")
        for (index, word) in words.enumerated() {
            let piece = index == 0 ? word : " " + word
            let isKnown = known.contains(word.lowercased())
            result = result + Text(piece)
                .foregroundStyle(isKnown ? Theme.textSecondary : Theme.textPrimary)
                .fontWeight(isKnown ? .regular : .medium)
        }
        return result
    }
}

/// A site's icon for a result: the one the search served with it, or one kept from a visit, so
/// opening a results page doesn't contact every site on it.
struct ResultIcon: View {
    let host: String
    var size: CGFloat = 16
    private var favicons: FaviconStore { FaviconStore.shared }

    var body: some View {
        Group {
            if let image = favicons.icon(for: host) {
                SiteIcon(image: image, tone: favicons.tone(for: host), size: size, cornerRadius: size * 0.22)
            } else {
                Icon(.globe, size: size)
                    .foregroundStyle(Theme.textQuaternary)
            }
        }
        .frame(width: size, height: size)
        .task(id: host) {
            // The icon the search served with the result (its own copy), kept only while Max Q is
            // open, or the one kept from a visit; no site is contacted just to draw its icon.
            let key = FaviconStore.key(for: host)
            guard !key.isEmpty, favicons.icon(for: key) == nil, let url = FaviconHints.url(for: key) else { return }
            favicons.loadIcon(host: key, candidates: [url], persist: false, siteFallback: false)
        }
    }
}

/// Site icons the search served with its results, by site, for ResultIcon.
@MainActor
enum FaviconHints {
    private static var byHost: [String: URL] = [:]

    static func note(_ results: [WebResult]) {
        for result in results {
            guard let favicon = result.favicon, let host = result.url.host else { continue }
            byHost[FaviconStore.key(for: host)] = favicon
        }
        if byHost.count > 2_000 { byHost.removeAll() }
    }

    static func url(for key: String) -> URL? { byHost[key] }
}

private struct ResultsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.hover).frame(width: 26, height: 26)
                        SkeletonBar(width: 0.22, height: 9, delay: Double(row) * 0.1)
                    }
                    SkeletonBar(width: 0.62, height: 14, delay: Double(row) * 0.1 + 0.05)
                    SkeletonBar(width: 0.9, height: 9, delay: Double(row) * 0.1 + 0.1)
                    SkeletonBar(width: 0.7, height: 9, delay: Double(row) * 0.1 + 0.15)
                }
                .padding(.vertical, 18)
                .rowHairline()
            }
        }
    }
}

// MARK: Beside the results

/// The column beside All: the Grokipedia article.
private struct SideColumn: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            GrokipediaSlot(browser: browser, search: search)
        }
        .animation(Motion.smooth, value: search.pad)
    }
}

/// Narrow pages put the Grokipedia article between the answer and the results.
private struct NarrowExtras: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        Group {
            if case .ready(let card) = search.pad {
                GrokipediaStrip(card: card) { search.show(.grokipedia) }
                    .transition(.card)
            } else if search.pad == .idle {
                GrokipediaChip(title: String(localized: "Look up on Grokipedia")) { search.show(.grokipedia) }
            }
        }
        .animation(Motion.smooth, value: search.pad)
    }
}

private struct GrokipediaSlot: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        switch search.pad {
        case .loading:
            GrokipediaCardSkeleton()
                .transition(.opacity)
        case .ready(let card):
            GrokipediaCardView(
                card: card,
                onOpen: { openFromResults($0, browser: browser) },
                onAskGrok: { title in browser.askGrok(String(localized: "Tell me about \(title).")) },
                onClose: { withAnimation(Motion.smooth) { search.dismissPad() } },
                onRead: { search.show(.grokipedia) },
                onSection: { search.jumpToSection($0) }
            )
            .id(card.articleURL)
            .transition(.card)
        case .idle:
            GrokipediaChip(title: String(localized: "Look up on Grokipedia")) { search.show(.grokipedia) }
                .transition(.pop(anchor: .topLeading))
        case .none:
            EmptyView()
        }
    }
}

/// Grokipedia in one row, for narrow pages: a small book, the title, two lines of the article.
/// It opens the Grokipedia tab.
private struct GrokipediaStrip: View {
    let card: GrokipediaCard
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 16) {
                GrokipediaBook(title: card.title, images: card.imageCandidates, width: 58, height: 84)
                    .frame(width: 70, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Icon(.book, size: 13)
                        Text("Grokipedia")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    Text(card.title)
                        .font(.serif(22, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.textPrimary)
                    Text(card.summary)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 16)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textQuaternary)
                    .offset(x: hovering ? 2 : 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).fill(hovering ? Theme.selected : Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}
