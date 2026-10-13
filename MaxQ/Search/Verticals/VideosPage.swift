//
//  VideosPage.swift
//  Max Q
//
//  The Videos tab, behind More: a grid of videos at 16:9, each with its length on the still, the
//  title, the channel, how many people watched it and when. Filters for when and how long sit
//  above the grid. A video opens in the tab (Back returns to the results), where Grok can be asked
//  about it.
//

import SwiftUI

struct VideosPage: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let wide: Bool

    private var feed: VerticalFeed<VideoItem> { search.videos }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                VideoFilterBar(search: search)
                    .padding(.bottom, 18)
                switch feed.phase {
                case .idle, .loading:
                    VideoGridSkeleton()
                        .transition(.opacity)
                case .failed(let message):
                    VerticalFailure(message: message, retry: { feed.reload() },
                                    site: DuckDuckGoPages.videos(search.query), browser: browser)
                case .needsKey:
                    SearchKeyPrompt(browser: browser, site: DuckDuckGoPages.videos(search.query))
                case .ready:
                    if search.shownVideos.isEmpty {
                        VerticalEmpty(text: String(localized: "No videos for “\(search.query)”."),
                                      reset: search.videoFilters.isDefault ? nil : { search.setVideoFilters(VideoFilters()) })
                    } else {
                        grid
                        MoreButton(loading: feed.loadingMore, failed: feed.moreFailed,
                                   visible: feed.canLoadMore || feed.loadingMore,
                                   title: String(localized: "More videos")) { feed.loadMore() }
                        SourceFootnote(text: "This search on DuckDuckGo", link: "Open there") {
                            if let url = DuckDuckGoPages.videos(search.query) { openFromResults(url, browser: browser) }
                        }
                        .padding(.top, 28)
                    }
                }
            }
            .padding(.horizontal, wide ? 40 : 28)
            .padding(.top, 22)
            .padding(.bottom, 56)
            .frame(maxWidth: 1320)
            .frame(maxWidth: .infinity)
            .animation(Motion.standard(0.25), value: feed.phase)
        }
        .pageScroll()
    }

    private var grid: some View {
        let fresh = Date().timeIntervalSince(feed.arrived) < 1.5
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 248, maximum: 420), spacing: 20, alignment: .top)],
                         alignment: .leading, spacing: 28) {
            ForEach(Array(search.shownVideos.enumerated()), id: \.element.id) { index, video in
                VideoTile(video: video) { openFromResults(video.url, browser: browser) }
                    .newsContextMenu(video.url, browser: browser) {
                        // The link and its title, like a bookmark (see the web results' menu).
                        CollectionItem(kind: .video, title: video.title, url: video.url, source: video.uploader ?? video.publisher)
                    }
                    .riseIn(order: index % 12, animated: fresh)
            }
        }
    }
}

private struct VideoTile: View {
    let video: VideoItem
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                AspectBox(aspect: 16 / 9, maxHeight: 400) {
                    ZStack(alignment: .bottomTrailing) {
                        Rectangle().fill(Theme.hover)
                        if let still = video.still {
                            FillImage(candidates: [still])
                                .scaleEffect(hovering ? 1.03 : 1)
                        }
                        Icon(.play, size: 17)
                            .foregroundStyle(Color.white)
                            .offset(x: 1)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .scaleEffect(hovering ? 1.08 : 1)
                            .opacity(hovering ? 1 : 0.85)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let duration = video.duration {
                            Text(duration)
                                .font(.system(size: 11.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 6)
                                .frame(height: 20)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.72)))
                                .padding(8)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        ResultIcon(host: video.url.host ?? "", size: 12)
                        Text(video.uploader ?? video.publisher ?? video.url.host ?? "")
                            .lineLimit(1)
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    if let line = statsLine {
                        Text(line)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.3), value: hovering)
        .accessibilityElement(children: .combine)
    }

    /// "420K views · 3 days ago".
    private var statsLine: String? {
        var parts: [String] = []
        if let views = video.views, views > 0 {
            parts.append(String(localized: "\(views.formatted(.number.notation(.compactName))) views"))
        }
        if let published = video.published {
            parts.append(ResultDate.label(published, isDay: false))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct VideoGridSkeleton: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 248, maximum: 420), spacing: 20, alignment: .top)],
                  alignment: .leading, spacing: 28) {
            ForEach(0..<6, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    AspectBox(aspect: 16 / 9, maxHeight: 400) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.hover)
                    }
                    SkeletonBar(width: 0.9, height: 12, delay: Double(index) * 0.06)
                    SkeletonBar(width: 0.5, height: 9, delay: Double(index) * 0.06 + 0.05)
                }
            }
        }
    }
}

/// When and how long, above the grid.
private struct VideoFilterBar: View {
    let search: GrokSearch

    private var filters: VideoFilters { search.videoFilters }

    var body: some View {
        HStack(spacing: 6) {
            ChoiceMenu(icon: .clock, options: [SearchTime.any, .day, .week, .month], selected: filters.time,
                       label: \.title) { var next = filters; next.time = $0; search.setVideoFilters(next) }
            ChoiceMenu(options: VideoFilters.Length.allCases, selected: filters.length, label: \.title) {
                var next = filters; next.length = $0; search.setVideoFilters(next)
            }
            if !filters.isDefault {
                Button("Clear") { withAnimation(Motion.smooth) { search.setVideoFilters(VideoFilters()) } }
                    .pill(.ghost, size: .mini)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Spacer(minLength: 0)
        }
        .animation(Motion.smooth, value: filters)
    }

}
