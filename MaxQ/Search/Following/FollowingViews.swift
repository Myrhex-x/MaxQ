//
//  FollowingViews.swift
//  Max Q
//
//  Where followed searches show: a section at the top of the sidebar (each search with how much
//  is new), the bell beside the address on a results page, and at the top of All, what's new
//  since the search was last opened.
//

import SwiftUI

// MARK: - Sidebar

/// The sidebar's Following section: one row per followed search, the count of what's new at its
/// end. A click opens the search; the menu on a row turns its notifications off or unfollows it.
struct FollowingSection: View {
    @Bindable var browser: BrowserModel
    @State private var store = FollowStore.shared
    @AppStorage("sidebarFollowingOpen") private var open = true

    var body: some View {
        if !store.searches.isEmpty, !browser.isPrivate {
            VStack(alignment: .leading, spacing: 1) {
                Button { withAnimation(Motion.smooth) { open.toggle() } } label: {
                    HStack(spacing: 6) {
                        SectionLabel("Following", trailing: store.newCount > 0 ? "\(store.newCount) new" : nil)
                        MorphChevron(open: open, size: 10)
                            .foregroundStyle(Theme.textQuaternary)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    ForEach(store.searches) { search in
                        FollowRow(search: search, checking: store.checking == search.id) {
                            browser.openMaxQSearch(search.query, on: search.fresh.contains { $0.kind == .news } ? .news : .all)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .padding(.bottom, 12)
            .animation(Motion.smooth, value: store.searches.map(\.id))
        }
    }
}

private struct FollowRow: View {
    let search: FollowedSearch
    let checking: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Icon(search.fresh.isEmpty ? .bell : .bellFill, size: 17)
                    .foregroundStyle(hovering || !search.fresh.isEmpty ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .opacity(checking ? 0.5 : 1)
                Text(search.query)
                    .font(.system(size: 14, weight: search.fresh.isEmpty ? .regular : .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !search.fresh.isEmpty {
                    Text("\(search.fresh.count)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.onInk)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Theme.ink))
                        .contentTransition(.numericText())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.smooth, value: search.fresh.count)
        .help(lastLook)
        .contextMenu {
            Button(search.notify ? "Turn Off Notifications" : "Notify Me About News") {
                FollowStore.shared.setNotify(search.id, !search.notify)
            }
            Button("Look Again Now") { Task { await FollowStore.shared.check(search.id) } }
            Divider()
            Button("Unfollow") { withAnimation(Motion.smooth) { FollowStore.shared.unfollow(search.query) } }
        }
        .accessibilityLabel(search.fresh.isEmpty ? search.query : String(localized: "\(search.query), \(search.fresh.count) new"))
    }

    private var lastLook: String {
        guard let date = search.lastChecked else { return String(localized: "Not looked at yet") }
        return String(localized: "Looked \(ResultDate.label(date, isDay: false))")
    }
}

// MARK: - The bell

/// Beside the address on a results page: follow the search (the bell fills), or stop.
struct FollowButton: View {
    let query: String
    @Bindable var browser: BrowserModel
    @State private var store = FollowStore.shared

    var body: some View {
        let following = store.isFollowing(query)
        Button {
            withAnimation(Motion.pop) { store.toggle(query) }
            browser.showToast(following ? String(localized: "Stopped following “\(query)”.")
                              : String(localized: "Following “\(query)”. New stories show in the sidebar."))
        } label: {
            Icon(following ? .bellFill : .bell, size: 18)
                .scaleEffect(following ? 1.04 : 1)
        }
        .iconButton(size: 32, active: following)
        .tip(following ? "Stop following this search" : "Follow this search")
        .accessibilityLabel(following ? "Stop Following This Search" : "Follow This Search")
    }
}

// MARK: - On the results page

/// At the top of All for a followed search: what came in since it was last opened.
struct SinceLastVisit: View {
    let items: [FollowItem]
    let since: Date?
    @Bindable var browser: BrowserModel
    @State private var expanded = false

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Icon(.bellFill, size: 14)
                    Text(since.map { String(localized: "New since \(ResultDate.label($0, isDay: false))") } ?? String(localized: "New since your last look"))
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(items.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items.prefix(expanded ? 20 : 4)) { item in
                        SinceRow(item: item) {
                            if let url = URL(string: item.url) { openFromResults(url, browser: browser) }
                        }
                    }
                }
                if items.count > 4 {
                    Button(expanded ? String(localized: "Show less") : String(localized: "Show all \(items.count)")) {
                        withAnimation(Motion.smooth) { expanded.toggle() }
                    }
                    .pill(.ghost, size: .mini)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .padding(.bottom, 22)
            .transition(.rise)
        }
    }
}

private struct SinceRow: View {
    let item: FollowItem
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Icon(item.kind == .news ? .doc : .bubble, size: 13)
                    .foregroundStyle(Theme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(item.source)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}
