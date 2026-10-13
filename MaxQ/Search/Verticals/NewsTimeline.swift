//
//  NewsTimeline.swift
//  Max Q
//
//  The News tab's Timeline: everything on the search that carries a date, on one line, newest
//  first. News reports, web pages and the Grokipedia article each keep their own mark,
//  so the line shows how a subject unfolded and who said what when. Recent days are kept apart;
//  older entries are gathered by month.
//

import SwiftUI

/// One dated thing on the timeline.
struct TimelineEntry: Identifiable {
    enum Kind {
        case news(NewsItem)
        case web(WebResult)
        case article(GrokipediaCard)
    }

    let id: String
    let date: Date
    /// The date is a day, without a time.
    let isDay: Bool
    let kind: Kind

    var url: URL? {
        switch kind {
        case .news(let item): item.url
        case .web(let result): result.url
        case .article: nil
        }
    }

    /// Everything on `search` that has a date, newest first, each page once.
    @MainActor
    static func entries(for search: GrokSearch) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        var seen = Set<String>()
        for item in search.news.items {
            guard let date = item.date, seen.insert(item.url.citationKey).inserted else { continue }
            entries.append(TimelineEntry(id: "news:\(item.id)", date: date, isDay: false, kind: .news(item)))
        }
        for result in search.webResults {
            guard let date = result.date, seen.insert(result.url.citationKey).inserted else { continue }
            entries.append(TimelineEntry(id: "web:\(result.id)", date: date, isDay: result.dateIsDay, kind: .web(result)))
        }
        if case .ready(let card) = search.pad, let date = card.updated {
            entries.append(TimelineEntry(id: "article:\(card.articleURL)", date: date, isDay: true, kind: .article(card)))
        }
        return entries.sorted { $0.date > $1.date }
    }
}

struct NewsTimeline: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        let entries = TimelineEntry.entries(for: search)
        let groups = Self.groups(entries)
        VStack(alignment: .leading, spacing: 0) {
            summary(entries)
                .padding(.bottom, 18)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.title) { group in
                    Text(group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.leading, Self.timeColumn + Self.lineColumn)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                        TimelineRow(entry: entry, showsTime: !group.isMonth, last: index == group.entries.count - 1) {
                            open(entry)
                        }
                    }
                }
            }
        }
    }

    static let timeColumn: CGFloat = 54
    static let lineColumn: CGFloat = 22

    private func summary(_ entries: [TimelineEntry]) -> some View {
        let days = Set(entries.map { Calendar.current.startOfDay(for: $0.date) }).count
        return HStack(spacing: 8) {
            Icon(.calendar, size: 15)
                .foregroundStyle(Theme.textTertiary)
            Text(entries.isEmpty
                 ? String(localized: "Nothing dated yet. News and web pages join the line as they load.")
                 : String(localized: "\(entries.count) moments over \(days) days, from the news, the web, X and Grokipedia"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func open(_ entry: TimelineEntry) {
        if case .article = entry.kind {
            search.show(.grokipedia)
        } else if let url = entry.url {
            openFromResults(url, browser: browser)
        }
    }

    struct Group {
        let title: String
        let isMonth: Bool
        var entries: [TimelineEntry]
    }

    /// Days for the last month ("Today", "Yesterday", "Tuesday", "Oct 2"), then months.
    static func groups(_ entries: [TimelineEntry], now: Date = Date()) -> [Group] {
        let calendar = Calendar.current
        var groups: [Group] = []
        for entry in entries {
            let age = now.timeIntervalSince(entry.date)
            let isMonth = age > 31 * 86_400
            let title: String
            if isMonth {
                title = entry.date.formatted(.dateTime.month(.wide).year())
            } else if calendar.isDateInToday(entry.date) {
                title = String(localized: "Today")
            } else if calendar.isDateInYesterday(entry.date) {
                title = String(localized: "Yesterday")
            } else if age < 6 * 86_400 {
                title = entry.date.formatted(.dateTime.weekday(.wide))
            } else {
                title = entry.date.formatted(.dateTime.month(.abbreviated).day())
            }
            if groups.last?.title == title {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append(Group(title: title, isMonth: isMonth, entries: [entry]))
            }
        }
        return groups
    }
}

private struct TimelineRow: View {
    let entry: TimelineEntry
    let showsTime: Bool
    let last: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 0) {
                Text(showsTime && !entry.isDay ? entry.date.formatted(date: .omitted, time: .shortened) : "")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: NewsTimeline.timeColumn, alignment: .leading)
                    .padding(.top, 3)
                // The line, and this moment's dot on it.
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, last ? 12 : 0)
                    Circle()
                        .fill(hovering ? Theme.textPrimary : Theme.surface)
                        .overlay(Circle().strokeBorder(hovering ? Theme.textPrimary : Theme.textTertiary, lineWidth: 1.5))
                        .frame(width: 9, height: 9)
                        .padding(.top, 5)
                }
                .frame(width: NewsTimeline.lineColumn)
                content
                    .padding(.leading, 6)
                    .padding(.bottom, 16)
                Spacer(minLength: 0)
            }
            // As tall as the moment's text, so the line runs the whole height.
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Icon(icon, size: 12)
                Text(label)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var icon: MQIcon {
        switch entry.kind {
        case .news: .doc
        case .web: .globe
        case .article: .book
        }
    }

    private var label: String {
        switch entry.kind {
        case .news(let item): String(localized: "\(item.source.isEmpty ? item.host : item.source) · News")
        case .web(let result): result.host
        case .article: String(localized: "Grokipedia · Fact-checked by Grok")
        }
    }

    private var title: String {
        switch entry.kind {
        case .news(let item): item.title
        case .web(let result): result.title
        case .article(let card): card.title
        }
    }

    private var detail: String? {
        switch entry.kind {
        case .news(let item): item.excerpt
        case .web(let result): result.plainSnippet
        case .article(let card): card.summary
        }
    }
}
