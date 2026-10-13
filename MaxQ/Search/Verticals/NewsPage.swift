//
//  NewsPage.swift
//  Max Q
//
//  The News tab, behind More. Three ways to look at the same reports:
//
//    Top stories: the reports grouped into events, the lead with its picture, each with the outlets
//                 that also covered it ("Full coverage · 6 sources"), developing stories marked.
//    Latest:      every report, newest first.
//    Timeline:    the news, the dated web results and the Grokipedia article on one line, by day:
//                 how the subject unfolded.
//
//  Beside it, Grok's answer in short and the Grokipedia article, as on All. With a search key the
//  reports and their pictures come from the Brave Search API (pictures from Brave's own copies);
//  without one, from the outlets' own news feeds, with the outlets' pictures.
//

import SwiftUI

struct NewsPage: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let wide: Bool

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: GrokSearchPage.gap) {
                VStack(alignment: .leading, spacing: 0) {
                    if !wide {
                        HStack(spacing: 8) {
                            NewsViewSwitch(search: search)
                            Spacer(minLength: 8)
                            NewsTimeMenu(search: search)
                        }
                        .padding(.bottom, 14)
                    }
                    NewsMain(browser: browser, search: search)
                }
                .frame(maxWidth: GrokSearchPage.mainWidth, alignment: .leading)
                if wide {
                    NewsSideColumn(browser: browser, search: search)
                        .frame(width: GrokSearchPage.sideWidth)
                }
            }
            .pageColumns(wide: wide)
        }
        .pageScroll()
    }
}

/// The News tab's control beside the tabs: the view and the period.
struct NewsAccessory: View {
    let search: GrokSearch

    var body: some View {
        HStack(spacing: 8) {
            NewsTimeMenu(search: search)
            NewsViewSwitch(search: search)
        }
    }
}

/// Top stories, Latest, Timeline: a thumb glides between them on grok.com's selection spring.
struct NewsViewSwitch: View {
    let search: GrokSearch
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NewsView.allCases) { view in
                let selected = search.newsView == view
                Button {
                    withAnimation(Motion.glide) { search.newsView = view }
                } label: {
                    Text(view.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background {
                            if selected {
                                Capsule().fill(Theme.raised)
                                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                                    .elevation(.raised)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.hover))
    }
}

/// How recent the news must be.
struct NewsTimeMenu: View {
    let search: GrokSearch

    var body: some View {
        MenuButton(placement: .below(.trailing)) { isOpen in
            HStack(spacing: 5) {
                Icon(.clock, size: 15)
                Text(search.newsTime.title)
                    .contentTransition(.interpolate)
                MorphChevron(open: isOpen, size: 12)
            }
            .foregroundStyle(search.newsTime == .any ? Theme.textSecondary : Theme.textPrimary)
        } content: {
            MenuCard(width: 190) {
                ForEach([SearchTime.any, .day, .week, .month]) { time in
                    MenuRow(verbatim: time.title, checked: search.newsTime == time) {
                        withAnimation(Motion.smooth) { search.setNewsTime(time) }
                    }
                }
            }
        }
        .pill(search.newsTime == .any ? .ghost : .secondary, size: .mini)
        .tip("Show news from a period")
        .accessibilityLabel(Text("News time: \(search.newsTime.title)"))
    }
}

// MARK: - The column

private struct NewsMain: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch search.news.phase {
            case .idle, .loading:
                NewsSkeleton()
                    .transition(.opacity)
            case .failed(let message):
                VerticalFailure(message: message, retry: { search.news.reload() },
                                site: DuckDuckGoPages.news(search.query), browser: browser)
            case .needsKey:
                SearchKeyPrompt(browser: browser, site: DuckDuckGoPages.news(search.query))
            case .ready:
                if search.news.items.isEmpty {
                    VerticalEmpty(text: search.newsTime == .any
                                  ? String(localized: "No news for “\(search.query)”.")
                                  : String(localized: "No news for “\(search.query)” from the \(search.newsTime.title.lowercased())."),
                                  reset: search.newsTime == .any ? nil : { search.setNewsTime(.any) })
                } else {
                    ZStack(alignment: .top) {
                        switch search.newsView {
                        case .top:
                            TopStories(browser: browser, search: search)
                                .transition(.blurFade(radius: 3))
                        case .latest:
                            LatestNews(browser: browser, search: search)
                                .transition(.blurFade(radius: 3))
                        case .timeline:
                            NewsTimeline(browser: browser, search: search)
                                .transition(.blurFade(radius: 3))
                        }
                    }
                    .animation(Motion.standard(0.22), value: search.newsView)
                    if search.newsView != .timeline {
                        MoreButton(loading: search.news.loadingMore, failed: search.news.moreFailed,
                                   visible: search.news.canLoadMore || search.news.loadingMore,
                                   title: String(localized: "More news")) { search.news.loadMore() }
                    }
                    SourceFootnote(text: SearchAPIAccount.shared.hasKey ? "This search on DuckDuckGo" : "From the outlets' own news feeds",
                                   link: SearchAPIAccount.shared.hasKey ? "Open there" : "Open on DuckDuckGo") {
                        if let url = DuckDuckGoPages.news(search.query) { openFromResults(url, browser: browser) }
                    }
                    .padding(.top, 28)
                }
            }
        }
        .animation(Motion.standard(0.25), value: search.news.phase)
    }
}

// MARK: - Top stories

private struct TopStories: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    @Namespace private var pick

    var body: some View {
        let stories = search.newsStories
        let fresh = Date().timeIntervalSince(search.news.arrived) < 1.5
        let lead = stories.first(where: { $0.image != nil }) ?? stories.first
        let rest = stories.filter { $0.id != lead?.id }
        LazyVStack(alignment: .leading, spacing: 0) {
            if let lead {
                LeadStory(story: lead, browser: browser)
                    .riseIn(order: 0, animated: fresh)
                    .padding(.bottom, 8)
                    .rowHairline()
            }
            ForEach(Array(rest.enumerated()), id: \.element.id) { index, story in
                StoryRow(story: story, browser: browser, picked: search.picked[.news] == index + (lead == nil ? 0 : 1), pick: pick)
                    .riseIn(order: index + 1, animated: fresh)
                    .id(story.id)
            }
        }
        .animation(Motion.smooth, value: search.picked[.news])
    }
}

/// The top story: its picture across the column, the headline, the lead of the report and the
/// other outlets that covered it.
private struct LeadStory: View {
    let story: NewsStory
    @Bindable var browser: BrowserModel
    @State private var hovering = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { openFromResults(story.lead.url, browser: browser) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    if let image = story.image {
                        AspectBox(aspect: 16 / 9, maxHeight: 360) {
                            FillImage(candidates: [image])
                                .scaleEffect(hovering ? 1.015 : 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    OutletLine(item: story.lead, breaking: story.isBreaking)
                    Text(story.lead.title)
                        .font(.system(size: 23, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !story.lead.excerpt.isEmpty {
                        Text(story.lead.excerpt)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(4)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.spring(0.35), value: hovering)
            .newsContextMenu(story.lead.url, browser: browser) { story.lead.collectionItem }

            if !story.others.isEmpty {
                CoverageButton(story: story, expanded: $expanded)
                if expanded {
                    CoverageList(items: story.others, browser: browser)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 18)
        .animation(Motion.smooth, value: expanded)
    }
}

/// A story as a row: the outlet and when, the headline, two lines of the report, its picture at
/// the end, and the other outlets that covered it.
private struct StoryRow: View {
    let story: NewsStory
    @Bindable var browser: BrowserModel
    var picked = false
    var pick: Namespace.ID? = nil
    @State private var hovering = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { openFromResults(story.lead.url, browser: browser) } label: {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        OutletLine(item: story.lead, breaking: story.isBreaking)
                        Text(story.lead.title)
                            .font(.system(size: 17.5, weight: .medium))
                            .tracking(-0.2)
                            .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !story.lead.excerpt.isEmpty {
                            Text(story.lead.excerpt)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textSecondary)
                                .lineSpacing(4)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let image = story.image {
                        NewsThumb(url: image, hovering: hovering)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .newsContextMenu(story.lead.url, browser: browser) { story.lead.collectionItem }

            if !story.others.isEmpty {
                CoverageButton(story: story, expanded: $expanded)
                if expanded {
                    CoverageList(items: story.others, browser: browser)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.vertical, 18)
        .background {
            if picked, let pick { PickVeil(namespace: pick) }
        }
        .rowHairline()
        .onHover { hovering = $0 }
        .animation(Motion.standard(0.17), value: hovering)
        .animation(Motion.smooth, value: expanded)
    }
}

/// "Full coverage · 4 sources", with the outlets' marks overlapping, as x.com stacks avatars.
private struct CoverageButton: View {
    let story: NewsStory
    @Binding var expanded: Bool
    @State private var hovering = false

    var body: some View {
        Button { withAnimation(Motion.smooth) { expanded.toggle() } } label: {
            HStack(spacing: 8) {
                HStack(spacing: -6) {
                    ForEach(Array(story.reports.prefix(4).enumerated()), id: \.element.id) { index, item in
                        OutletIcon(item: item, size: 18)
                            .padding(1.5)
                            .background(Circle().fill(Theme.surface))
                            .zIndex(Double(10 - index))
                    }
                }
                Text(expanded ? String(localized: "Hide coverage") : String(localized: "Full coverage · \(story.sourceCount) sources"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                    .contentTransition(.interpolate)
                MorphChevron(open: expanded, size: 11)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: 30)
            .background(Capsule().fill(hovering ? Theme.selected : Theme.hover))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

/// The other outlets' reports of one story, one line each.
private struct CoverageList: View {
    let items: [NewsItem]
    @Bindable var browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                CoverageRow(item: item) { openFromResults(item.url, browser: browser) }
                    .newsContextMenu(item.url, browser: browser) { item.collectionItem }
            }
        }
        .padding(.leading, 2)
    }
}

private struct CoverageRow: View {
    let item: NewsItem
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                OutletIcon(item: item, size: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(item.source.isEmpty ? item.host : item.source)
                        if let date = item.date {
                            Text("·").foregroundStyle(Theme.textQuaternary)
                            Text(ResultDate.label(date, isDay: false))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

// MARK: - Latest

private struct LatestNews: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    @Namespace private var pick

    var body: some View {
        let items = search.latestNews
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                NewsRow(item: item, browser: browser, picked: search.picked[.news] == index, pick: pick)
                    .riseIn(order: index, animated: false)
                    .id(item.id)
            }
        }
        .animation(Motion.smooth, value: search.picked[.news])
    }
}

private struct NewsRow: View {
    let item: NewsItem
    @Bindable var browser: BrowserModel
    var picked = false
    var pick: Namespace.ID? = nil
    @State private var hovering = false

    var body: some View {
        Button { openFromResults(item.url, browser: browser) } label: {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    OutletLine(item: item, breaking: false)
                    Text(item.title)
                        .font(.system(size: 17, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.excerpt.isEmpty {
                        Text(item.excerpt)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(4)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let image = item.image {
                    NewsThumb(url: image, hovering: hovering)
                }
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
        .newsContextMenu(item.url, browser: browser) { item.collectionItem }
    }
}

// MARK: - Pieces

/// The outlet's mark and name, when it ran the report, and whether it's live or developing.
private struct OutletLine: View {
    let item: NewsItem
    let breaking: Bool

    var body: some View {
        HStack(spacing: 7) {
            OutletIcon(item: item, size: 16)
            Text(item.source.isEmpty ? item.host : item.source)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let date = item.date {
                Text("·").foregroundStyle(Theme.textQuaternary)
                if NewsFreshness(date) == .live {
                    LiveDot(color: Theme.danger, size: 5)
                }
                Text(ResultDate.label(date, isDay: false))
                    .foregroundStyle(NewsFreshness(date) == .live ? Theme.textPrimary : Theme.textTertiary)
                    .fixedSize()
            }
            if breaking {
                HStack(spacing: 3) {
                    Icon(.bolt, size: 11)
                    Text("Developing")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(Capsule().fill(Theme.hover))
                .overlay(Capsule().strokeBorder(Theme.chipBorder, lineWidth: 1))
            }
        }
        .font(.system(size: 12.5))
    }
}

/// An outlet's mark: its site's icon, or its initial when the link is an aggregator's (MSN, Yahoo),
/// whose icon would name the wrong outlet.
struct OutletIcon: View {
    let item: NewsItem
    var size: CGFloat = 16

    private static let aggregators: Set<String> = ["msn.com", "yahoo.com", "news.yahoo.com", "aol.com", "newsbreak.com",
                                                   "flipboard.com", "news.google.com", "apple.news"]

    var body: some View {
        if Self.aggregators.contains(where: { item.host == $0 || item.host.hasSuffix("." + $0) }) {
            Text(String((item.source.first ?? "N")).uppercased())
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(Theme.onInk)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.ink))
                .accessibilityHidden(true)
        } else {
            ResultIcon(host: item.url.host ?? "", size: size * 0.75)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.hover))
                .clipShape(Circle())
        }
    }
}

private struct NewsThumb: View {
    let url: URL
    let hovering: Bool
    @State private var failed = false

    var body: some View {
        if !failed {
            FillImage(candidates: [url]) { failed = true }
                .scaleEffect(hovering ? 1.04 : 1)
                .frame(width: 124, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                .animation(Motion.spring(0.35), value: hovering)
                .padding(.top, 2)
        }
    }
}

private struct NewsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.hover)
                .frame(height: 280)
                .padding(.bottom, 16)
            SkeletonBar(width: 0.3, height: 9)
                .padding(.bottom, 10)
            SkeletonBar(width: 0.85, height: 16, delay: 0.05)
                .padding(.bottom, 8)
            SkeletonBar(width: 0.6, height: 16, delay: 0.1)
                .padding(.bottom, 26)
            ForEach(0..<3, id: \.self) { row in
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBar(width: 0.3, height: 9, delay: Double(row) * 0.1)
                        SkeletonBar(width: 0.9, height: 13, delay: Double(row) * 0.1 + 0.05)
                        SkeletonBar(width: 0.7, height: 9, delay: Double(row) * 0.1 + 0.1)
                    }
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.hover)
                        .frame(width: 124, height: 84)
                }
                .padding(.vertical, 18)
                .rowHairline()
            }
        }
    }
}

// MARK: - Beside the news

private struct NewsSideColumn: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            AnswerDigest(browser: browser, search: search)
            if case .ready(let card) = search.pad {
                SideArticle(card: card) { search.show(.grokipedia) }
                    .transition(.rise)
            }
        }
        .animation(Motion.smooth, value: search.answer)
        .animation(Motion.smooth, value: search.pad)
    }
}

/// The Grokipedia article beside another tab: its picture, title and opening lines; it opens the
/// Grokipedia tab.
struct SideArticle: View {
    let card: GrokipediaCard
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Icon(.book, size: 13)
                    Text("Grokipedia")
                    Spacer(minLength: 0)
                    Icon(.chevronRight, size: 13)
                        .foregroundStyle(hovering ? Theme.textPrimary : Theme.textQuaternary)
                        .offset(x: hovering ? 2 : 0)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                HStack(alignment: .top, spacing: 14) {
                    GrokipediaBook(title: card.title, images: card.imageCandidates, width: 50, height: 72)
                        .frame(width: 60, height: 82)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(card.title)
                            .font(.serif(20, weight: .medium))
                            .tracking(-0.36)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Text(card.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(2)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hovering ? Theme.selected : Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

// MARK: - Shared by the tabs behind More

/// DuckDuckGo's own pages for a search, for "Open there".
enum DuckDuckGoPages {
    static func news(_ query: String) -> URL? { page(query, "news") }
    static func images(_ query: String) -> URL? { page(query, "images") }
    static func videos(_ query: String) -> URL? { page(query, "videos") }

    private static func page(_ query: String, _ tab: String) -> URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "iar", value: tab),
                                 URLQueryItem(name: "ia", value: tab)]
        return components.url
    }
}

/// A tab that couldn't load: why, and the ways on.
struct VerticalFailure: View {
    let message: String
    let retry: () -> Void
    let site: URL?
    @Bindable var browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Button("Try again", action: retry)
                    .pill(.secondary, size: .small)
                if let site {
                    Button("Open on DuckDuckGo") { openFromResults(site, browser: browser) }
                        .pill(.ghost, size: .small)
                }
            }
        }
        .padding(.vertical, 18)
    }
}

/// A tab with nothing to show, and the way back to everything when a filter is narrowing it.
struct VerticalEmpty: View {
    let text: String
    var reset: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            if let reset {
                Button("Clear filters") { withAnimation(Motion.smooth) { reset() } }
                    .pill(.secondary, size: .small)
            }
        }
        .padding(.vertical, 20)
    }
}

/// "More news": the chevron gathers into dots while the next page loads.
struct MoreButton: View {
    let loading: Bool
    let failed: Bool
    let visible: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        if visible {
            HStack {
                Spacer()
                Button(action: action) {
                    HStack(spacing: 8) {
                        if loading {
                            ShimmerText(text: String(localized: "Loading more"), font: .system(size: 14, weight: .medium))
                        } else {
                            Text(failed ? String(localized: "Try again") : title)
                        }
                        MorphIcon(loading ? .dots : .chevronDown, size: 14, weight: 2.4)
                            .opacity(loading ? 0.6 : 1)
                    }
                    .animation(Motion.spring(0.3), value: loading)
                }
                .pill(.outline, size: .regular)
                .disabled(loading)
                Spacer()
            }
            .padding(.top, 24)
        }
    }
}

extension View {
    /// The menu a result's row opens with a right-click; `save` makes what goes into a collection.
    func newsContextMenu(_ url: URL, browser: BrowserModel, save: (() -> CollectionItem)? = nil) -> some View {
        modifier(ResultMenu(url: url, browser: browser, save: save))
    }
}

private struct ResultMenu: ViewModifier {
    let url: URL
    let browser: BrowserModel
    let save: (() -> CollectionItem)?
    @Environment(\.collectionName) private var collectionName

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Open Link in New Tab") { browser.openInNewTab(url, select: false) }
                Button("Open Beside the Results") { browser.openBeside(url) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                if !browser.isPrivate {
                    Divider()
                    AddToCollectionMenu(item: save ?? { CollectionItem(kind: .page, title: url.host ?? url.absoluteString, url: url, source: url.host) },
                                        suggestedName: collectionName.isEmpty ? (url.host ?? "") : collectionName)
                }
            }
            .draggable(url)
    }
}

extension NewsItem {
    /// The story as an item in a collection: with the outlet's own summary and picture when it came
    /// from the outlet's feed, as a link and its title when the search API found it.
    var collectionItem: CollectionItem {
        viaSearchAPI
            ? CollectionItem(kind: .news, title: title, url: url, source: source.isEmpty ? host : source)
            : CollectionItem(kind: .news, title: title, url: url, text: excerpt, image: image, source: source.isEmpty ? host : source)
    }
}
