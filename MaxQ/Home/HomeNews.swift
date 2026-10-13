//
//  HomeNews.swift
//  Max Q
//
//  The news below the new-tab page's question, reached by scrolling down (or "Today's news"). At
//  the top, the day's top story across the column: its picture, the headline, and how many outlets
//  ran it. Then each topic as a section, its lead story with a picture beside the next few. Topic
//  chips jump to their section; the menu beside them chooses which topics show. A story opens in
//  the tab; "Full coverage" opens Max Q's own News tab on it, with every outlet's report.
//

import SwiftUI

struct HomeNewsSection: View {
    @Bindable var browser: BrowserModel
    /// Scrolls the page to a topic's section.
    let jump: (String) -> Void
    @State private var feed = HomeNewsFeed.shared
    @State private var width: CGFloat = 900

    private var wide: Bool { width >= 820 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)
            chips
                .padding(.bottom, 26)
            if let story = feed.topStory {
                TopStoryCard(story: story, browser: browser, wide: wide, width: width)
                    .padding(.bottom, 40)
                    .transition(.opacity)
            } else if !feed.loading.isEmpty || feed.stories.isEmpty {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.hover)
                    .frame(height: wide ? 300 : 420)
                    .pulsing()
                    .padding(.bottom, 40)
            }
            ForEach(feed.visibleTopics.filter { $0.id != "top" }) { topic in
                TopicSection(topic: topic, browser: browser, wide: wide)
                    .id(topic.id)
                    .padding(.bottom, 44)
                    .onAppear { feed.loadIfNeeded(topic) }
            }
            footnote
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(Motion.smooth, value: feed.topStory?.id)
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.heading(26))
                    .tracking(-0.52)
                    .foregroundStyle(Theme.textPrimary)
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            if let updated = feed.updated {
                Text(feed.refreshing ? String(localized: "Updating") : String(localized: "Updated \(ResultDate.label(updated, isDay: false))"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.interpolate)
            }
            Button { feed.refresh() } label: {
                Icon(.reload, size: 16)
                    .rotationEffect(.degrees(feed.refreshing ? 360 : 0))
                    .animation(feed.refreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: feed.refreshing)
            }
            .iconButton(size: 30)
            .tip("Refresh the news")
            .accessibilityLabel("Refresh the News")
            MenuButton(placement: .below(.trailing)) { _ in
                Icon(.more, size: 16)
            } content: {
                TopicChooser(feed: feed)
            }
            .iconButton(size: 30)
            .tip("Choose topics")
            .accessibilityLabel("Choose News Topics")
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(feed.visibleTopics.filter { $0.id != "top" }) { topic in
                    TopicChip(topic: topic, loading: feed.loading.contains(topic.id)) {
                        feed.loadIfNeeded(topic)
                        jump(topic.id)
                    }
                }
            }
        }
        .rowEdgeFade()
    }

    private var footnote: some View {
        Text("From the outlets' own news feeds, in your Mac's language. A story opens in this tab, or ⌘-click for a new one.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}

/// Which topics the news shows, as switches.
private struct TopicChooser: View {
    let feed: HomeNewsFeed

    var body: some View {
        MenuCard(width: 230) {
            MenuSectionTitle("Topics")
            ForEach(HomeNewsFeed.topics.filter { $0.id != "top" }) { topic in
                let on = feed.visibleTopics.contains(topic)
                MenuRow(icon: topic.icon, verbatim: topic.title, checked: on) {
                    withAnimation(Motion.smooth) { feed.setVisible(topic.id, !on) }
                }
            }
            MenuDivider()
            MenuRow(icon: .gear, title: "News settings") {
                SettingsRouter.shared.section = .general
                BrowserCommandRouter.openSettings?()
            }
        }
    }
}

private struct TopicChip: View {
    let topic: HomeNewsFeed.Topic
    let loading: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(topic.icon, size: 14)
                    .foregroundStyle(Theme.textTertiary)
                Text(topic.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(hovering ? Theme.selected : Theme.chip))
            .overlay(Capsule().strokeBorder(Theme.chipBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

// MARK: - The top story

private struct TopStoryCard: View {
    let story: NewsStory
    @Bindable var browser: BrowserModel
    let wide: Bool
    /// The column's width: on wide pages the picture takes a little over half of it.
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 28)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
        layout {
            Button { openFromResults(story.lead.url, browser: browser) } label: {
                AspectBox(aspect: 16 / 10, maxHeight: 380) {
                    FillImage(candidates: [story.image].compactMap { $0 })
                        .scaleEffect(hovering ? 1.02 : 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(width: wide ? (width * 0.56).rounded() : nil)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Icon(.bolt, size: 13)
                    Text("Top story")
                    if let date = story.latest {
                        Text("·").foregroundStyle(Theme.textQuaternary)
                        Text(ResultDate.label(date, isDay: false))
                    }
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                Button { openFromResults(story.lead.url, browser: browser) } label: {
                    Text(story.lead.title)
                        .font(.system(size: wide ? 26 : 24, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                if !story.lead.excerpt.isEmpty {
                    Text(story.lead.excerpt)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(4)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                OutletsLine(story: story)
                HStack(spacing: 8) {
                    Button {
                        browser.openMaxQSearch(story.lead.title, on: .news)
                    } label: {
                        HStack(spacing: 6) {
                            Icon(.stack, size: 15)
                            Text(story.sourceCount > 1 ? String(localized: "Full coverage") : String(localized: "More on this"))
                        }
                    }
                    .pill(.secondary, size: .small)
                    Button {
                        browser.askGrok(String(localized: "What's the latest on this story, and what's confirmed so far? \(story.lead.title)"))
                    } label: {
                        HStack(spacing: 6) {
                            Icon(.bubble, size: 15)
                            Text("Ask Grok")
                        }
                    }
                    .pill(.ghost, size: .small)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.35), value: hovering)
        .newsContextMenu(story.lead.url, browser: browser) { story.lead.collectionItem }
    }
}

/// The outlets that ran a story: their marks overlapping, and their names.
private struct OutletsLine: View {
    let story: NewsStory

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -6) {
                ForEach(Array(story.reports.prefix(5).enumerated()), id: \.element.id) { index, item in
                    OutletIcon(item: item, size: 20)
                        .padding(1.5)
                        .background(Circle().fill(Theme.surface))
                        .zIndex(Double(10 - index))
                }
            }
            Text(names)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var names: String {
        let outlets = story.reports.map { $0.source.isEmpty ? $0.host : $0.source }
        guard outlets.count > 1 else { return outlets.first ?? "" }
        let shown = outlets.prefix(2).joined(separator: ", ")
        return outlets.count > 2 ? String(localized: "\(shown) and \(outlets.count - 2) more") : shown
    }
}

// MARK: - Topics

private struct TopicSection: View {
    let topic: HomeNewsFeed.Topic
    @Bindable var browser: BrowserModel
    let wide: Bool
    private var feed: HomeNewsFeed { HomeNewsFeed.shared }

    var body: some View {
        let stories = Array(feed.stories(for: topic).prefix(HomeNewsFeed.perTopic))
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Icon(topic.icon, size: 15)
                    .foregroundStyle(Theme.textTertiary)
                Text(topic.title)
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.textPrimary)
                if feed.loading.contains(topic.id) {
                    LiveDot(color: Theme.textSecondary, size: 5)
                }
                Spacer(minLength: 8)
                ArrowLink(title: "See all") { browser.openMaxQSearch(topic.query, on: .news) }
            }
            .rowHairlineBelow()
            if stories.isEmpty {
                if feed.failed.contains(topic.id) {
                    HStack(spacing: 10) {
                        Text("This topic didn't load.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                        Button("Try again") { feed.loadIfNeeded(topic) }
                            .pill(.secondary, size: .mini)
                    }
                } else {
                    TopicSkeleton(wide: wide)
                }
            } else {
                let lead = stories.first(where: { $0.image != nil }) ?? stories[0]
                let rest = stories.filter { $0.id != lead.id }
                let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 28)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                layout {
                    HomeStoryCard(story: lead, browser: browser)
                        .frame(maxWidth: wide ? 400 : .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(rest) { story in
                            HomeStoryRow(story: story, browser: browser)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: stories.map(\.id))
    }
}

private struct HomeStoryCard: View {
    let story: NewsStory
    @Bindable var browser: BrowserModel
    @State private var hovering = false

    var body: some View {
        Button { openFromResults(story.lead.url, browser: browser) } label: {
            VStack(alignment: .leading, spacing: 10) {
                if let image = story.image {
                    AspectBox(aspect: 16 / 9, maxHeight: 260) {
                        FillImage(candidates: [image])
                            .scaleEffect(hovering ? 1.03 : 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                }
                StoryMeta(story: story)
                Text(story.lead.title)
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.35), value: hovering)
        .newsContextMenu(story.lead.url, browser: browser) { story.lead.collectionItem }
    }
}

private struct HomeStoryRow: View {
    let story: NewsStory
    @Bindable var browser: BrowserModel
    @State private var hovering = false

    var body: some View {
        Button { openFromResults(story.lead.url, browser: browser) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    StoryMeta(story: story)
                    Text(story.lead.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let image = story.image {
                    FillImage(candidates: [image])
                        .frame(width: 92, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -12)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .newsContextMenu(story.lead.url, browser: browser) { story.lead.collectionItem }
    }
}

/// The outlet, how long ago, and how many others ran it.
private struct StoryMeta: View {
    let story: NewsStory

    var body: some View {
        HStack(spacing: 6) {
            OutletIcon(item: story.lead, size: 15)
            Text(story.lead.source.isEmpty ? story.lead.host : story.lead.source)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let date = story.latest {
                Text("·").foregroundStyle(Theme.textQuaternary)
                if NewsFreshness(date) == .live { LiveDot(color: Theme.danger, size: 5) }
                Text(ResultDate.label(date, isDay: false))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            if story.sourceCount > 1 {
                Text("·").foregroundStyle(Theme.textQuaternary)
                Text("\(story.sourceCount) sources")
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .font(.system(size: 12.5))
    }
}

private struct TopicSkeleton: View {
    let wide: Bool

    var body: some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 28)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
        layout {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.hover)
                    .frame(height: 200)
                    .pulsing()
                SkeletonBar(width: 0.4, height: 9)
                SkeletonBar(width: 0.9, height: 13, delay: 0.05)
            }
            .frame(maxWidth: wide ? 400 : .infinity)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(0..<4, id: \.self) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBar(width: 0.3, height: 9, delay: Double(row) * 0.1)
                        SkeletonBar(width: 0.85, height: 12, delay: Double(row) * 0.1 + 0.05)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

extension View {
    /// A hairline a little below the view (a section's header).
    func rowHairlineBelow() -> some View {
        padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
