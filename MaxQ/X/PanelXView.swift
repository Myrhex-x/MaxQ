//
//  PanelXView.swift
//  Max Q
//
//  "What is X saying about this page", in the side panel: x.com's own search, Latest first, for
//  posts that share the page on screen (or, one click away, that mention its title). It follows
//  the page: switch tabs or follow a link and the posts change with it. It runs in the user's own
//  X account and costs nothing; with an API key, Grok can sum the reactions up as well.
//

import SwiftUI

struct PanelXView: View {
    @Bindable var browser: BrowserModel
    @State private var byTitle = false

    private var pane: XSearchPane { browser.xPanelSearch }
    private var account: GrokAccount { browser.grokAccount }

    /// The page on screen, when there's one X could be talking about.
    private var page: (url: URL, title: String)? {
        guard let tab = browser.selectedTab, !tab.isHome, tab.nativeSearch == nil,
              let url = tab.url, url.scheme == "https" || url.scheme == "http" else { return nil }
        return (url, tab.title)
    }

    private var query: String? {
        guard let page else { return nil }
        if byTitle { return XLinks.titleQuery(for: page.title) }
        return XLinks.linkQuery(for: page.url)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let page {
                header(page)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ZStack(alignment: .top) {
                    XSearchHost(pane: pane, visible: true)
                        .opacity(pane.state == .ready ? 1 : 0)
                        .animation(Motion.standard(0.25), value: pane.state)
                    overlay
                }
                .frame(maxHeight: .infinity)
                if account.hasKey {
                    summarize
                }
            } else {
                empty
            }
        }
        .onAppear(perform: load)
        .onChange(of: query) { _, _ in load() }
        .animation(Motion.standard(0.25), value: pane.state)
    }

    private func load() {
        guard let query else { return }
        pane.show(query: query, latest: true)
    }

    // MARK: - Pieces

    private func header(_ page: (url: URL, title: String)) -> some View {
        HStack(spacing: 10) {
            ResultIcon(host: page.url.host ?? "", size: 16)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.hover))
            VStack(alignment: .leading, spacing: 1) {
                Text(byTitle ? "Posts mentioning this page" : "Posts sharing this page")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.interpolate)
                Text(page.title.isEmpty ? (page.url.host ?? "") : page.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            MatchPicker(byTitle: $byTitle)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .animation(Motion.snappy, value: byTitle)
    }

    @ViewBuilder
    private var overlay: some View {
        switch pane.state {
        case .needsSignIn:
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to X to see posts")
                    .font(.heading(17))
                    .foregroundStyle(Theme.textPrimary)
                Text("x.com searches for signed-in accounts. Sign in once in X's tile at the top of the sidebar.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Sign in to X") { browser.openPinned(.x) }
                    .pill(.primary, size: .small)
                    .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.blurFade())
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                Button("Try again") { pane.reload() }
                    .pill(.secondary, size: .small)
            }
            .padding(.top, 40)
            .transition(.opacity)
        case .loading, .idle:
            PanelPostsPlaceholder()
                .transition(.opacity)
        case .ready:
            EmptyView()
        }
    }

    /// With a key, Grok can read the posts and sum the reactions up.
    private var summarize: some View {
        let cost = account.typicalAnswerCost(AppSettings.shared.grokEffort, searchingX: true)
        return Button {
            browser.askGrokWhatXSays()
        } label: {
            HStack(spacing: 8) {
                Icon(.bubble, size: 15)
                Text("Sum up the reactions with Grok")
                Spacer(minLength: 6)
                Text(GrokAccount.friendlyCost(cost, approximate: true))
                    .foregroundStyle(Theme.textTertiary)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SummarizeBarStyle())
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What X is saying")
                .font(.heading(20))
                .tracking(-0.4)
                .foregroundStyle(Theme.textPrimary)
            Text("Open a page, and the posts that share it on X show up here, newest first.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Link or Title: what the posts are matched on, in a small segmented control.
private struct MatchPicker: View {
    @Binding var byTitle: Bool
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            segment(String(localized: "Link"), selected: !byTitle) { byTitle = false }
            segment(String(localized: "Title"), selected: byTitle) { byTitle = true }
        }
        .padding(2)
        .background(Capsule().fill(Theme.hover))
        .tip(byTitle ? "Posts that mention the page's title" : "Posts that share the page's link")
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.glide) { action() }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    if selected {
                        Capsule().fill(Theme.raised).elevation(.raised)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SummarizeBarStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SummarizeBar(configuration: configuration)
    }

    private struct SummarizeBar: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .background(configuration.isPressed ? Theme.selected : (hovering ? Theme.hover : .clear))
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hovering)
        }
    }
}

/// Outlines of posts, breathing, while x.com loads in the panel.
private struct PanelPostsPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Theme.selected).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBar(width: 0.45, height: 9, delay: Double(row) * 0.1)
                        SkeletonBar(width: 0.95, height: 9, delay: Double(row) * 0.1 + 0.05)
                        SkeletonBar(width: [0.7, 0.55, 0.8, 0.6][row], height: 9, delay: Double(row) * 0.1 + 0.1)
                    }
                    .padding(.top, 3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }
    }
}
