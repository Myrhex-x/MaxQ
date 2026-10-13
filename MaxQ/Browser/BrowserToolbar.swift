//
//  BrowserToolbar.swift
//  Max Q
//
//  The row above the page, quiet like grok.com's top bar: round ghost buttons, the address pill
//  (Grokipedia's header search), page actions behind SpaceXAI-style menus, and the Grok button,
//  shaped like grok.com's "Imagine" link. Its empty space drags the window.
//

import AppKit
import SwiftUI

struct BrowserToolbar: View {
    @Bindable var browser: BrowserModel
    var addressFocus: FocusState<Bool>.Binding

    @State private var shareAnchor = ScreenAnchor()

    private var tab: BrowserTab? { browser.selectedTab }
    private var onPage: Bool { !(tab?.isHome ?? true) }

    var body: some View {
        HStack(spacing: 2) {
            if browser.sidebarVisible && browser.sidebarMode == .compact {
                // The compact rail is narrower than the traffic lights above it.
                Color.clear.frame(width: 18, height: 1)
            }
            if !browser.sidebarVisible {
                // Room for the window's traffic lights.
                Color.clear.frame(width: 74, height: 1)
                Button {
                    withAnimation(Motion.smooth) { browser.sidebarVisible = true }
                } label: { Icon(.sidebar, size: 18) }
                    .iconButton(size: 32)
                    .tip("Show sidebar", shortcut: "⌃⌘S")
                    .accessibilityLabel("Show Sidebar")
                    .padding(.trailing, 4)
            }

            Button { tab?.goBack() } label: { Icon(.chevronLeft, size: 18) }
                .iconButton(size: 32)
                .disabled(!(tab?.canGoBack ?? false))
                .tip("Back", shortcut: "⌘[")
                .accessibilityLabel("Back")
            Button { tab?.goForward() } label: { Icon(.chevronRight, size: 18) }
                .iconButton(size: 32)
                .disabled(!(tab?.canGoForward ?? false))
                .tip("Forward", shortcut: "⌘]")
                .accessibilityLabel("Forward")
            Button {
                if tab?.isLoading == true { tab?.stopLoading() } else { tab?.reload() }
            } label: {
                ZStack {
                    if tab?.isLoading == true {
                        Icon(.close, size: 16).transition(.iconSwap)
                    } else {
                        Icon(.reload, size: 17).transition(.iconSwap)
                    }
                }
                .animation(Motion.spring(0.42), value: tab?.isLoading == true)
            }
            .iconButton(size: 32)
            .disabled(!onPage)
            .tip(tab?.isLoading == true ? "Stop" : "Reload", shortcut: tab?.isLoading == true ? "⌘." : "⌘R")
            .accessibilityLabel(tab?.isLoading == true ? "Stop" : "Reload")

            if onPage {
                AddressField(browser: browser, focus: addressFocus)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .top) {
                        if !browser.suggestions.isEmpty && addressFocus.wrappedValue {
                            SuggestionsPanel(browser: browser, maxWidth: 680)
                                .padding(.horizontal, 12)
                                .offset(y: 44)
                                .transition(.pop(anchor: .top, scale: 0.985))
                        }
                    }
                    .animation(Motion.decelerate(0.2), value: browser.suggestions.isEmpty)
            } else {
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
            }

            if onPage, tab?.nativeSearch == nil {
                pageActions
                    .transition(.opacity)
            } else if let query = tab?.nativeSearch, !browser.isPrivate {
                FollowButton(query: query, browser: browser)
                    .transition(.opacity)
            }

            grokButton
                .padding(.leading, 6)
        }
        .padding(.horizontal, 8)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .onTapGesture(count: 2) { browser.window?.zoom(nil) }
        }
    }

    // MARK: - Page actions

    @ViewBuilder
    private var pageActions: some View {
        if let tab, case .translating(let done, let total) = tab.translation {
            HStack(spacing: 8) {
                ShimmerText(text: String(localized: "Translating \(min(done + 1, total)) of \(total)"), font: .system(size: 13, weight: .medium))
                Button("Stop") { browser.translator.toggle(tab) }
                    .pill(.ghost, size: .mini)
            }
            .padding(.horizontal, 6)
            .transition(.blurFade())
        } else if let tab, tab.translation == .translated {
            Button("Show original") { browser.translator.toggle(tab) }
                .pill(.secondary, size: .mini)
                .tip("Restore the page's own text")
                .padding(.horizontal, 4)
                .transition(.blurFade())
        }

        if let tab {
            TrackerShield(browser: browser, tab: tab)
        }

        if let tab, tab.readerAvailable || tab.reader != nil {
            Button { browser.toggleReader() } label: { Icon(.book, size: 17) }
                .iconButton(size: 32, active: tab.reader != nil)
                .tip(tab.reader == nil ? "Reader" : "Original page", shortcut: "⇧⌘R")
                .accessibilityLabel(tab.reader == nil ? "Show Reader" : "Hide Reader")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        if let tab, tab.media.video, let webView = tab.webView {
            Button {
                Task {
                    if await MediaScript.pictureInPicture(in: webView) {
                        browser.showToast(String(localized: "Click Float video, on the video, to float it over your other windows."))
                    } else {
                        browser.showToast(String(localized: "This page has no video to float."))
                    }
                }
            } label: { Icon(.pip, size: 17) }
            .iconButton(size: 32)
            .tip("Picture in picture")
            .accessibilityLabel("Picture in Picture")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        if browser.onVideoPage {
            Button { browser.askAboutVideo() } label: { Icon(.play, size: 16) }
                .iconButton(size: 32)
                .tip("Ask Grok about this video")
                .accessibilityLabel("Ask Grok About This Video")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        Button { browser.whatXSays() } label: { Icon(.bubble, size: 18) }
            .iconButton(size: 32)
            .tip("What X is saying about this page", shortcut: "⌥⌘X")
            .accessibilityLabel("What is X saying about this page")

        MenuButton(placement: .below(.trailing)) { _ in
            Icon(.share, size: 18)
        } content: {
            MenuCard(width: 230) {
                MenuRow(icon: .compose, title: "Share on X") { browser.shareToX() }
                MenuRow(icon: .envelope, title: "Send to Grok Bot") { browser.sendToBot() }
                MenuDivider()
                MenuRow(icon: .link, title: "Copy link") { browser.copyLink() }
                if let url = tab?.url {
                    MenuRow(icon: .share, title: "More…") { showSharePicker(for: url) }
                }
            }
        }
        .iconButton(size: 32)
        .screenAnchor(shareAnchor)
        .tip("Share")
        .accessibilityLabel("Share")

        MenuButton(placement: .below(.trailing)) { isOpen in
            // The three dots stretch into a cross while the menu is open.
            MorphIcon(isOpen ? .close : .more, size: 18)
        } content: {
            MenuCard(width: 236) {
                MenuRow(icon: .lines, title: "Summarize page") { browser.summarizeCurrentPage() }
                MenuRow(icon: .translate, title: tab?.translation == .translated ? "Show original" : "Translate page") {
                    if let tab { browser.translator.toggle(tab) }
                }
                MenuDivider()
                MenuRow(icon: .search, title: "Find on page", shortcut: "⌘F") { browser.showFindBar() }
                MenuRow(icon: .zoomIn, title: "Zoom in", shortcut: "⌘+") { browser.zoom(0.1) }
                MenuRow(icon: .zoomOut, title: "Zoom out", shortcut: "⌘−") { browser.zoom(-0.1) }
                MenuRow(icon: .doc, title: "Actual size", shortcut: "⌘0") { browser.zoom(nil) }
            }
        }
        .iconButton(size: 32)
        .tip("More")
        .accessibilityLabel("More Page Actions")
    }

    private func showSharePicker(for url: URL) {
        guard let view = shareAnchor.anchorView else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private var grokButton: some View {
        Button {
            withAnimation(Motion.smooth) { browser.toggleGrokPanel() }
        } label: {
            Text("Grok")
                .fontWeight(.semibold)
        }
        .pill(browser.grokPanelVisible ? .secondary : .ghost, size: .small)
        .tip(browser.grokPanelVisible ? "Hide Grok" : "Ask Grok", shortcut: "⌘J")
        .accessibilityLabel(browser.grokPanelVisible ? "Hide Grok" : "Show Grok")
    }
}

/// The shield: the trackers this page tried to load and Max Q stopped, as a count on the glyph,
/// and the switch that lets them through on this site.
private struct TrackerShield: View {
    @Bindable var browser: BrowserModel
    @Bindable var tab: BrowserTab
    @State private var settings = AppSettings.shared

    private var blocker: TrackerBlocker { TrackerBlocker.shared }
    private var allowed: Bool { blocker.isAllowed(tab.url?.host) }
    private var blocking: Bool { settings.blockTrackers && !allowed }
    private var site: String { TrackerBlocker.site(tab.url?.host) ?? String(localized: "this site") }

    var body: some View {
        MenuButton(placement: .below(.trailing)) { _ in
            Icon(blocking ? .shield : .shieldOff, size: 18)
                .overlay(alignment: .topTrailing) {
                    if blocking, !tab.trackers.isEmpty {
                        Text("\(tab.trackers.count)")
                            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.onInk)
                            .contentTransition(.numericText())
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Capsule().fill(Theme.ink))
                            .offset(x: 8, y: -7)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(Motion.pop, value: tab.trackers.isEmpty)
                .animation(Motion.snappy, value: tab.trackers.count)
        } content: {
            MenuCard(width: 300) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(blocking ? "Trackers blocked on \(site)" : "Trackers on \(site)")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .menuWrapping()
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, tab.trackers.isEmpty ? 8 : 4)
                ForEach(tab.trackers.prefix(tab.trackers.count > 10 ? 8 : 10), id: \.self) { company in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(blocking ? Theme.textTertiary : Theme.warning)
                            .frame(width: 5, height: 5)
                        Text(company)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                }
                if tab.trackers.count > 10 {
                    Text("and \(tab.trackers.count - 8) more")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                }
                MenuDivider()
                if settings.blockTrackers {
                    MenuRow(icon: allowed ? .shield : .shieldOff,
                            title: allowed ? "Block trackers here" : "Let trackers through here",
                            detail: "On \(site), and reloads the page") {
                        blocker.setAllowed(!allowed, for: tab.url?.host)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { tab.reload() }
                    }
                } else {
                    MenuRow(icon: .shield, title: "Block trackers everywhere", detail: "Turned off in Settings") {
                        settings.blockTrackers = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { tab.reload() }
                    }
                }
            }
        }
        .iconButton(size: 32)
        .tip(verbatim: tip)
        .accessibilityLabel(tip)
    }

    private var summary: String {
        if !settings.blockTrackers { return String(localized: "Tracker blocking is off.") }
        if allowed { return String(localized: "You let trackers through on this site.") }
        if tab.trackers.isEmpty { return String(localized: "None of the trackers on Max Q's list so far.") }
        return tab.trackers.count == 1 ? String(localized: "1 company kept from following you here.")
            : String(localized: "\(tab.trackers.count) companies kept from following you here.")
    }

    private var tip: String {
        guard blocking else { return String(localized: "Trackers allowed on this site") }
        return switch tab.trackers.count {
        case 0: String(localized: "No trackers blocked")
        case 1: String(localized: "1 tracker blocked")
        default: String(localized: "\(tab.trackers.count) trackers blocked")
        }
    }
}
