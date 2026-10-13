//
//  GrokipediaReader.swift
//  Max Q
//
//  The Grokipedia tab: the whole article, set natively the way grokipedia.com sets it. The title
//  in the book serif, "Fact-checked by Grok" with when, the text at Grokipedia's reading size and
//  measure, section headings in the serif with a hairline under the larger ones, figures with
//  their captions (they open in the photo viewer), tables, lists, and the numbered sources at the
//  end. Citation numbers open their source in a small card; links to other articles open those
//  articles here, natively, with Back to return. Beside the text, Grokipedia's infobox and the
//  contents, which stay in view as you read and mark the section you're in with a bar that glides
//  from one to the next. Then more articles on the search.
//

import AppKit
import SwiftUI

/// The Grokipedia tab.
struct GrokipediaPage: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let wide: Bool

    var body: some View {
        Group {
            switch search.pad {
            case .ready(let card):
                if let article = card.article {
                    GrokipediaReader(browser: browser, search: search, card: card, article: article, wide: wide)
                        .id(card.articleURL)
                } else {
                    page { ArticleOpening(browser: browser, search: search, card: card, wide: wide, fullArticle: false) }
                }
            case .loading:
                page { GrokipediaArticleSkeleton(wide: wide) }
            default:
                page { EmptyView() }
            }
        }
        .transition(.blurFade())
        .animation(Motion.smooth, value: search.pad)
    }

    /// The page without a whole article: what there is, then more articles.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                content()
                GrokipediaList(browser: browser, search: search)
                    .padding(.top, search.pad == .none ? 0 : 44)
            }
            .frame(maxWidth: GrokSearchPage.mainWidth + (wide ? GrokSearchPage.gap + GrokSearchPage.sideWidth : 0), alignment: .leading)
            .pageColumns(wide: wide)
        }
        .pageScroll()
        .animation(Motion.smooth, value: search.articles)
    }
}

// MARK: - Where the reader is

/// What the contents need to follow the reading: where the visible part of the page starts, where
/// each heading is, and how tall things are. Kept apart so scrolling only redraws the contents.
@MainActor
@Observable
final class ReaderTracker {
    var visibleTop: CGFloat = 0
    var viewportHeight: CGFloat = 600
    var contentHeight: CGFloat = 1
    var headingY: [String: CGFloat] = [:]
    var railTop: CGFloat = 0
    var railHeight: CGFloat = 0

    /// The heading the reader is under.
    func active(in outline: [GrokipediaHeading]) -> String? {
        var current: String?
        for heading in outline {
            guard let y = headingY[heading.id] else { continue }
            if y <= visibleTop + 140 { current = heading.id } else { break }
        }
        if let sources = headingY["sources"], sources <= visibleTop + 140 { return "sources" }
        return current
    }

    var progress: Double {
        let span = contentHeight - viewportHeight
        guard span > 1 else { return 1 }
        return min(max(Double(visibleTop / span), 0), 1)
    }

    /// How far the contents move down to stay in view, without running past the article.
    var railOffset: CGFloat {
        let wanted = visibleTop + 22 - railTop
        let limit = max(0, contentHeight - railTop - railHeight - 120)
        return min(max(wanted, 0), limit)
    }
}

private struct ScrollMetrics: Equatable {
    let top: CGFloat
    let height: CGFloat
    let content: CGFloat
}

/// The reader's own coordinate space: the article's top is 0, wherever it has scrolled to.
let readerSpace = "grokipediaReader"

// MARK: - The reader

struct GrokipediaReader: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let card: GrokipediaCard
    let article: GrokipediaArticle
    let wide: Bool

    @State private var tracker = ReaderTracker()
    @State private var allSources = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: GrokSearchPage.gap) {
                    VStack(alignment: .leading, spacing: 0) {
                        ArticleOpening(browser: browser, search: search, card: card, wide: wide, fullArticle: true)
                            .id("opening")
                        if !wide {
                            narrowAside
                        }
                        ArticleBody(browser: browser, article: article, tracker: tracker, articleURL: card.articleURL)
                        sources
                            .padding(.top, 40)
                        // What X is saying about it, as on All.
                        PostsModule(browser: browser, search: search)
                            .padding(.top, 24)
                        GrokipediaList(browser: browser, search: search)
                            .padding(.top, 36)
                        Text("From Grokipedia, linked back to the article. Some articles are licensed CC BY-SA 4.0.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textQuaternary)
                            .padding(.top, 20)
                    }
                    .frame(maxWidth: GrokSearchPage.mainWidth, alignment: .leading)
                    if wide {
                        VStack(alignment: .leading, spacing: 28) {
                            GrokipediaInfoboxCard(card: card, infobox: article.infobox, rows: 8)
                            VStack(alignment: .leading, spacing: 0) {
                                // Where the contents rest, measured apart from the offset that keeps
                                // them in view.
                                Color.clear.frame(height: 0)
                                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(readerSpace)).minY } action: {
                                        tracker.railTop = $0
                                    }
                                ContentsRail(outline: article.outline, hasSources: !article.references.isEmpty, tracker: tracker) { id in
                                    jump(to: id, proxy: proxy)
                                }
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tracker.railHeight = $0 }
                                .modifier(RailOffset(tracker: tracker))
                            }
                        }
                        .frame(width: GrokSearchPage.sideWidth)
                    }
                }
                .pageColumns(wide: wide)
                .coordinateSpace(.named(readerSpace))
            }
            .pageScroll()
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(top: geometry.contentOffset.y + geometry.contentInsets.top,
                              height: geometry.containerSize.height - geometry.contentInsets.top,
                              content: geometry.contentSize.height)
            } action: { _, metrics in
                tracker.visibleTop = metrics.top
                tracker.viewportHeight = metrics.height
                tracker.contentHeight = metrics.content
            }
            .overlay(alignment: .bottom) {
                // Questions about the article, answered from it.
                ArticleAskBar(context: askContext, browser: browser) { id in jump(to: id, proxy: proxy) }
                    .padding(.horizontal, 24)
            }
            .onChange(of: search.articleJump) { _, request in
                guard let request else { return }
                jump(to: request.id, proxy: proxy)
            }
            .onChange(of: search.sectionStep) { _, request in
                guard let request else { return }
                step(by: request.delta, proxy: proxy)
            }
            .onAppear {
                if let request = search.articleJump {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { jump(to: request.id, proxy: proxy) }
                }
            }
        }
        .environment(\.readerLink) { url, rect in handle(url, at: rect) }
        .environment(\.readerLinkHover) { url, rect in
            guard AppSettings.shared.linkPreviews else { return }
            LinkPreviewPresenter.shared.hover(url, at: rect, in: browser.window) { target in
                LinkPreviewPresenter.shared.hide()
                handle(url ?? target, at: rect)
            }
        }
        .onDisappear {
            LinkPreviewPresenter.shared.hide()
            if ArticleSpeaker.shared.isReading(card.articleURL) { ArticleSpeaker.shared.stop() }
        }
    }

    /// The article as Grok reads it for questions about it (built once per article).
    private var askContext: ArticleContext {
        ArticleContext.make(title: card.title, url: card.articleURL, article: article)
    }

    private func jump(to id: String, proxy: ScrollViewProxy) {
        withAnimation(Motion.page) {
            proxy.scrollTo(id == "sources" ? "sources" : "h-\(id)", anchor: .top)
        }
    }

    /// The next (or previous) heading from the one being read, then the sources.
    private func step(by delta: Int, proxy: ScrollViewProxy) {
        var stops = article.outline.map(\.id)
        if !article.references.isEmpty { stops.append("sources") }
        guard !stops.isEmpty else { return }
        let current = tracker.active(in: article.outline).flatMap { stops.firstIndex(of: $0) }
        let next = current.map { $0 + delta } ?? (delta > 0 ? 0 : -1)
        guard stops.indices.contains(next) else {
            if next < 0 { withAnimation(Motion.page) { proxy.scrollTo("opening", anchor: .top) } }
            return
        }
        jump(to: stops[next], proxy: proxy)
    }

    /// Narrow pages: the infobox under the opening, and the contents folded.
    private var narrowAside: some View {
        VStack(alignment: .leading, spacing: 18) {
            GrokipediaInfoboxCard(card: card, infobox: article.infobox, rows: 6)
                .frame(maxWidth: 440)
            if !article.outline.isEmpty {
                FoldedContents(outline: article.outline) { id in
                    search.jumpToSection(id)
                }
            }
        }
        .padding(.bottom, 26)
    }

    // MARK: Sources

    @ViewBuilder
    private var sources: some View {
        if !article.references.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sources")
                        .font(.serif(26, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(article.references.count == 1 ? "1 source" : "\(article.references.count) sources")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.bottom, 8)
                .rowHairline()
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(allSources ? article.references : Array(article.references.prefix(12))) { reference in
                        SourceReferenceRow(reference: reference) { url in openFromResults(url, browser: browser) }
                            .id("ref-\(reference.number)")
                    }
                }
                if article.references.count > 12 {
                    Button {
                        withAnimation(Motion.smooth) { allSources.toggle() }
                    } label: {
                        MorphLabel(text: allSources ? String(localized: "Fewer sources")
                                                    : String(localized: "All \(article.references.count) sources"),
                                   font: .system(size: 13.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 14)
                }
            }
            .id("sources")
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(readerSpace)).minY } action: { tracker.headingY["sources"] = $0 }
        }
    }

    // MARK: Links

    /// Links out of the article: another article opens here, natively; a citation shows its
    /// source; the web opens as any result does.
    private func handle(_ url: URL, at rect: NSRect) {
        switch url.scheme {
        case ArticleLinks.articleScheme:
            guard let (page, title) = ArticleLinks.article(from: url) else { return }
            openGrokipediaArticle(page, title: title, browser: browser)
        case ArticleLinks.citationScheme:
            guard let number = ArticleLinks.citation(from: url),
                  let reference = article.references.first(where: { $0.number == number }) else { return }
            showCitation(reference, at: rect)
        default:
            openFromResults(url, browser: browser)
        }
    }

    /// The source of a citation, in a card that grows out of the number that was clicked.
    private func showCitation(_ reference: GrokipediaReference, at rect: NSRect) {
        guard let window = browser.window else { return }
        var anchor = rect
        if anchor.isEmpty {
            let point = NSEvent.mouseLocation
            anchor = NSRect(x: point.x - 6, y: point.y - 8, width: 12, height: 16)
        }
        PopoverController.show(at: anchor, in: window, placement: .below(.center)) {
            CitationCard(reference: reference) { url in
                PopoverController.dismissActive()
                openFromResults(url, browser: browser)
            }
        }
    }
}

/// Keeps the contents in view while the article scrolls, reading only the tracker.
struct RailOffset: ViewModifier {
    let tracker: ReaderTracker

    func body(content: Content) -> some View {
        content.offset(y: tracker.railOffset)
    }
}

/// Opens a Grokipedia article natively: the results page for its title, on the Grokipedia tab,
/// with that very article. ⌘ opens it in a new tab.
@MainActor
func openGrokipediaArticle(_ page: String, title: String, browser: BrowserModel) {
    guard let url = MaxQScheme.searchURL(for: title, tab: .grokipedia, page: page) else { return }
    let flags = NSApp.currentEvent?.modifierFlags ?? []
    if flags.contains(.command) {
        browser.openInNewTab(url, select: flags.contains(.shift))
    } else {
        browser.selectedTab?.searchQuery = title
        browser.selectedTab?.load(url)
        browser.syncAddressText()
    }
}

/// The addresses a paragraph's links carry: another article, or a citation number.
nonisolated enum ArticleLinks {
    static let articleScheme = "maxq-grokipedia"
    static let citationScheme = "maxq-cite"

    static func article(_ page: String, title: String) -> URL? {
        var components = URLComponents()
        components.scheme = articleScheme
        components.host = "article"
        components.queryItems = [URLQueryItem(name: "page", value: page), URLQueryItem(name: "title", value: title)]
        return components.url
    }

    static func article(from url: URL) -> (page: String, title: String)? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let page = items.first(where: { $0.name == "page" })?.value, !page.isEmpty else { return nil }
        let title = items.first(where: { $0.name == "title" })?.value ?? page.replacingOccurrences(of: "_", with: " ")
        return (page, title)
    }

    static func citation(_ number: Int) -> URL? { URL(string: "\(citationScheme)://\(number)") }

    static func citation(from url: URL) -> Int? { url.host.flatMap(Int.init) }
}

// MARK: - The opening

/// The article's opening: where it's from, the title, when Grok fact-checked it, how long it
/// takes to read, the ways out, and (without the whole article) the lead.
private struct ArticleOpening: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let card: GrokipediaCard
    let wide: Bool
    /// The whole article follows; otherwise the lead and the infobox are all there is.
    let fullArticle: Bool
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Icon(.book, size: 15)
                Text("Grokipedia")
                if let kind = card.kind {
                    Text(kind.label)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .reveal(revealed)

            Text(card.title)
                .font(.serif(wide ? 40 : 34, weight: .medium))
                .tracking(-(wide ? 40 : 34) * 0.018)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, 12)
                .reveal(revealed, delay: 0.05)

            FactCheckLine(card: card)
                .padding(.top, 10)
                .reveal(revealed, delay: 0.09)

            actions
                .padding(.top, 18)
                .reveal(revealed, delay: 0.12)

            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .reveal(revealed, delay: 0.14)

            if !fullArticle {
                HStack(alignment: .top, spacing: 32) {
                    Text(card.summary)
                        .font(.system(size: 15.5))
                        .lineSpacing(9)
                        .foregroundStyle(Theme.textReading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: GrokSearchPage.mainWidth, alignment: .leading)
                    if wide {
                        GrokipediaInfoboxCard(card: card, infobox: nil, rows: 10)
                            .frame(width: GrokSearchPage.sideWidth)
                    }
                }
                .reveal(revealed, delay: 0.17)
            }
        }
        .onAppear { revealed = true }
    }

    private var speaker: ArticleSpeaker { ArticleSpeaker.shared }
    private var reading: Bool { speaker.isReading(card.articleURL) }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                browser.askGrok(String(localized: "Tell me about \(card.title)."))
            } label: {
                HStack(spacing: 6) {
                    Icon(.bubble, size: 15)
                    Text("Ask Grok")
                }
            }
            .pill(.primary, size: .small)

            if fullArticle, let article = card.article {
                Button {
                    speaker.toggle(card, article: article)
                } label: {
                    HStack(spacing: 6) {
                        Icon(.speaker, size: 15)
                        MorphLabel(text: !reading ? String(localized: "Listen")
                                                  : (speaker.paused ? String(localized: "Resume") : String(localized: "Pause")),
                                   font: .system(size: 13, weight: .medium))
                    }
                }
                .pill(reading ? .secondary : .outline, size: .small)
                .tip("Read the article aloud with your Mac's voice")
                if reading {
                    Button { speaker.stop() } label: { Icon(.stop, size: 14) }
                        .iconButton(size: 32, outlined: true)
                        .tip("Stop reading")
                        .accessibilityLabel("Stop Reading")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }

            Button { browser.openBeside(card.articleURL) } label: { Icon(.splitView, size: 16) }
                .iconButton(size: 32, outlined: true)
                .tip("Read it on grokipedia.com beside the results")
                .accessibilityLabel("Read Beside the Results")

            Button { openFromResults(card.articleURL, browser: browser, natively: false) } label: {
                HStack(spacing: 5) {
                    Text("grokipedia.com")
                    Icon(.arrowUpRight, size: 13)
                }
            }
            .pill(.outline, size: .small)
            .tip("Open the article on grokipedia.com")

            if let site = card.officialSite, let host = card.officialSiteLabel {
                Button { openFromResults(site, browser: browser) } label: {
                    HStack(spacing: 5) {
                        Text(host).lineLimit(1)
                        Icon(.arrowUpRight, size: 13)
                    }
                }
                .pill(.ghost, size: .small)
                .tip("Official site")
            }
        }
        .animation(Motion.smooth, value: reading)
    }
}

/// Grokipedia's line under the title: "Fact-checked by Grok · 1 hour ago", then the reading time
/// and the number of sources.
struct FactCheckLine: View {
    let card: GrokipediaCard
    var size: CGFloat = 13
    /// With the reading time and the number of sources.
    var detailed = true

    var body: some View {
        HStack(spacing: 6) {
            Icon(.sealCheck, size: size + 2)
            Text(parts.joined(separator: " · "))
        }
        .font(.system(size: size))
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
    }

    private var parts: [String] {
        var parts: [String] = []
        if let updated = card.updated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append(String(localized: "Fact-checked by Grok · \(formatter.localizedString(for: updated, relativeTo: Date()))"))
        } else {
            parts.append(String(localized: "On Grokipedia"))
        }
        if detailed, let article = card.article {
            parts.append(String(localized: "\(article.readingMinutes) min read"))
            if !article.references.isEmpty {
                parts.append(article.references.count == 1 ? String(localized: "1 source") : String(localized: "\(article.references.count) sources"))
            }
        }
        return parts
    }
}

// MARK: - The body

/// The article's blocks, built as they come into view.
struct ArticleBody: View {
    @Bindable var browser: BrowserModel
    let article: GrokipediaArticle
    let tracker: ReaderTracker
    let articleURL: URL

    /// Every figure in the article, so the photo viewer pages through them all.
    private var gallery: ArticleGallery {
        var gallery = ArticleGallery()
        for block in article.blocks {
            if case let .figure(_, image, caption, aspect) = block {
                gallery.images.append(image)
                gallery.captions.append(caption)
                gallery.aspects.append(aspect)
            }
        }
        return gallery
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(article.blocks) { block in
                view(for: block)
                    .id(block.id)
            }
        }
    }

    @ViewBuilder
    private func view(for block: GrokipediaBlock) -> some View {
        switch block {
        case .heading(let heading):
            ArticleHeading(heading: heading, articleURL: articleURL)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(readerSpace)).minY } action: { y in
                    tracker.headingY[heading.id] = y
                }
        case .paragraph(_, let runs):
            ArticleParagraph(runs: runs)
                .padding(.bottom, 16)
        case let .figure(_, image, caption, aspect):
            ArticleFigure(image: image, caption: caption, aspect: aspect, gallery: gallery)
                .padding(.top, 6)
                .padding(.bottom, 22)
        case let .table(_, header, rows):
            ArticleTable(header: header, rows: rows)
                .padding(.top, 4)
                .padding(.bottom, 22)
        case let .list(_, ordered, items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, runs in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.system(size: 15.5).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .frame(minWidth: 14, alignment: .trailing)
                        ArticleParagraph(runs: runs)
                    }
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, 18)
        case .quote(_, let runs):
            HStack(alignment: .top, spacing: 14) {
                Rectangle().fill(Theme.borderStrong).frame(width: 2)
                ArticleParagraph(runs: runs, color: Theme.textSecondary)
            }
            .padding(.bottom, 18)
        }
    }
}

/// A section heading in the book serif; the larger ones with a hairline under them, as on
/// Grokipedia. On hover, as there, a link to the section to copy.
private struct ArticleHeading: View {
    let heading: GrokipediaHeading
    let articleURL: URL
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: copyLink) {
                    ZStack {
                        if copied { Icon(.check, size: 14).transition(.glyphSwap) } else { Icon(.link, size: 14).transition(.glyphSwap) }
                    }
                }
                .iconButton(size: 24)
                .tip(copied ? "Copied" : "Copy a link to this section")
                .accessibilityLabel("Copy a Link to This Section")
                .opacity(hovering || copied ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.bottom, heading.level == 2 ? 6 : (heading.level == 3 ? 8 : 6))
            if heading.level == 2 {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                    .padding(.bottom, 12)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.top, heading.level == 2 ? 26 : 14)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var title: some View {
        switch heading.level {
        case 2:
            Text(heading.text)
                .font(.serif(26, weight: .medium))
                .tracking(-0.35)
        case 3:
            Text(heading.text)
                .font(.serif(21, weight: .medium))
                .tracking(-0.25)
        default:
            Text(heading.text)
                .font(.system(size: 16.5, weight: .semibold))
        }
    }

    private func copyLink() {
        guard var components = URLComponents(url: articleURL, resolvingAgainstBaseURL: false) else { return }
        components.fragment = heading.id
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(components.url?.absoluteString ?? articleURL.absoluteString, forType: .string)
        withAnimation(Motion.spring(0.2)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(Motion.spring(0.2)) { copied = false } }
    }
}

/// A paragraph at Grokipedia's reading size and measure: links to other articles and to the web
/// in the link blue, citation numbers small and raised. Selectable, and steady when clicked.
struct ArticleParagraph: View {
    let runs: [GrokipediaRun]
    /// The text size; Reader's own when not given.
    var size: CGFloat? = nil
    var color: Color = Theme.textReading
    @Environment(\.readerLink) private var readerLink
    @Environment(\.readerLinkHover) private var readerLinkHover
    @Environment(\.readerTextSize) private var textSize
    /// Read so the text is set again in the other theme's colors.
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ReaderText(text: Self.attributed(runs, size: size ?? textSize, color: NSColor(color)), onHover: readerLinkHover) { url, rect in
            readerLink(url, rect)
        }
    }

    static func attributed(_ runs: [GrokipediaRun], size: CGFloat, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = size * 0.62
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let link = NSColor(Theme.link)
        let text = NSMutableAttributedString()
        for run in runs {
            switch run.kind {
            case .citation(let number):
                // A narrow no-break space keeps the number with its word.
                var attributes = base
                attributes[.font] = NSFont.systemFont(ofSize: size * 0.66, weight: .medium)
                attributes[.baselineOffset] = size * 0.38
                attributes[.foregroundColor] = NSColor(Theme.textTertiary)
                if let url = ArticleLinks.citation(number) { attributes[.link] = url }
                text.append(NSAttributedString(string: "\u{202F}\(number)", attributes: attributes))
            case .article(let page):
                var attributes = styled(run, base: base, size: size)
                attributes[.foregroundColor] = link
                if let url = ArticleLinks.article(page, title: run.text) { attributes[.link] = url }
                text.append(NSAttributedString(string: run.text, attributes: attributes))
            case .link(let url):
                var attributes = styled(run, base: base, size: size)
                attributes[.foregroundColor] = link
                attributes[.link] = url
                text.append(NSAttributedString(string: run.text, attributes: attributes))
            case .text:
                text.append(NSAttributedString(string: run.text, attributes: styled(run, base: base, size: size)))
            }
        }
        return text
    }

    private static func styled(_ run: GrokipediaRun, base: [NSAttributedString.Key: Any], size: CGFloat) -> [NSAttributedString.Key: Any] {
        guard run.bold || run.italic else { return base }
        var font = NSFont.systemFont(ofSize: size, weight: run.bold ? .semibold : .regular)
        if run.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        var attributes = base
        attributes[.font] = font
        return attributes
    }
}

extension EnvironmentValues {
    /// What a link in the reader's text does: where it goes, and where it is on screen.
    @Entry var readerLink: (URL, NSRect) -> Void = { _, _ in }
    /// The pointer resting on a link in the reader's text (a preview shows), or leaving it.
    @Entry var readerLinkHover: ((URL?, NSRect) -> Void)? = nil
}

/// A figure: the picture at its own shape, rounded with a hairline, its caption under it. It
/// opens in the photo viewer.
/// The article's figures together, for the photo viewer.
struct ArticleGallery {
    var images: [URL] = []
    var captions: [String] = []
    var aspects: [Double?] = []
}

private struct ArticleFigure: View {
    let image: URL
    let caption: String
    let aspect: Double?
    var gallery = ArticleGallery()
    @State private var failed = false

    private var shape: CGFloat { CGFloat(min(max(aspect ?? 1.5, 0.6), 2.4)) }

    var body: some View {
        if !failed {
            VStack(spacing: 9) {
                // No taller than 380 points: the width follows from the picture's shape, so the
                // frame hugs the picture.
                AspectBox(aspect: shape, maxHeight: 380) {
                    FillImage(candidates: [image], referer: "https://grokipedia.com/") { failed = true }
                }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    .opensInLightbox(gallery.images.isEmpty ? [image] : gallery.images,
                                     index: gallery.images.firstIndex(of: image) ?? 0,
                                     captions: gallery.images.isEmpty ? [caption] : gallery.captions,
                                     aspects: gallery.images.isEmpty ? [aspect] : gallery.aspects,
                                     referer: "https://grokipedia.com/")
                if !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 520)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A table, as Grokipedia draws one: a header row on a light band, hairlines between rows, inside a
/// rounded frame that scrolls sideways when it's wider than the column.
private struct ArticleTable: View {
    let header: [String]
    let rows: [[String]]

    private var columns: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                if !header.isEmpty {
                    GridRow {
                        ForEach(0..<columns, id: \.self) { index in
                            cell(header.indices.contains(index) ? header[index] : "", bold: true)
                        }
                    }
                    .background(Theme.hover)
                }
                ForEach(Array(rows.prefix(60).enumerated()), id: \.offset) { _, row in
                    Rectangle().fill(Theme.hairline).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(0..<columns, id: \.self) { index in
                            cell(row.indices.contains(index) ? row[index] : "", bold: false)
                        }
                    }
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
    }

    private func cell(_ text: String, bold: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: bold ? .semibold : .regular))
            .foregroundStyle(Theme.textPrimary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 90, maxWidth: 240, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .textSelection(.enabled)
    }
}

// MARK: - Sources

private struct SourceReferenceRow: View {
    let reference: GrokipediaReference
    let open: (URL) -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = reference.url { open(url) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(reference.number)")
                    .font(.mono(11.5, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 30, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let site = reference.site {
                        HStack(spacing: 5) {
                            ResultIcon(host: site, size: 12)
                            Text(site.hasPrefix("www.") ? String(site.dropFirst(4)) : site)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                if reference.url != nil {
                    Icon(.arrowUpRight, size: 13)
                        .foregroundStyle(hovering ? Theme.textPrimary : Theme.textQuaternary)
                }
            }
            .padding(.vertical, 9)
            .rowHairline()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reference.url == nil)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

/// A citation's source, in the small card that opens from its number.
private struct CitationCard: View {
    let reference: GrokipediaReference
    let open: (URL) -> Void

    var body: some View {
        MenuCard(width: 300) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Source \(reference.number)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                Text(reference.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .menuWrapping()
                if let site = reference.site {
                    HStack(spacing: 6) {
                        ResultIcon(host: site, size: 14)
                        Text(site.hasPrefix("www.") ? String(site.dropFirst(4)) : site)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            if let url = reference.url {
                MenuDivider()
                MenuRow(icon: .arrowUpRight, title: "Open the source") { open(url) }
            }
        }
    }
}

// MARK: - The infobox

/// Grokipedia's infobox: the title on a band, the article's picture with its caption, then label
/// and value rows on hairlines, the label column 92 points wide. A few rows first, the rest a click
/// away.
struct GrokipediaInfoboxCard: View {
    let card: GrokipediaCard
    let infobox: GrokipediaInfobox?
    var rows = 8
    @State private var showAll = false
    @State private var photoFailed = false
    @State private var photoAspect: CGFloat?

    private var facts: [KnowledgeFact] { infobox?.facts.isEmpty == false ? infobox!.facts : card.facts }
    private var images: [URL] {
        if let image = infobox?.image { return [image] + card.imageCandidates.filter { $0 != image } }
        return card.imageCandidates
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if facts.isEmpty && (images.isEmpty || photoFailed) {
            GrokipediaBook(title: card.title, images: card.imageCandidates)
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                Text(infobox?.title.isEmpty == false ? infobox!.title : card.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(Theme.hover)
                if !images.isEmpty, !photoFailed {
                    VStack(spacing: 0) {
                        // The picture whole, at its own shape, as Grokipedia shows it: a tall
                        // portrait narrows on a quiet band rather than being cropped.
                        AspectBox(aspect: photoAspect ?? 1.5, maxHeight: 300) {
                            FillImage(candidates: images, referer: "https://grokipedia.com/",
                                      onFailure: { photoFailed = true },
                                      onLoad: { size in
                                          guard size.height > 0 else { return }
                                          withAnimation(Motion.smooth) { photoAspect = size.width / size.height }
                                      })
                        }
                        .frame(maxWidth: .infinity)
                        .background(Theme.hover)
                        .opensInLightbox([images[0]], captions: [infobox?.caption ?? card.title],
                                         aspects: [photoAspect.map(Double.init)], referer: "https://grokipedia.com/")
                        if let caption = infobox?.caption {
                            Text(caption)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                    }
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                }
                ForEach(showAll ? facts : Array(facts.prefix(rows))) { fact in
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(fact.label)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 92, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(fact.value)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                if facts.count > rows {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    Button {
                        withAnimation(Motion.smooth) { showAll.toggle() }
                    } label: {
                        MorphLabel(text: showAll ? String(localized: "Fewer details") : String(localized: "All \(facts.count) details"),
                                   font: .system(size: 12.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                }
            }
            .background(shape.fill(Theme.raised))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
        }
    }
}

// MARK: - Contents

/// The contents beside the article: the sections, with the subsections of the one being read
/// unfolded under it, a bar that glides to the section in view, and how far through it is.
struct ContentsRail: View {
    let outline: [GrokipediaHeading]
    let hasSources: Bool
    let tracker: ReaderTracker
    let jump: (String) -> Void
    @Namespace private var marker

    /// Each section with its subsections.
    private var sections: [(heading: GrokipediaHeading, children: [GrokipediaHeading])] {
        var result: [(GrokipediaHeading, [GrokipediaHeading])] = []
        for heading in outline {
            if heading.level <= 2 || result.isEmpty {
                result.append((heading, []))
            } else {
                result[result.count - 1].1.append(heading)
            }
        }
        return result
    }

    var body: some View {
        let active = tracker.active(in: outline)
        let openSection = sections.first { section in
            section.heading.id == active || section.children.contains { $0.id == active }
        }?.heading.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Contents")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(Int((tracker.progress * 100).rounded()))%")
                    .font(.mono(11, weight: .regular))
                    .foregroundStyle(Theme.textQuaternary)
                    .contentTransition(.numericText())
            }
            .padding(.bottom, 8)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hover)
                    Capsule().fill(Theme.textSecondary)
                        .frame(width: max(2, proxy.size.width * tracker.progress))
                }
            }
            .frame(height: 2)
            .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.heading.id) { section in
                        row(section.heading, active: active)
                        if openSection == section.heading.id {
                            ForEach(section.children) { child in
                                row(child, active: active)
                                    .transition(.opacity.combined(with: .offset(y: -4)))
                            }
                        }
                    }
                    if hasSources {
                        row(GrokipediaHeading(id: "sources", level: 2, text: String(localized: "Sources")), active: active)
                    }
                }
                .animation(Motion.smooth, value: openSection)
                .animation(Motion.glide, value: active)
            }
            .frame(maxHeight: max(160, tracker.viewportHeight - 140))
            .scrollEdgeFade(10)
        }
    }

    private func row(_ heading: GrokipediaHeading, active: String?) -> some View {
        ContentsRow(heading: heading, isActive: heading.id == active, isSpoken: ArticleSpeaker.shared.section == heading.id,
                    marker: marker) { jump(heading.id) }
    }
}

private struct ContentsRow: View {
    let heading: GrokipediaHeading
    let isActive: Bool
    /// The section being read aloud.
    var isSpoken = false
    let marker: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack {
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    if isActive {
                        Capsule().fill(Theme.textPrimary)
                            .frame(width: 2)
                            .padding(.vertical, 4)
                            .matchedGeometryEffect(id: "marker", in: marker)
                    }
                }
                .frame(width: 2)
                Text(heading.text)
                    .font(.system(size: heading.level > 2 ? 12.5 : 13.5, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? Theme.textPrimary : (hovering ? Theme.textSecondary : Theme.textTertiary))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, heading.level > 2 ? 26 : 14)
                    .padding(.vertical, 6)
                    .offset(x: hovering && !isActive ? 2 : 0)
                Spacer(minLength: 0)
                if isSpoken {
                    Icon(.speaker, size: 13)
                        .foregroundStyle(Theme.textSecondary)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.3), value: hovering)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

/// Narrow pages: the contents folded under one row, unfolding to the numbered sections.
struct FoldedContents: View {
    let outline: [GrokipediaHeading]
    let jump: (String) -> Void
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.smooth) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Contents")
                        .font(.system(size: 13.5, weight: .medium))
                    Text("\(outline.filter { $0.level == 2 }.count)")
                        .font(.mono(11, weight: .regular))
                        .foregroundStyle(Theme.textQuaternary)
                    Spacer()
                    MorphChevron(open: open, size: 13)
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rowHairline()
            if open {
                VStack(spacing: 0) {
                    ForEach(Array(outline.filter { $0.level == 2 }.enumerated()), id: \.element.id) { index, heading in
                        NumberedRow(number: index + 1, title: heading.text) { jump(heading.id) }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .frame(maxWidth: 440)
    }
}

// MARK: - Loading and lists

struct GrokipediaArticleSkeleton: View {
    let wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Icon(.book, size: 15)
                ShimmerText(text: String(localized: "Reading Grokipedia"), font: .system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.textTertiary)
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.hover)
                .frame(width: 280, height: 40)
                .padding(.top, 16)
            SkeletonBar(width: 0.34, height: 10).padding(.top, 14)
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 22)
            HStack(alignment: .top, spacing: GrokSearchPage.gap) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<7, id: \.self) { index in
                        SkeletonBar(width: index == 6 ? 0.5 : 0.96, height: 11, delay: Double(index) * 0.08)
                    }
                }
                .frame(maxWidth: GrokSearchPage.mainWidth)
                if wide {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.hover)
                        .frame(width: GrokSearchPage.sideWidth, height: 300)
                }
            }
        }
    }
}

/// More articles on the search, in Grokipedia's search list: the title in the book serif, two
/// lines of the article, a chevron, hairlines between. Each opens here, natively.
struct GrokipediaList: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    @Namespace private var pick

    private var others: [WebResult] { search.otherArticles }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch search.articles {
            case .idle, .loading:
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<4, id: \.self) { row in
                        VStack(alignment: .leading, spacing: 10) {
                            SkeletonBar(width: 0.4, height: 16, delay: Double(row) * 0.1)
                            SkeletonBar(width: 0.9, height: 9, delay: Double(row) * 0.1 + 0.05)
                            SkeletonBar(width: 0.6, height: 9, delay: Double(row) * 0.1 + 0.1)
                        }
                        .padding(.vertical, 18)
                        .rowHairline()
                    }
                }
                .frame(maxWidth: GrokSearchPage.mainWidth)
                .transition(.opacity)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Text(message)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Try again") { search.loadArticles() }
                        .pill(.secondary, size: .small)
                }
            case .ready:
                if others.isEmpty {
                    if search.pad == .none {
                        empty
                    }
                } else {
                    ModuleHeader(title: "More on Grokipedia",
                                 detail: others.count == 1 ? String(localized: "1 article") : String(localized: "\(others.count) articles"))
                        .padding(.bottom, 4)
                        .frame(maxWidth: GrokSearchPage.mainWidth)
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, result in
                        GrokipediaRow(result: result, order: index, picked: search.picked[.grokipedia] == index, pick: pick,
                                      besideResults: { browser.openBeside($0) }) { url in
                            openGrokipediaResult(url, title: result.title, browser: browser)
                        }
                        .id(result.id)
                    }
                    .frame(maxWidth: GrokSearchPage.mainWidth)
                }
                footer
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Grokipedia article on “\(search.query)”")
                .font(.serif(28, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(Theme.textPrimary)
            Text("Grokipedia may still have it under another name.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let url = GrokipediaLinks.search(search.query) {
                ArrowLink(title: "Search Grokipedia for “\(search.query)”") { openFromResults(url, browser: browser) }
            }
            Spacer(minLength: 8)
            Text("Articles found with Grokipedia's own search")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textQuaternary)
        }
        .padding(.top, 22)
        .frame(maxWidth: GrokSearchPage.mainWidth)
    }
}

/// A Grokipedia address opens natively when it's an article; anything else opens as a page.
@MainActor
func openGrokipediaResult(_ url: URL, title: String, browser: BrowserModel) {
    if let page = GrokipediaLinks.page(of: url) {
        openGrokipediaArticle(page, title: GrokSearch.articleTitle(title), browser: browser)
    } else {
        openFromResults(url, browser: browser)
    }
}

/// A row of Grokipedia's search list. On hover the title steps back to grey and the chevron comes
/// forward; rows rise 8 points into place 60 ms apart.
struct GrokipediaRow: View {
    let result: WebResult
    let order: Int
    var picked = false
    var pick: Namespace.ID? = nil
    var besideResults: (URL) -> Void = { _ in }
    let open: (URL) -> Void
    @State private var hovering = false

    var body: some View {
        Button { open(result.url) } label: {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title)
                        .font(.serif(22, weight: .medium))
                        .tracking(-22 * 0.018)
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !result.snippet.isEmpty {
                        Text(result.plainSnippet)
                            .font(.system(size: 14))
                            .lineSpacing(4.5)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chevronRight, size: 16)
                    .foregroundStyle(hovering || picked ? Theme.textPrimary : Theme.textTertiary)
                    .offset(x: hovering || picked ? 2 : 0)
            }
            .padding(.vertical, 16)
            .background {
                if picked, let pick { PickVeil(namespace: pick) }
            }
            .rowHairline()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.standard(0.17), value: hovering)
        .riseIn(order: order)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Open Beside the Results") { besideResults(result.url) }
        }
    }
}
