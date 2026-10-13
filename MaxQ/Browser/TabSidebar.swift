//
//  TabSidebar.swift
//  Max Q
//
//  The sidebar, laid out like grok.com's: it sits straight on the window with no card around it.
//  At the top, SpaceXAI's sites as pinned tiles, each a tab of its own that stays put; then a
//  search row and the tabs as single-line rows whose highlight glides from tab to tab; at the foot,
//  the user's name, opening grok.com's account menu (theme switch, Settings, private window).
//  Compact mode is a slim rail of icons with tooltips.
//

import SwiftUI
import UniformTypeIdentifiers

struct TabSidebar: View {
    @Bindable var browser: BrowserModel
    @Namespace private var selection
    @State private var draggingID: UUID?
    @State private var searching = false
    @FocusState private var filterFocused: Bool

    private var compact: Bool { browser.sidebarMode == .compact }

    var body: some View {
        VStack(spacing: 0) {
            header
            if compact {
                CompactRail(browser: browser, selection: selection)
            } else {
                expanded
                    .transition(.opacity)
            }
            if !compact {
                NowPlayingCard(browser: browser)
            }
            SidebarFooter(browser: browser, compact: compact)
        }
        .animation(Motion.smooth, value: browser.sidebarMode)
        .animation(Motion.smooth, value: browser.allTabs.map { $0.media.isActive })
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 2) {
            // The window's traffic lights sit here.
            Color.clear.frame(width: compact ? 0 : 74, height: 1)
            Spacer(minLength: 0)
            if !compact {
                Button {
                    withAnimation(Motion.smooth) { browser.sidebarMode = .compact }
                } label: { Icon(.sidebar, size: 18) }
                    .iconButton(size: 32)
                    .tip("Collapse sidebar")
                    .accessibilityLabel("Collapse Sidebar")
                Button { browser.newTab() } label: { Icon(.compose, size: 18) }
                    .iconButton(size: 32)
                    .tip("New tab", shortcut: "⌘T")
                    .accessibilityLabel("New Tab")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .padding(.top, compact ? 26 : 0)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    // MARK: Expanded

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 0) {
            if browser.isPrivate {
                HStack(spacing: 8) {
                    GhostMark(size: 18)
                    Text("Private window")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.privateTint)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            PinnedTiles(browser: browser)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 10)

            searchRow
                .padding(.horizontal, 8)

            FollowingSection(browser: browser)
                .padding(.horizontal, 8)
                .padding(.top, 14)

            CollectionsSection(browser: browser)
                .padding(.horizontal, 8)

            HStack(spacing: 6) {
                SectionLabel("Tabs", trailing: "\(browser.tabs.count)")
                Spacer()
                if browser.tabs.count > 1 {
                    MenuButton(placement: .below(.trailing)) { _ in
                        Icon(.more, size: 16)
                    } content: {
                        MenuCard(width: 230) {
                            MenuRow(icon: .stack, title: "Tidy Tabs Into Groups",
                                    detail: OnDevice.isAvailable ? "By topic, on this Mac" : "By site") { browser.tidyTabs() }
                            if !browser.groups.isEmpty {
                                MenuRow(icon: .lines, title: "Ungroup All Tabs") { browser.ungroupAll() }
                            }
                            MenuDivider()
                            MenuRow(icon: .close, title: "Close Other Tabs") {
                                if let tab = browser.selectedTab { browser.closeOtherTabs(except: tab) }
                            }
                            MenuRow(icon: .reload, title: "Reopen Closed Tab", shortcut: "⇧⌘T",
                                    enabled: browser.canReopenClosedTab) { browser.reopenClosedTab() }
                        }
                    }
                    .iconButton(size: 26)
                    .tip("Tab actions")
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.top, 18)
            .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    ForEach(browser.looseTabs) { tab in
                        tabRow(tab)
                    }
                    ForEach(browser.groups) { group in
                        GroupHeader(browser: browser, group: group, count: browser.tabs(in: group).count)
                            .padding(.top, 6)
                        if !group.collapsed {
                            ForEach(browser.tabs(in: group)) { tab in
                                tabRow(tab)
                                    .padding(.leading, 10)
                            }
                        }
                    }
                    if browser.tabFilter.isEmpty {
                        newTabRow
                    } else if browser.visibleTabs.isEmpty {
                        Text("No tabs match “\(browser.tabFilter)”")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
                .animation(Motion.smooth, value: browser.tabs.map(\.id))
                .animation(Motion.glide, value: browser.selectedTabID)
            }
            .scrollEdgeFade()
        }
    }

    private func tabRow(_ tab: BrowserTab) -> some View {
        TabRow(browser: browser, tab: tab, isSelected: tab.id == browser.selectedTabID,
               selectionNamespace: selection)
            .onDrag {
                browser.peek = nil
                draggingID = tab.id
                return NSItemProvider(object: tab.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: TabDropDelegate(target: tab, browser: browser, draggingID: $draggingID))
            .transition(.asymmetric(insertion: .rise, removal: .opacity.combined(with: .scale(scale: 0.97))))
    }

    /// grok.com's "Search" row. Clicking it turns the row into the field in place.
    private var searchRow: some View {
        ZStack {
            if searching || !browser.tabFilter.isEmpty {
                HStack(spacing: 10) {
                    Icon(.search, size: 18)
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Search tabs", text: $browser.tabFilter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($filterFocused)
                        .onSubmit {
                            if let first = browser.visibleTabs.first { browser.select(first) }
                        }
                        .onKeyPress(.escape) {
                            closeSearch()
                            return .handled
                        }
                    Button { closeSearch() } label: { Icon(.close, size: 14) }
                        .iconButton(size: 22)
                        .accessibilityLabel("Clear Search")
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.input))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
            } else {
                SidebarNavRow(title: String(localized: "Search tabs"), shortcut: nil) {
                    Icon(.search, size: 18)
                } action: {
                    withAnimation(Motion.snappy) { searching = true }
                    DispatchQueue.main.async { filterFocused = true }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: filterFocused) { _, focused in
            if !focused && browser.tabFilter.isEmpty { withAnimation(Motion.snappy) { searching = false } }
        }
    }

    private func closeSearch() {
        browser.tabFilter = ""
        filterFocused = false
        withAnimation(Motion.snappy) { searching = false }
    }

    private var newTabRow: some View {
        SidebarNavRow(title: String(localized: "New tab"), shortcut: "⌘T", muted: true) {
            Icon(.plus, size: 16)
        } action: {
            browser.newTab()
        }
    }
}

// MARK: - Rows

/// A grok.com sidebar row: icon, label, a veil on hover.
struct SidebarNavRow<Glyph: View>: View {
    let title: String
    var shortcut: String? = nil
    var muted = false
    var trailing: AnyView? = nil
    @ViewBuilder var glyph: Glyph
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                glyph
                    .frame(width: 20, height: 20)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                    .scaleEffect(hovering ? 1.08 : 1)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(muted && !hovering ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let trailing { trailing }
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textQuaternary)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

struct TabRow: View {
    @Bindable var browser: BrowserModel
    @Bindable var tab: BrowserTab
    let isSelected: Bool
    let selectionNamespace: Namespace.ID

    @State private var hovering = false
    @State private var frame: CGRect = .zero
    @State private var peekTask: Task<Void, Never>?

    /// Half of a split view.
    private var inSplit: Bool { browser.split?.contains(tab.id) == true }
    /// The other half of the split on screen: it shares the selection, quieter.
    private var inSplitOnScreen: Bool { !isSelected && browser.activeSplit?.contains(tab.id) == true }

    var body: some View {
        HStack(spacing: 10) {
            TabIcon(tab: tab, size: 16)
                .frame(width: 20, height: 20)

            title
                .frame(maxWidth: .infinity, alignment: .leading)
                // grok.com fades a row's title out under its actions on hover.
                .mask(
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: hovering ? 0.72 : 0.94),
                        .init(color: .black.opacity(hovering ? 0 : 1), location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                )

            if tab.isUsingCamera || tab.isUsingMicrophone {
                Icon(tab.isUsingCamera ? .video : .mic, size: 14)
                    .foregroundStyle(Theme.danger)
                    .tip(tab.isUsingCamera ? "This page is using your camera" : "This page is using your microphone")
            }

            if tab.media.playing, let webView = tab.webView {
                // Playing: a click mutes it (or brings the sound back).
                Button { Task { await MediaScript.setMuted(!tab.media.muted, in: webView) } } label: {
                    Icon(tab.media.muted ? .speakerOff : .speaker, size: 14)
                }
                .iconButton(size: 22)
                .tip(tab.media.muted ? "Unmute this tab" : "Mute this tab")
                .accessibilityLabel(tab.media.muted ? "Unmute \(tab.displayTitle)" : "Mute \(tab.displayTitle)")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            if hovering {
                Button { browser.closeTab(tab) } label: { Icon(.close, size: 14) }
                    .iconButton(size: 24)
                    .tip("Close tab", shortcut: "⌘W")
                    .accessibilityLabel("Close \(tab.displayTitle)")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.selected)
                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
            } else if hovering || inSplitOnScreen {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.hover)
            }
        }
        .overlay(alignment: .trailing) {
            if inSplit, !hovering {
                Icon(.splitView, size: 13)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.trailing, 10)
                    .transition(.opacity)
                    .tip("In split view")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            cancelPeek()
            browser.select(tab)
        }
        .onHover { inside in
            hovering = inside
            if inside { schedulePeek() } else { cancelPeek() }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onDisappear { cancelPeek() }
        .animation(Motion.hover, value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityHint(tab.url?.absoluteString ?? "")
        .contextMenu { TabContextMenu(browser: browser, tab: tab) }
    }

    @ViewBuilder
    private var title: some View {
        let text = tab.searchQuery ?? tab.displayTitle
        if tab.isLoading {
            ShimmerText(text: text, font: .system(size: 14), base: Theme.textTertiary, peak: Theme.textPrimary)
                .lineLimit(1)
        } else {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(isSelected || hovering ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
        }
    }

    /// Previews appear after a short rest on a row, or at once while one is already showing.
    private func schedulePeek() {
        peekTask?.cancel()
        guard !isSelected, !tab.isHome else { return }
        let warm = browser.peek != nil
        peekTask = Task {
            if !warm { try? await Task.sleep(for: .milliseconds(600)) }
            guard !Task.isCancelled, hovering else { return }
            browser.showPeek(tab, anchor: frame)
        }
    }

    private func cancelPeek() {
        peekTask?.cancel()
        peekTask = nil
        let id = tab.id
        // A short grace period, so sliding to the next row doesn't flicker the preview away.
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            if !hovering { browser.hidePeek(id) }
        }
    }
}

/// The hover preview: the page as it last looked, its title and site.
struct TabPeekCard: View {
    @Bindable var tab: BrowserTab
    static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot = tab.snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.width - 12, height: 168, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    .padding(6)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    TabIcon(tab: tab, size: 12)
                        .frame(width: 14, height: 14)
                    Text(site)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if tab.isLoading {
                        ShimmerText(text: String(localized: "Loading"), font: .system(size: 12))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, tab.snapshot == nil ? 12 : 4)
            .padding(.bottom, 12)
        }
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
    }

    private var site: String {
        if let query = tab.nativeSearch { return String(localized: "Max Q · \(query)") }
        if let query = tab.searchQuery, let host = tab.url?.host {
            return "\(host.replacingOccurrences(of: "www.", with: "")) · \(query)"
        }
        return tab.url.map { AddressSuggestion.displayURL($0) } ?? ""
    }
}

// MARK: - Compact rail

private struct CompactRail: View {
    @Bindable var browser: BrowserModel
    let selection: Namespace.ID

    var body: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(Motion.smooth) { browser.sidebarMode = .expanded }
            } label: { Icon(.sidebar, size: 18) }
                .iconButton(size: 36)
                .tip("Expand sidebar", placement: .trailing)
                .accessibilityLabel("Expand Sidebar")
            Button { browser.newTab() } label: { Icon(.compose, size: 18) }
                .iconButton(size: 36)
                .tip("New tab", shortcut: "⌘T", placement: .trailing)
                .accessibilityLabel("New Tab")

            Rectangle().fill(Theme.hairline).frame(width: 24, height: 1).padding(.vertical, 6)

            PinnedTiles(browser: browser, vertical: true)

            Rectangle().fill(Theme.hairline).frame(width: 24, height: 1).padding(.vertical, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(browser.tabs) { tab in
                        CompactTabTile(browser: browser, tab: tab, isSelected: tab.id == browser.selectedTabID,
                                       selectionNamespace: selection)
                    }
                }
                .padding(.vertical, 2)
                .animation(Motion.glide, value: browser.selectedTabID)
            }
            .scrollEdgeFade()
        }
        .frame(maxWidth: .infinity)
        // grok.com's collapsed sidebar: its icons settle in from 8 points low, out of a blur.
        .transition(.settle)
    }
}

struct CompactTabTile: View {
    @Bindable var browser: BrowserModel
    @Bindable var tab: BrowserTab
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    @State private var hovering = false
    @State private var frame: CGRect = .zero
    @State private var peekTask: Task<Void, Never>?

    var body: some View {
        TabIcon(tab: tab, size: 17)
            .frame(width: 36, height: 36)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.selected)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.hover)
                }
            }
            .opacity(tab.isLoading ? 0.6 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                peekTask?.cancel()
                browser.select(tab)
            }
            .onHover { inside in
                hovering = inside
                peekTask?.cancel()
                if inside, !isSelected, !tab.isHome {
                    let warm = browser.peek != nil
                    peekTask = Task {
                        if !warm { try? await Task.sleep(for: .milliseconds(600)) }
                        guard !Task.isCancelled, hovering else { return }
                        browser.showPeek(tab, anchor: frame)
                    }
                } else if !inside {
                    let id = tab.id
                    Task {
                        try? await Task.sleep(for: .milliseconds(90))
                        if !hovering { browser.hidePeek(id) }
                    }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .animation(Motion.hover, value: hovering)
            .accessibilityLabel(tab.displayTitle)
            .contextMenu { TabContextMenu(browser: browser, tab: tab) }
    }
}

// MARK: - Footer

/// grok.com's account row: the user's name and initial; it opens the account menu.
private struct SidebarFooter: View {
    @Bindable var browser: BrowserModel
    let compact: Bool

    var body: some View {
        ProfileMenuButton(browser: browser, compact: compact)
            .padding(.horizontal, compact ? 0 : 8)
            .padding(.top, 6)
            .padding(.bottom, compact ? 12 : 10)
    }
}

/// The name the user chose in setup, with their initial in a round avatar. Clicking it opens
/// grok.com's account menu upward: who's signed in and how Grok is connected, the theme switch,
/// Settings, a private window and the sidebar toggle.
struct ProfileMenuButton: View {
    @Bindable var browser: BrowserModel
    var compact = false
    @State private var settings = AppSettings.shared
    @State private var hovering = false

    var body: some View {
        MenuButton(placement: .above(.leading)) { isOpen in
            if compact {
                ProfileAvatar(name: settings.name, size: 30)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(isOpen || hovering ? Theme.hover : .clear))
                    .contentShape(Circle())
            } else {
                HStack(spacing: 10) {
                    ProfileAvatar(name: settings.name, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(settings.name ?? "Max Q")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if !SpaceStore.shared.spaces.isEmpty, !browser.isPrivate {
                            // Which space the window shows, once there's more than one.
                            Text(SpaceStore.shared.name(of: browser.spaceID))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                                .contentTransition(.interpolate)
                        }
                    }
                    Spacer(minLength: 4)
                    Icon(.chevronUpDown, size: 14)
                        .foregroundStyle(Theme.textTertiary)
                        .opacity(isOpen || hovering ? 1 : 0)
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(isOpen ? Theme.selected : (hovering ? Theme.hover : .clear)))
                .contentShape(Rectangle())
            }
        } content: {
            ProfileMenu(browser: browser)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .modifier(CompactTip(enabled: compact, text: settings.name ?? String(localized: "Account")))
        .accessibilityLabel(settings.name.map { "\($0), account menu" } ?? "Account menu")
    }
}

private struct CompactTip: ViewModifier {
    let enabled: Bool
    let text: String

    func body(content: Content) -> some View {
        if enabled { content.tip(verbatim: text, placement: .trailing) } else { content }
    }
}

/// The account menu's content.
private struct ProfileMenu: View {
    @Bindable var browser: BrowserModel
    @State private var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissPopover) private var dismissPopover
    private var webAccount: GrokWebAccount { GrokWebAccount.shared }
    private var account: GrokAccount { GrokAccount.shared }

    var body: some View {
        MenuCard(width: 272) {
            HStack(spacing: 12) {
                ProfileAvatar(name: settings.name, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.name ?? "Max Q")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if grokConnected {
                            Circle().fill(Theme.success).frame(width: 6, height: 6)
                        }
                        Text(grokLine)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ThemeSwitch()
                .padding(.bottom, 4)
            if !browser.isPrivate {
                MenuDivider()
                MenuSectionTitle("Spaces")
                MenuRow(icon: .house, verbatim: String(localized: "Personal"), checked: browser.spaceID == nil) {
                    browser.switchSpace(to: nil)
                }
                ForEach(SpaceStore.shared.spaces) { space in
                    MenuRow(icon: .stack, verbatim: space.name, checked: browser.spaceID == space.id) {
                        browser.switchSpace(to: space.id)
                    }
                }
                MenuRow(icon: .plus, title: "New space…") { browser.newSpace() }
                if browser.spaceID != nil {
                    MenuRow(icon: .trash, title: "Delete this space…", destructive: true) { browser.deleteCurrentSpace() }
                }
            }
            MenuDivider()
            MenuRow(icon: .gear, title: "Settings", shortcut: "⌘,") { openSettings() }
            if !browser.isPrivate {
                MenuRow(icon: .ghost, title: "New private window", shortcut: "⇧⌘N") { openWindow(id: "private") }
            }
            MenuRow(icon: .sidebar, title: browser.sidebarMode == .compact ? "Expand sidebar" : "Collapse sidebar") {
                withAnimation(Motion.smooth) { browser.sidebarMode = browser.sidebarMode == .compact ? .expanded : .compact }
            }
            if !grokConnected {
                MenuDivider()
                MenuRow(icon: .link, title: "Connect Grok") {
                    withAnimation(Motion.smooth) { browser.grokPanelVisible = true }
                }
            }
        }
    }

    private var grokConnected: Bool {
        if account.hasKey, account.status != .none {
            // A rejected key isn't a connection.
            if case .invalid = account.status { return webAccount.isSignedIn }
            return true
        }
        return webAccount.isSignedIn
    }

    private var grokLine: String {
        if account.hasKey {
            if case .invalid = account.status { return String(localized: "Grok API key rejected") }
            return String(localized: "Grok with your API key")
        }
        return webAccount.isSignedIn ? String(localized: "Signed in to grok.com") : String(localized: "Grok isn't connected")
    }
}

/// A round avatar with the user's initial, in x.ai's black and white.
struct ProfileAvatar: View {
    let name: String?
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            if let initial = name?.first.map({ String($0).uppercased() }) {
                Circle().fill(Theme.ink)
                Text(initial)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Theme.onInk)
            } else {
                Circle().fill(Theme.hover)
                MaxQMark(size: size * 0.62, glow: false)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// grok.com's three-way theme switch (light, dark, system) with a gliding thumb.
struct ThemeSwitch: View {
    @State private var settings = AppSettings.shared
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            segment(.light, icon: .sun, label: String(localized: "Light"))
            segment(.dark, icon: .moon, label: String(localized: "Dark"))
            segment(.system, icon: .system, label: String(localized: "Match system"))
        }
        .padding(2)
    }

    private func segment(_ value: AppearancePreference, icon: MQIcon, label: String) -> some View {
        let selected = settings.appearance == value
        return Button {
            withAnimation(Motion.glide) { settings.appearance = value }
        } label: {
            Icon(icon, size: 18)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.selected)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Shared

private struct TabContextMenu: View {
    let browser: BrowserModel
    let tab: BrowserTab

    var body: some View {
        Button("Reload") { tab.reload() }.disabled(tab.isHome)
        Button("Duplicate") { browser.duplicate(tab) }.disabled(tab.url == nil)
        Button("Copy Link") {
            if let url = tab.url {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
        .disabled(tab.url == nil)
        Divider()
        if browser.split?.contains(tab.id) == true {
            Button("Swap Split Panes") { browser.swapSplit() }
            Button("Close Split View") { browser.closeSplit() }
        } else if let current = browser.selectedTab, current.id != tab.id, !tab.isHome {
            Button("Open Beside \(current.searchQuery ?? current.displayTitle)") { browser.splitView(with: tab) }
        }
        Divider()
        Button("Close Tab") { browser.closeTab(tab) }
        Button("Close Other Tabs") { browser.closeOtherTabs(except: tab) }.disabled(browser.tabs.count < 2)
    }
}

/// A tab group's header: its name and count; a click folds it, its menu renames, ungroups or
/// closes it.
private struct GroupHeader: View {
    @Bindable var browser: BrowserModel
    let group: TabGroup
    let count: Int
    @State private var hovering = false
    @State private var renaming = false
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            MorphChevron(open: !group.collapsed, size: 11)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 20)
            if renaming {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($focused)
                    .onSubmit { browser.renameGroup(group.id, to: name); renaming = false }
                    .onChange(of: focused) { _, on in if !on { browser.renameGroup(group.id, to: name); renaming = false } }
            } else {
                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Text("\(count)")
                .font(.mono(11, weight: .regular))
                .foregroundStyle(Theme.textQuaternary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { browser.toggleGroup(group.id) }
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .contextMenu {
            Button("Rename Group") {
                name = group.name
                renaming = true
                DispatchQueue.main.async { focused = true }
            }
            Button("Ungroup") { browser.ungroup(group.id) }
            Divider()
            Button("Close the Group's Tabs") { browser.closeGroup(group.id) }
        }
        .accessibilityLabel("\(group.name), \(count) tabs")
    }
}

/// Reorders tabs live while one is dragged over another.
private struct TabDropDelegate: DropDelegate {
    let target: BrowserTab
    let browser: BrowserModel
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let id = draggingID, id != target.id,
              let dragged = browser.tabs.first(where: { $0.id == id }) else { return }
        withAnimation(Motion.snappy) { browser.move(dragged, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

struct TabIcon: View {
    @Bindable var tab: BrowserTab
    var size: CGFloat = 16
    private var favicons: FaviconStore { FaviconStore.shared }

    var body: some View {
        if tab.isHome {
            MaxQMark(size: size + 2, glow: false)
        } else if tab.nativeSearch != nil || (tab.webView == nil && MaxQScheme.isNative(tab.url)) {
            // Grok's results page.
            Icon(.search, size: size)
                .foregroundStyle(Theme.textPrimary)
        } else if let image = favicons.icon(for: tab.host) {
            SiteIcon(image: image, tone: favicons.tone(for: tab.host), size: size, cornerRadius: size * 0.22)
        } else {
            Icon(.globe, size: size)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
