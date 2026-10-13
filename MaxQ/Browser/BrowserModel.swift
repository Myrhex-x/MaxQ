//
//  BrowserModel.swift
//  Max Q
//
//  Everything one browser window knows: its tabs, the address bar, the Grok panel, the
//  Grokipedia card, the find bar, downloads and toasts. Each window has its own model (and
//  private windows their own, non-persistent website data).
//

import AppKit
import Observation
import SwiftUI
import WebKit

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
}

/// The sidebar's hover preview: which tab, and where its row is in the window.
struct TabPeek: Equatable {
    let tabID: UUID
    let anchor: CGRect
}

struct BotHandoff: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

/// Two tabs side by side. The selected tab is the pane with the keyboard.
struct SplitPair: Equatable {
    var leading: UUID
    var trailing: UUID
    /// The leading pane's share of the width.
    var ratio: CGFloat = 0.5

    func contains(_ id: UUID?) -> Bool { id == leading || id == trailing }

    func partner(of id: UUID) -> UUID? {
        if id == leading { return trailing }
        if id == trailing { return leading }
        return nil
    }
}

/// Tabs kept together under a name in the sidebar.
struct TabGroup: Identifiable, Equatable {
    let id: UUID
    var name: String
    var collapsed = false
}

enum SidebarMode: String {
    /// Full sidebar: launchers, tab titles and sites.
    case expanded
    /// A slim rail of icons.
    case compact
}

@MainActor
@Observable
final class BrowserModel {
    let isPrivate: Bool
    /// The space the window shows (nil: Personal). Each space has its own sign-ins and tabs.
    private(set) var spaceID: UUID?
    @ObservationIgnored private(set) var websiteDataStore: WKWebsiteDataStore
    /// Bumped when the window moves to another space, so views holding its web views take the new ones.
    private(set) var spaceVersion = 0

    /// The tab list in the sidebar.
    var tabs: [BrowserTab] = []
    /// The pinned sites' own tabs (Grok, Grokipedia, X), kept outside the tab list: a tile at the
    /// top of the sidebar switches to its tab instead of opening another.
    private(set) var pinnedTabs: [Launcher: BrowserTab] = [:]
    var selectedTabID: UUID?

    var sidebarVisible = true
    var sidebarMode: SidebarMode = SidebarMode(rawValue: UserDefaults.standard.string(forKey: "sidebarMode") ?? "") ?? .expanded {
        didSet { UserDefaults.standard.set(sidebarMode.rawValue, forKey: "sidebarMode") }
    }
    /// Filters the sidebar's tab list.
    var tabFilter = ""
    var grokPanelVisible = false
    /// The panel shows what X is saying about the page on screen, instead of Grok.
    var panelShowsX = false
    /// The panel shows the agent, Grok doing a task in a tab.
    var panelShowsAgent = false
    /// Bringing bookmarks and history over from another browser.
    var showingImport = false
    /// Two tabs side by side, shown whenever one of them is selected.
    var split: SplitPair?
    var findBarVisible = false
    var findText = ""
    var toast: Toast?
    var botHandoff: BotHandoff?
    /// Asking for the Grok Bot's address, the first time its suggestion is picked in a form.
    var botEmailSetup: BotEmailSetup?
    /// The tab preview showing beside the sidebar, if any.
    var peek: TabPeek?
    /// The research sheet, when it's open.
    var researchDraft: ResearchDraft?
    /// Groups of tabs, in the order they show under the loose tabs.
    var groups: [TabGroup] = []
    /// Tabs are being sorted into groups.
    private(set) var tidying = false
    /// An answer being shared as a picture.
    var shareAnswer: ShareAnswerDraft?

    // Address bar
    var addressText = ""
    var addressFocused = false
    var suggestions: [AddressSuggestion] = []
    var suggestionIndex = 0
    /// Bumped to ask the view to move keyboard focus into the address bar.
    private(set) var focusAddressRequest = 0
    /// Bumped to ask the Grok panel to focus its composer.
    private(set) var composerFocusRequest = 0

    let grok = GrokSession()
    /// Grok doing a task in a tab.
    let agent = AgentSession()
    /// ⌘K.
    let commandBar = CommandBar()
    let translator = PageTranslator()
    let grokipedia = GrokipediaPanelModel()
    /// Searches run on Grok's own results page in this window.
    @ObservationIgnored let searches = GrokSearchStore()
    @ObservationIgnored let downloads = DownloadCoordinator()
    @ObservationIgnored let grokAccount = GrokAccount.shared
    @ObservationIgnored let settings = AppSettings.shared
    @ObservationIgnored private var grokWebPanelStorage: GrokWebPanel?
    @ObservationIgnored private var xSearchStorage: XSearchPane?
    @ObservationIgnored private var xPanelSearchStorage: XSearchPane?

    /// grok.com in the side panel, in this window's space.
    var grokWebPanel: GrokWebPanel {
        if let grokWebPanelStorage { return grokWebPanelStorage }
        let panel = GrokWebPanel(dataStore: websiteDataStore)
        panel.openInTab = { [weak self] url in self?.openInNewTab(url) }
        grokWebPanelStorage = panel
        return panel
    }
    /// x.com's live search, for the "Posts on X" tab of Grok's results pages in this window.
    var xSearch: XSearchPane {
        if let xSearchStorage { return xSearchStorage }
        let pane = XSearchPane(browser: self)
        xSearchStorage = pane
        return pane
    }
    /// x.com's search in the side panel, for the posts sharing the page on screen.
    var xPanelSearch: XSearchPane {
        if let xPanelSearchStorage { return xPanelSearchStorage }
        let pane = XSearchPane(browser: self)
        pane.linksOpenInNewTab = true
        xPanelSearchStorage = pane
        return pane
    }
    @ObservationIgnored weak var window: NSWindow?

    @ObservationIgnored private var recentlyClosed: [(url: URL, title: String)] = []
    /// The tab-list tab to come back to when a pinned tab is put away.
    @ObservationIgnored private var lastListTabID: UUID?
    @ObservationIgnored private var sessionRestored = false
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var externalPromptOpen = false

    @ObservationIgnored private let suggestionSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    init(isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        let space = isPrivate ? nil : SpaceStore.shared.lastUsed
        self.spaceID = space
        self.websiteDataStore = isPrivate ? .nonPersistent() : SpaceStore.shared.dataStore(for: space)
        grok.browser = self
        agent.browser = self
        commandBar.browser = self
        translator.browser = self
        downloads.browser = self
        searches.browser = self

        let first = BrowserTab(browser: self)
        tabs = [first]
        selectedTabID = first.id
        lastListTabID = first.id
        syncAddressText()
    }

    /// Brings back the last session's tabs, once, into the first normal window that appears. Done
    /// when the window is on screen rather than in init: SwiftUI may build a window's model more
    /// than once and keep only one, and a discarded model must not use up the saved session.
    func restoreSavedSession() {
        guard !isPrivate, !sessionRestored else { return }
        sessionRestored = true
        // Only into a window nobody has used yet.
        guard tabs.count == 1, tabs[0].isHome, pinnedTabs.isEmpty,
              let saved = SessionStore.claimSavedSession(space: spaceID) else { return }
        restore(saved)
    }

    /// Brings `saved`'s tabs into the window.
    private func restore(_ saved: SavedSession) {
        let restored = saved.tabs.compactMap { saved -> BrowserTab? in
            guard let url = URL(string: saved.url) else { return nil }
            let tab = BrowserTab(browser: self, restoring: url, title: saved.title)
            tab.group = saved.group.flatMap(UUID.init(uuidString:))
            return tab
        }
        groups = (saved.groups ?? []).compactMap { group in
            UUID(uuidString: group.id).map { TabGroup(id: $0, name: group.name, collapsed: group.collapsed) }
        }
        for (key, page) in saved.pinned ?? [:] {
            guard let launcher = Launcher(rawValue: key), launcher.destination != nil,
                  let url = URL(string: page.url) else { continue }
            let tab = BrowserTab(browser: self, restoring: url, title: page.title)
            tab.pinned = launcher
            pinnedTabs[launcher] = tab
        }
        guard !restored.isEmpty || !pinnedTabs.isEmpty else { return }
        if !restored.isEmpty { tabs = restored }
        let index = min(max(saved.selectedIndex, 0), tabs.count - 1)
        lastListTabID = tabs[index].id
        let pinnedFirst = saved.selectedPinned.flatMap(Launcher.init(rawValue:)).flatMap { pinnedTabs[$0] }
        let first = pinnedFirst ?? tabs[index]
        selectedTabID = first.id
        first.restoreIfNeeded()
        syncAddressText()
    }

    // MARK: - Spaces

    /// Moves the window to another space: its tabs are kept for when it comes back, and the other
    /// space's tabs, sign-ins and site data take their place.
    func switchSpace(to id: UUID?) {
        guard !isPrivate, id != spaceID else { return }
        agent.reset()
        SessionStore.saveNow(self)
        for tab in allTabs { tab.tearDown() }
        pinnedTabs = [:]
        split = nil
        groups = []
        peek = nil
        grokWebPanelStorage = nil
        xSearchStorage = nil
        xPanelSearchStorage = nil
        searches.removeAll()
        spaceID = id
        websiteDataStore = SpaceStore.shared.dataStore(for: id)
        SpaceStore.shared.noteUsed(id)
        let first = BrowserTab(browser: self)
        tabs = [first]
        selectedTabID = first.id
        lastListTabID = first.id
        if let saved = SessionStore.load(space: id) { restore(saved) }
        spaceVersion += 1
        syncAddressText()
        save()
        showToast(String(localized: "Now in \(SpaceStore.shared.name(of: id))."))
    }

    /// Asks for a name, makes the space, and moves the window there.
    func newSpace() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "New space")
        alert.informativeText = String(localized: "A space keeps its own tabs, sign-ins and cookies, like Personal and Work.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = String(localized: "Work")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Create"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let id = SpaceStore.shared.create(field.stringValue)
            self?.switchSpace(to: id)
        }
    }

    /// Deletes the space on screen, with what sites kept in it, after asking.
    func deleteCurrentSpace() {
        guard let id = spaceID, let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete “\(SpaceStore.shared.name(of: id))”?")
        alert.informativeText = String(localized: "Its tabs, and the sign-ins, cookies and data sites kept in it, are removed from this Mac.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.switchSpace(to: nil)
            Task { await SpaceStore.shared.delete(id) }
        }
    }

    var selectedTab: BrowserTab? {
        if let tab = tabs.first(where: { $0.id == selectedTabID }) { return tab }
        return pinnedTabs.values.first { $0.id == selectedTabID }
    }

    /// The tab list's tab that was on screen last (while a pinned site is, the one before it).
    var lastListSelection: UUID? { lastListTabID }

    /// The pinned site on screen, if the selected tab is one.
    var selectedPinned: Launcher? { selectedTab?.pinned }

    /// Every tab in the window: the list, then the pinned sites'.
    var allTabs: [BrowserTab] {
        tabs + Launcher.pinnable.compactMap { pinnedTabs[$0] }
    }

    /// Tabs not in a group, as the sidebar shows them (filtered by its search field).
    var looseTabs: [BrowserTab] { visibleTabs.filter { tab in tab.group == nil || !groups.contains { $0.id == tab.group } } }

    /// A group's tabs, as the sidebar shows them.
    func tabs(in group: TabGroup) -> [BrowserTab] { visibleTabs.filter { $0.group == group.id } }

    /// Sorts the tabs into named groups: by topic with the Mac's own model, or by site without it.
    func tidyTabs() {
        let candidates = tabs.filter { !$0.isHome }
        guard candidates.count >= 3, !tidying else {
            showToast(String(localized: "Open a few more tabs first."))
            return
        }
        tidying = true
        let described = candidates.map { tab -> (title: String, site: String) in
            let site = tab.url.flatMap { $0.host }.map(SourceLabels.registeredDomain) ?? ""
            return (tab.searchQuery.map { String(localized: "Search: \($0)") } ?? tab.displayTitle,
                    MaxQScheme.isNative(tab.url) ? "" : site)
        }
        Task {
            let found = await OnDevice.groups(for: described)
            tidying = false
            guard !found.isEmpty else {
                showToast(String(localized: "These tabs don't fall into groups."))
                return
            }
            var newGroups: [TabGroup] = []
            for tab in tabs { tab.group = nil }
            for group in found {
                let made = TabGroup(id: UUID(), name: group.name)
                newGroups.append(made)
                for index in group.members where candidates.indices.contains(index) { candidates[index].group = made.id }
            }
            // Loose tabs first, then each group's, in the groups' order.
            let loose = tabs.filter { $0.group == nil }
            let grouped = newGroups.flatMap { group in tabs.filter { $0.group == group.id } }
            withAnimation(Motion.smooth) {
                groups = newGroups
                tabs = loose + grouped
            }
            save()
            showToast(OnDevice.isAvailable ? String(localized: "Tabs sorted by topic, on this Mac.") : String(localized: "Tabs sorted by site."),
                      actionTitle: String(localized: "Undo")) { [weak self] in self?.ungroupAll() }
        }
    }

    func ungroupAll() {
        withAnimation(Motion.smooth) {
            for tab in tabs { tab.group = nil }
            groups = []
        }
        save()
    }

    func toggleGroup(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.smooth) { groups[index].collapsed.toggle() }
        save()
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { groups[index].name = String(trimmed.prefix(30)) }
        save()
    }

    func ungroup(_ id: UUID) {
        withAnimation(Motion.smooth) {
            for tab in tabs where tab.group == id { tab.group = nil }
            groups.removeAll { $0.id == id }
        }
        save()
    }

    func closeGroup(_ id: UUID) {
        for tab in tabs where tab.group == id { closeTab(tab) }
        groups.removeAll { $0.id == id }
        save()
    }

    /// Tabs shown in the sidebar (filtered by the sidebar's search field).
    var visibleTabs: [BrowserTab] {
        let query = tabFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return tabs }
        return tabs.filter {
            $0.displayTitle.lowercased().contains(query) || ($0.url?.absoluteString.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Tabs

    @discardableResult
    func newTab(select: Bool = true, focusAddress: Bool = true) -> BrowserTab {
        let tab = BrowserTab(browser: self)
        insert(tab)
        if select {
            self.select(tab)
            if focusAddress { requestAddressFocus() }
        }
        return tab
    }

    func openInNewTab(_ url: URL, select: Bool = true) {
        let tab = BrowserTab(browser: self)
        insert(tab)
        tab.load(url)
        if select { self.select(tab) }
        save()
    }

    /// Opens `url` in the current tab when it's an empty new tab, otherwise in a new one.
    func open(_ url: URL) {
        if let tab = selectedTab, tab.isHome {
            tab.load(url)
            syncAddressText()
            save()
        } else {
            openInNewTab(url)
        }
    }

    func openPopupTab(configuration: WKWebViewConfiguration, select: Bool) -> WKWebView? {
        let tab = BrowserTab(browser: self, configuration: configuration)
        insert(tab)
        if select { self.select(tab) }
        return tab.webView
    }

    private func insert(_ tab: BrowserTab) {
        // From a pinned site, new tabs go after the list tab that was on screen before it.
        if let current = tabs.firstIndex(where: { $0.id == selectedTabID })
            ?? tabs.firstIndex(where: { $0.id == lastListTabID }) {
            tabs.insert(tab, at: current + 1)
        } else {
            tabs.append(tab)
        }
    }

    func select(_ tab: BrowserTab) {
        guard selectedTabID != tab.id else { return }
        if tab.pinned == nil { lastListTabID = tab.id }
        // The outgoing page is still on screen: keep a picture of it for the hover preview.
        selectedTab?.captureSnapshot()
        BotEmailAutofill.shared.hide()
        peek = nil
        selectedTabID = tab.id
        tab.restoreIfNeeded()
        findBarVisible = false
        addressFocused = false
        suggestions = []
        syncAddressText()
        refreshGrokipedia()
        save()
    }

    /// ⌘1 to ⌘8 pick that tab; ⌘9 always picks the last one.
    func select(index: Int) {
        guard !tabs.isEmpty else { return }
        let target = index >= 8 ? tabs.count - 1 : min(index, tabs.count - 1)
        select(tabs[target])
    }

    func selectNextTab() {
        guard let i = tabs.firstIndex(where: { $0.id == selectedTabID }) else { returnToList(); return }
        guard tabs.count > 1 else { return }
        select(tabs[(i + 1) % tabs.count])
    }

    func selectPreviousTab() {
        guard let i = tabs.firstIndex(where: { $0.id == selectedTabID }) else { returnToList(); return }
        guard tabs.count > 1 else { return }
        select(tabs[(i - 1 + tabs.count) % tabs.count])
    }

    /// From a pinned tab, back to the tab list's tab that was on screen before it.
    private func returnToList() {
        if let tab = tabs.first(where: { $0.id == lastListTabID }) ?? tabs.last {
            select(tab)
        }
    }

    // MARK: - Split view

    /// The split on screen: there's one, and the selected tab is in it.
    var activeSplit: SplitPair? {
        guard let split, split.contains(selectedTabID),
              allTabs.contains(where: { $0.id == split.leading }), allTabs.contains(where: { $0.id == split.trailing }) else { return nil }
        return split
    }

    /// Puts `other` beside the tab on screen, and moves the keyboard to it.
    func splitView(with other: BrowserTab) {
        guard let current = selectedTab, current.id != other.id else { return }
        split = SplitPair(leading: current.id, trailing: other.id)
        if let from = tabs.firstIndex(where: { $0.id == other.id }), let to = tabs.firstIndex(where: { $0.id == current.id }), from != to + 1 {
            // Side by side in the sidebar too.
            tabs.move(fromOffsets: IndexSet(integer: from), toOffset: from > to ? to + 1 : to)
        }
        select(other)
    }

    /// Opens `url` in a new tab beside the one on screen (a result next to its results page).
    func openBeside(_ url: URL) {
        guard let current = selectedTab else { openInNewTab(url); return }
        let tab = BrowserTab(browser: self)
        insert(tab)
        tab.load(url)
        split = SplitPair(leading: current.id, trailing: tab.id)
        select(tab)
        save()
    }

    /// The tab beside the one on screen in the split, if any.
    var splitPartner: BrowserTab? {
        guard let split = activeSplit, let id = selectedTabID, let partner = split.partner(of: id) else { return nil }
        return allTabs.first { $0.id == partner }
    }

    /// A click in one of the split's panes gives it the keyboard.
    func focusPane(_ tab: BrowserTab) {
        guard activeSplit?.contains(tab.id) == true, selectedTabID != tab.id else { return }
        select(tab)
    }

    func swapSplit() {
        guard var split else { return }
        swap(&split.leading, &split.trailing)
        split.ratio = 1 - split.ratio
        withAnimation(Motion.smooth) { self.split = split }
    }

    func closeSplit() {
        withAnimation(Motion.smooth) { split = nil }
    }

    // MARK: - Pinned sites

    /// Switches to a pinned site's tab, opening it the first time. Clicking the tile of the site
    /// already on screen goes back to its front page, like the site's own logo. Grok Bot is an
    /// app, so its tile opens the app.
    func openPinned(_ launcher: Launcher) {
        guard let home = launcher.destination else {
            openGrokBot()
            return
        }
        if let tab = pinnedTabs[launcher] {
            guard tab.isSelected else {
                select(tab)
                return
            }
            if let webView = tab.webView, let url = tab.url, launcher.isFrontPage(url) {
                // Already home: back to the top, like the site's own logo.
                Task { _ = await PageScripts.run("window.scrollTo({ top: 0, behavior: 'smooth' }); return true;", in: webView) }
            } else {
                tab.load(home)
            }
            return
        }
        let tab = BrowserTab(browser: self)
        tab.pinned = launcher
        pinnedTabs[launcher] = tab
        tab.load(home)
        select(tab)
        save()
    }

    /// Closes a pinned site's tab (its tile stays, ready to open the site again) and goes back to
    /// the tab list.
    func putAway(_ launcher: Launcher) {
        guard let tab = pinnedTabs.removeValue(forKey: launcher) else { return }
        if split?.contains(tab.id) == true { split = nil }
        let wasSelected = tab.id == selectedTabID
        if peek?.tabID == tab.id { peek = nil }
        tab.tearDown()
        if wasSelected {
            selectedTabID = nil
            if tabs.isEmpty { tabs = [BrowserTab(browser: self)] }
            returnToList()
        }
        save()
    }

    func closeTab(_ tab: BrowserTab) {
        if let launcher = tab.pinned {
            putAway(launcher)
            return
        }
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let url = tab.url, !isPrivate {
            recentlyClosed.append((url, tab.title))
            if recentlyClosed.count > 20 { recentlyClosed.removeFirst() }
        }
        let wasSelected = tab.id == selectedTabID
        if peek?.tabID == tab.id { peek = nil }
        if split?.contains(tab.id) == true { split = nil }
        tabs.remove(at: index)
        tab.tearDown()

        if tabs.isEmpty {
            if let window, pinnedTabs.isEmpty {
                // Closing the last tab closes the window; don't bring that tab back next launch.
                save()
                window.performClose(nil)
                return
            }
            tabs = [BrowserTab(browser: self)]
        }
        if wasSelected {
            let next = tabs[min(index, tabs.count - 1)]
            selectedTabID = nil
            select(next)
        }
        save()
    }

    func closeCurrentTab() {
        if let tab = selectedTab { closeTab(tab) }
    }

    func closeOtherTabs(except keep: BrowserTab) {
        for tab in tabs where tab.id != keep.id { closeTab(tab) }
    }

    func reopenClosedTab() {
        guard let last = recentlyClosed.popLast() else { return }
        openInNewTab(last.url)
    }

    var canReopenClosedTab: Bool { !recentlyClosed.isEmpty }

    func moveTabs(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Drag and drop in the sidebar: puts `tab` where `target` is.
    func move(_ tab: BrowserTab, to target: BrowserTab) {
        guard tab.id != target.id,
              let from = tabs.firstIndex(where: { $0.id == tab.id }),
              let to = tabs.firstIndex(where: { $0.id == target.id }) else { return }
        tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        save()
    }

    func duplicate(_ tab: BrowserTab) {
        guard let url = tab.url else { return }
        openInNewTab(url)
    }

    func tabURLDidChange(_ tab: BrowserTab) {
        if tab.id == selectedTabID {
            if !addressFocused { syncAddressText() }
            refreshGrokipedia()
        }
        save()
    }

    func tabDidFinishLoading(_ tab: BrowserTab) {
        if tab.id == selectedTabID, !addressFocused { syncAddressText() }
        if tab.id == selectedTabID {
            // Give the page a moment to paint, then keep a picture for the hover preview.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak tab] in
                if let tab, tab.isSelected { tab.captureSnapshot() }
            }
        }
        save()
    }

    // MARK: - Tab previews

    func showPeek(_ tab: BrowserTab, anchor: CGRect) {
        guard tab.id != selectedTabID, !tab.isHome else { peek = nil; return }
        peek = TabPeek(tabID: tab.id, anchor: anchor)
    }

    func hidePeek(_ tabID: UUID) {
        if peek?.tabID == tabID { peek = nil }
    }

    private func save() {
        SessionStore.save(self)
    }

    // MARK: - Address bar

    func requestAddressFocus() {
        focusAddressRequest += 1
    }

    /// Bumped to bring setup back over this window (Settings, "Set up Max Q again").
    private(set) var setupRequest = 0

    func showSetup() {
        setupRequest += 1
    }

    func requestComposerFocus() {
        composerFocusRequest += 1
    }

    func syncAddressText() {
        guard let tab = selectedTab else { addressText = ""; return }
        if tab.isHome {
            addressText = ""
        } else if let page = tab.nativePage {
            addressText = MaxQScheme.title(for: page)
        } else if let query = tab.searchQuery {
            addressText = query
        } else {
            addressText = tab.url?.absoluteString ?? ""
        }
    }

    func submitAddress() {
        if suggestionIndex > 0, suggestions.indices.contains(suggestionIndex) {
            activate(suggestions[suggestionIndex])
            return
        }
        // A shortcut being typed ("!y"): Return takes the first one offered.
        if addressText.hasPrefix("!"), !addressText.trimmingCharacters(in: .whitespaces).contains(" "),
           let first = suggestions.first, first.bang != nil {
            activate(first)
            return
        }
        guard let input = AddressInput.classify(addressText) else { return }
        navigate(input)
    }

    func navigate(_ input: AddressInput) {
        if case .search(let text) = input, let (bang, words) = Bangs.parse(text) {
            follow(bang, words: words)
            return
        }
        var tab = selectedTab ?? newTab(focusAddress: false)
        // A pinned site keeps its tile: searches and other sites typed there open a new tab.
        if let launcher = tab.pinned {
            let stays: Bool = if case .url(let url) = input { launcher.keepsInPinnedTab(url) } else { false }
            if !stays { tab = newTab(focusAddress: false) }
        }
        switch input {
        case .url(let url):
            tab.searchQuery = nil
            tab.load(url)
        case .search(let query):
            guard let url = settings.searchEngine.searchURL(for: query) else { return }
            tab.searchQuery = query
            tab.searchVertical = .web
            tab.load(url)
        }
        dismissSuggestions()
        addressFocused = false
        syncAddressText()
        refreshGrokipedia()
        window?.makeFirstResponder(tab.webView)
        save()
    }

    /// A shortcut from the address bar: Max Q's own tabs for "!x" and "!gp", Grok for "!grok", a
    /// site's own search for the rest.
    func follow(_ bang: Bang, words: String) {
        dismissSuggestions()
        addressFocused = false
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        switch bang.target {
        case .research:
            syncAddressText()
            startResearch(words)
            return
        case .imagine:
            syncAddressText()
            ImagineStore.shared.draft = words.isEmpty ? nil : words
            openNative(.imagine, inNewTab: selectedTab?.isHome != true)
            return
        case .askGrok:
            syncAddressText()
            if words.isEmpty {
                grokPanelVisible = true
                requestComposerFocus()
            } else {
                askGrok(words)
            }
            return
        case .maxQ(let searchTab) where words.isEmpty && (searchTab == .x || searchTab == .grokipedia):
            // "!x" alone: the site itself, in its tile.
            openPinned(searchTab == .x ? .x : .grokipedia)
            return
        case .maxQ(.news) where words.isEmpty:
            // "!news" alone: today's news, on the new-tab page.
            let tab = newTab(focusAddress: false)
            tab.showNewsRequest += 1
            return
        case .maxQ where words.isEmpty:
            return
        case .maxQ(let searchTab) where settings.searchEngine.isMaxQ:
            guard let url = MaxQScheme.searchURL(for: words, tab: searchTab) else { return }
            let tab = tabForNavigation()
            tab.searchQuery = words
            tab.searchVertical = .web
            tab.load(url)
            finishNavigation(in: tab)
        default:
            guard let url = bang.url(for: words) else { return }
            let tab = tabForNavigation()
            if case .maxQ(let searchTab) = bang.target, searchTab == .x || searchTab == .grokipedia {
                tab.searchQuery = words
                tab.searchVertical = searchTab == .x ? .x : .grokipedia
            } else {
                tab.searchQuery = nil
            }
            tab.load(url)
            finishNavigation(in: tab)
        }
    }

    /// Max Q's own results page for `query`, on `searchTab`, in the tab on screen (or, with ⌘ held
    /// or `inNewTab`, a new one). The News tab's "See all" and "Full coverage" open this way.
    func openMaxQSearch(_ query: String, on searchTab: GrokSearchTab = .all, inNewTab: Bool = false) {
        guard let url = MaxQScheme.searchURL(for: query, tab: searchTab) else { return }
        let commandHeld = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        let tab = inNewTab || commandHeld ? newTab(select: !commandHeld, focusAddress: false) : tabForNavigation()
        tab.searchQuery = query
        tab.searchVertical = .web
        tab.load(url)
        finishNavigation(in: tab)
    }

    /// One of Max Q's own pages (research, a collection, Imagine), in a new tab or the one on screen.
    func openNative(_ page: NativePage, inNewTab: Bool = false) {
        let url = MaxQScheme.url(for: page)
        let tab = inNewTab ? newTab(focusAddress: false) : tabForNavigation()
        tab.searchQuery = nil
        tab.load(url)
        finishNavigation(in: tab)
    }

    /// Opens the research sheet for `question` (or an empty one).
    func startResearch(_ question: String = "") {
        researchDraft = ResearchDraft(question: question)
    }

    /// The tab a typed address or search loads in: the one on screen, unless it's a pinned site's.
    private func tabForNavigation() -> BrowserTab {
        let tab = selectedTab ?? newTab(focusAddress: false)
        return tab.pinned == nil ? tab : newTab(focusAddress: false)
    }

    private func finishNavigation(in tab: BrowserTab) {
        syncAddressText()
        refreshGrokipedia()
        window?.makeFirstResponder(tab.webView)
        save()
    }

    func activate(_ suggestion: AddressSuggestion) {
        switch suggestion.kind {
        case let .bang(trigger, words):
            if let bang = Bangs.find(trigger) { follow(bang, words: words) }
        case .bangHint(let trigger):
            // Into the field, ready for the words.
            addressText = "!\(trigger) "
            requestAddressFocus()
            addressTextChanged()
        case .open(let url), .history(let url, _), .bookmark(let url, _, _):
            navigate(.url(url))
        case .search(let query), .engineSuggestion(let query):
            navigate(.search(query))
        case .askGrok(let query):
            dismissSuggestions()
            addressFocused = false
            syncAddressText()
            askGrok(query)
        }
    }

    /// Tab in the address field: puts the shortcut the list is pointing at into the field. False
    /// when there's nothing to complete, so Tab moves focus as usual.
    func completeShortcut() -> Bool {
        let text = addressText.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("!"), !text.contains(" "), suggestions.indices.contains(suggestionIndex),
              let bang = suggestions[suggestionIndex].bang else { return false }
        addressText = "!\(bang.trigger) "
        addressTextChanged()
        return true
    }

    func moveSuggestionSelection(by delta: Int) {
        guard !suggestions.isEmpty else { return }
        suggestionIndex = max(0, min(suggestions.count - 1, suggestionIndex + delta))
    }

    func dismissSuggestions() {
        suggestionTask?.cancel()
        suggestions = []
        suggestionIndex = 0
    }

    /// Recomputes the dropdown for what's typed: default action, Ask Grok, history, then the
    /// engine's suggestions (fetched after a short pause, only when suggestions are on).
    func addressTextChanged() {
        suggestionTask?.cancel()
        let text = addressText.trimmingCharacters(in: .whitespaces)
        guard addressFocused, !text.isEmpty else {
            suggestions = []
            suggestionIndex = 0
            return
        }
        // Shortcuts: "!" lists them, "!yt lofi" sends the words there.
        let completions = Bangs.completions(for: text)
        if text.hasPrefix("!"), !text.contains(" ") {
            var rows: [AddressSuggestion] = []
            if let exact = Bangs.find(text) { rows.append(AddressSuggestion(kind: .bang(trigger: exact.trigger, words: ""))) }
            rows += completions.filter { $0.trigger != Bangs.find(text)?.trigger }
                .map { AddressSuggestion(kind: .bangHint(trigger: $0.trigger)) }
            suggestions = rows
            suggestionIndex = 0
            return
        }
        if let (bang, words) = Bangs.parse(text) {
            suggestions = [AddressSuggestion(kind: .bang(trigger: bang.trigger, words: words))]
            suggestionIndex = 0
            guard settings.searchSuggestionsEnabled, !isPrivate, !words.isEmpty,
                  let suggestURL = settings.searchEngine.suggestURL(for: words) else { return }
            suggestionTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled, let self else { return }
                guard let (data, _) = try? await self.suggestionSession.data(from: suggestURL), !Task.isCancelled else { return }
                let more = SearchEngine.parseSuggestions(data)
                    .filter { $0.caseInsensitiveCompare(words) != .orderedSame }
                    .prefix(5)
                    .map { AddressSuggestion(kind: .bang(trigger: bang.trigger, words: $0)) }
                guard self.addressFocused, self.addressText.trimmingCharacters(in: .whitespaces) == text else { return }
                self.suggestions = [AddressSuggestion(kind: .bang(trigger: bang.trigger, words: words))] + more
            }
            return
        }
        var rows: [AddressSuggestion] = []
        switch AddressInput.classify(text) {
        case .url(let url): rows.append(AddressSuggestion(kind: .open(url)))
        case .search(let query): rows.append(AddressSuggestion(kind: .search(query)))
        case nil: break
        }
        rows.append(AddressSuggestion(kind: .askGrok(text)))
        if !isPrivate {
            for bookmark in BookmarkStore.shared.matches(for: text, limit: 3) {
                guard let url = URL(string: bookmark.url) else { continue }
                rows.append(AddressSuggestion(kind: .bookmark(url, title: bookmark.title, folder: bookmark.folder)))
            }
        }
        let history = isPrivate ? [] : HistoryStore.shared.matches(for: text, limit: 4)
        for entry in history {
            guard let url = URL(string: entry.url) else { continue }
            let row = AddressSuggestion(kind: .history(url, title: entry.title))
            if !rows.contains(where: { $0.id == row.id }) { rows.append(row) }
        }
        suggestions = rows
        suggestionIndex = 0

        guard settings.searchSuggestionsEnabled, !isPrivate,
              case .search = AddressInput.classify(text),
              let suggestURL = settings.searchEngine.suggestURL(for: text) else { return }
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, let self else { return }
            guard let (data, _) = try? await self.suggestionSession.data(from: suggestURL), !Task.isCancelled else { return }
            let remote = SearchEngine.parseSuggestions(data)
                .filter { $0.caseInsensitiveCompare(text) != .orderedSame }
                .prefix(5)
            guard self.addressFocused, self.addressText.trimmingCharacters(in: .whitespaces) == text else { return }
            let extra = remote.map { AddressSuggestion(kind: .engineSuggestion($0)) }
            self.suggestions = self.suggestions.filter {
                if case .engineSuggestion = $0.kind { return false } else { return true }
            } + extra
        }
    }

    // MARK: - Grokipedia card

    /// The card loads by itself only in normal windows set to "Automatically". Private windows
    /// never contact Grokipedia unless the user asks.
    var grokipediaAutomatic: Bool {
        settings.grokipediaMode == .automatic && !isPrivate
    }

    /// Runs the selected tab's search on another vertical (the web, Grokipedia or X).
    func switchVertical(to vertical: SearchVertical) {
        guard let tab = selectedTab, let query = tab.searchQuery, vertical != tab.searchVertical,
              let url = vertical.url(for: query) else { return }
        // A pinned site's tab keeps its site: the other search opens in a tab of its own.
        if tab.pinned != nil {
            openInNewTab(url)
            return
        }
        tab.searchVertical = vertical
        tab.load(url)
        refreshGrokipedia()
        save()
    }

    func refreshGrokipedia() {
        // Grok's own results page looks Grokipedia up itself.
        guard settings.grokipediaMode != .off, let tab = selectedTab, !tab.isHome, tab.nativeSearch == nil else {
            grokipedia.update(query: nil, automatic: false)
            return
        }
        // Grokipedia's own search pages and X's don't need the card beside them.
        grokipedia.update(query: tab.searchVertical == .web ? tab.searchQuery : nil, automatic: grokipediaAutomatic)
    }

    // MARK: - Grok

    func toggleGrokPanel() {
        grokPanelVisible.toggle()
    }

    var grokPanelMode: GrokPanelMode {
        get { settings.grokPanelMode }
        set {
            settings.grokPanelMode = newValue
            panelShowsX = false
            panelShowsAgent = false
        }
    }

    /// Native chat when a key is set; grok.com in the panel otherwise.
    func askGrok(_ question: String) {
        grokPanelVisible = true
        if grokAccount.hasKey && grokPanelMode == .native {
            grok.ask(question)
        } else {
            grokPanelMode = .web
            grokWebPanel.ask(question)
        }
    }

    /// "Follow up" on Grok's results page: the answer moves into the panel's chat, ready for the
    /// next question.
    func continueInChat(question: String, answer: String, citations: [GrokCitation], model: String?) {
        grokPanelMode = .native
        grok.adopt(question: question, answer: answer, citations: citations, model: model)
        grokPanelVisible = true
        requestComposerFocus()
    }

    /// grok.com answers in the side panel (no API key needed, the user's own Grok account).
    func askGrokOnWeb(_ question: String) {
        grokPanelVisible = true
        grokPanelMode = .web
        grokWebPanel.ask(question)
    }

    func requestGrokKey() {
        grokPanelVisible = true
        grokPanelMode = .native
    }

    func summarizeCurrentPage() {
        Task {
            guard let page = await currentPageContext() else {
                showToast(String(localized: "Open a page first, then ask Grok to summarize it."))
                return
            }
            grokPanelVisible = true
            if grokAccount.hasKey {
                grokPanelMode = .native
                grok.summarize(page: page)
            } else {
                grokPanelMode = .web
                grokWebPanel.ask(String(localized: "Summarize this page: \(page.url?.absoluteString ?? page.title)"))
            }
        }
    }

    /// The page summarized by the Mac's own model: free, and nothing leaves the Mac.
    func summarizeOnDevice() {
        guard OnDevice.isAvailable else {
            showToast(OnDevice.unavailableReason)
            return
        }
        Task {
            guard let page = await currentPageContext(maxCharacters: 12_000), !page.text.isEmpty else {
                showToast(String(localized: "Open a page first, then summarize it."))
                return
            }
            showToast(String(localized: "Summarizing on this Mac…"))
            guard let summary = await OnDevice.summarize(title: page.title, text: page.text) else {
                showToast(String(localized: "The summary didn't finish."))
                return
            }
            toast = nil
            grokPanelVisible = true
            grokPanelMode = .native
            grok.appendLocal(question: String(localized: "Summarize “\(page.title)” on this Mac"), answer: summary)
        }
    }

    func summarizeAllTabs() {
        Task {
            let pages = await allTabsContext()
            guard !pages.isEmpty else { showToast(String(localized: "There are no open pages to summarize.")); return }
            grokPanelVisible = true
            grokPanelMode = .native
            grok.summarize(tabs: pages)
        }
    }

    /// "What is X saying about this page": x.com's own search for posts sharing it, live in the
    /// side panel, in the user's X account. Free, and no key needed.
    func whatXSays() {
        grokPanelVisible = true
        panelShowsAgent = false
        panelShowsX = true
    }

    /// The agent in the panel, ready for a task (or with `task` started).
    func showAgent(task: String? = nil) {
        grokPanelVisible = true
        panelShowsX = false
        panelShowsAgent = true
        if let task, !task.isEmpty, !agent.isActive {
            agent.draft = task
            agent.send()
        } else {
            requestComposerFocus()
        }
    }

    /// Grok reads what X is saying about the page and sums it up (an X search on the user's key).
    func askGrokWhatXSays() {
        guard let tab = selectedTab, let url = tab.url, !tab.isHome else {
            showToast(String(localized: "Open a page first."))
            return
        }
        grokPanelVisible = true
        grokPanelMode = .native
        grok.whatXSays(about: PageContext(title: tab.title, url: url, text: ""))
    }

    /// The selected page's visible text, read when the user asks (never in the background).
    func currentPageContext(maxCharacters: Int = 24_000) async -> PageContext? {
        // Grok's own results page isn't a web page to read.
        guard let tab = selectedTab, !tab.isHome, tab.nativeSearch == nil else { return nil }
        return await context(for: tab, maxCharacters: maxCharacters)
    }

    func allTabsContext() async -> [PageContext] {
        await allTabPages().map(\.context)
    }

    /// Each open page's text with its tab, read when the user asks (never in the background).
    func allTabPages() async -> [(id: UUID, context: PageContext)] {
        let pages = allTabs.filter { !$0.isHome && $0.url != nil && $0.nativeSearch == nil && !MaxQScheme.isNative($0.url) }
        guard !pages.isEmpty else { return [] }
        // Share a fixed budget across tabs so "All tabs" can't send an enormous request.
        let budget = max(2_000, 48_000 / pages.count)
        var result: [(id: UUID, context: PageContext)] = []
        for tab in pages.prefix(12) {
            if let context = await context(for: tab, maxCharacters: budget) { result.append((tab.id, context)) }
        }
        return result
    }

    /// "Which tab had the pricing table?": a question for Grok with the open tabs' text attached.
    /// Grok links the tabs it means, and a click switches to them.
    func askAboutTabs(_ question: String) {
        guard grokAccount.hasKey else {
            showToast(String(localized: "Asking Grok about your tabs needs your SpaceXAI API key, so their text can go with the question."))
            requestGrokKey()
            return
        }
        grokPanelVisible = true
        grokPanelMode = .native
        Task {
            let pages = await allTabPages()
            guard !pages.isEmpty else {
                showToast(String(localized: "There are no open pages to ask about."))
                return
            }
            grok.askAboutTabs(question, pages: pages)
        }
    }

    private func context(for tab: BrowserTab, maxCharacters: Int) async -> PageContext? {
        guard let webView = tab.webView else {
            // Restored tab that hasn't loaded: title and URL only.
            return tab.url.map { PageContext(title: tab.title, url: $0, text: "") }
        }
        let result = await PageScripts.run(PageScripts.visibleText, arguments: ["max": maxCharacters], in: webView) as? [String: Any]
        let title = (result?["title"] as? String) ?? tab.title
        let text = (result?["text"] as? String) ?? ""
        return PageContext(title: title, url: webView.url ?? tab.url, text: text)
    }

    // MARK: - Page context menu

    func handlePageMenu(_ action: PageMenuAction, in tab: BrowserTab, webView: MaxQWebView) {
        let token = tab.pageToken
        Task {
            let selection = await webView.captureSelection(token: token)
            let page = PageContext(title: tab.title, url: tab.url, text: "")
            switch action {
            case .askGrok:
                guard !selection.text.isEmpty else { return }
                grokPanelVisible = true
                if grokAccount.hasKey { grokPanelMode = .native; grok.askAbout(selection.text, from: page) }
                else { askGrok(String(localized: "What should I know about this: \"\(GrokSession.preview(selection.text, limit: 600))\"")) }
            case .check:
                guard !selection.text.isEmpty else { return }
                ClaimChecks.check(selection.text, source: .page(title: tab.title, url: tab.url),
                                  anchor: selection.rect.flatMap { webView.screenRect(forPage: $0) }, browser: self)
            case .explain:
                guard !selection.text.isEmpty else { return }
                grokPanelVisible = true
                if grokAccount.hasKey { grokPanelMode = .native; grok.explain(selection.text, from: page) }
                else { askGrok(String(localized: "Explain this in plain language: \"\(GrokSession.preview(selection.text, limit: 600))\"")) }
            case .translate:
                guard !selection.text.isEmpty else { return }
                grokPanelVisible = true
                if grokAccount.hasKey { grokPanelMode = .native; grok.translate(selection.text) }
                else { askGrok(String(localized: "Translate this into \(GrokSession.userLanguageName): \"\(GrokSession.preview(selection.text, limit: 600))\"")) }
            case .rewrite(let style):
                guard !selection.text.isEmpty else { return }
                guard grokAccount.hasKey else {
                    showToast(String(localized: "Rewriting needs your SpaceXAI API key, so the result can go back into the field."))
                    requestGrokKey()
                    return
                }
                grokPanelVisible = true
                grokPanelMode = .native
                grok.rewrite(selection.text, style: style,
                             target: ReplaceTarget(webView: webView, tabID: tab.id, pageToken: token))
            case .addToCollection(let id):
                let item = selection.text.isEmpty
                    ? CollectionItem(kind: .page, title: tab.title, url: tab.url, source: tab.url?.host)
                    : CollectionItem(kind: .quote, title: tab.title, url: tab.url, text: String(selection.text.prefix(4_000)), source: tab.url?.host)
                if let id {
                    CollectionStore.shared.add(item, to: id)
                } else {
                    CollectionStore.shared.addToNew(item, named: tab.title)
                }
                showToast(String(localized: "Added to the collection."))
            case .searchX:
                if let url = XLinks.search(for: selection.text) { openInNewTab(url) }
            case .grokipedia:
                if let url = GrokipediaLinks.search(selection.text) { openInNewTab(url) }
            case .searchWeb:
                if let url = settings.searchEngine.searchURL(for: selection.text) {
                    let newTab = BrowserTab(browser: self)
                    insert(newTab)
                    newTab.searchQuery = selection.text
                    newTab.searchVertical = .web
                    newTab.load(url)
                    select(newTab)
                }
            case .fillBotEmail:
                let ok = await PageScripts.run(PageScripts.fillField,
                                               arguments: ["text": settings.botEmail, "token": token],
                                               in: webView) as? Bool ?? false
                if !ok { showToast(String(localized: "Click inside an email field first, then try again.")) }
            }
        }
    }

    /// Reader on the tab on screen: on (the page's article, set like a Grokipedia article) or off.
    func toggleReader() {
        guard let tab = selectedTab, let webView = tab.webView, !tab.isHome, tab.nativeSearch == nil, tab.nativePage == nil,
              let url = tab.url, url.scheme == "https" || url.scheme == "http" else { return }
        if tab.reader != nil {
            withAnimation(Motion.smooth) { tab.reader = nil }
            return
        }
        withAnimation(Motion.smooth) { tab.reader = .loading }
        let token = tab.pageToken
        Task {
            let json = await PageScripts.run(ReaderScripts.extract, in: webView) as? [String: Any]
            guard tab.pageToken == token, tab.reader != nil else { return }
            if let json, let document = ReaderDocument.make(json, url: webView.url ?? url) {
                withAnimation(Motion.smooth) { tab.reader = .ready(document) }
            } else {
                withAnimation(Motion.smooth) { tab.reader = .failed(String(localized: "Reader couldn't find an article on this page.")) }
            }
        }
    }

    /// The tab on screen shows a YouTube video.
    var onVideoPage: Bool { VideoPages.isVideo(selectedTab?.url) }

    /// Asks Grok about the video on screen, with its transcript (a summary with its key moments,
    /// unless `question` says otherwise).
    func askAboutVideo(_ question: String? = nil) {
        guard let tab = selectedTab, let webView = tab.webView, VideoPages.isVideo(tab.url) else {
            showToast(String(localized: "Open a YouTube video first."))
            return
        }
        let asked = question ?? String(localized: "Summarize this video, with its key moments.")
        guard grokAccount.hasKey else {
            askGrokOnWeb("\(asked) \(tab.url?.absoluteString ?? "")")
            return
        }
        grokPanelVisible = true
        grokPanelMode = .native
        showToast(String(localized: "Reading the video's transcript…"))
        Task {
            switch await VideoPages.transcript(in: webView) {
            case .success(let transcript):
                toast = nil
                grok.askAboutVideo(asked, transcript: transcript, url: tab.url, tab: tab.id)
            case .failure(let error):
                showToast(error.message)
            }
        }
    }

    /// Checks what's selected on the page with Grok (⇧⌘F).
    func checkSelection() {
        guard let tab = selectedTab, let webView = tab.webView, !tab.isHome, tab.nativeSearch == nil else {
            showToast(String(localized: "Select words on a page to check them."))
            return
        }
        let token = tab.pageToken
        Task {
            let selection = await webView.captureSelection(token: token)
            guard !selection.text.isEmpty else {
                showToast(String(localized: "Select words on a page to check them."))
                return
            }
            ClaimChecks.check(selection.text, source: .page(title: tab.title, url: tab.url),
                              anchor: selection.rect.flatMap { webView.screenRect(forPage: $0) }, browser: self)
        }
    }

    // MARK: - Find in page

    func showFindBar() {
        guard let tab = selectedTab, !tab.isHome, tab.nativeSearch == nil else { return }
        findBarVisible = true
    }

    func find(backwards: Bool = false) {
        guard let webView = selectedTab?.webView, !findText.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(findText, configuration: configuration) { _ in }
    }

    func closeFindBar() {
        findBarVisible = false
        findText = ""
    }

    // MARK: - Page actions

    func zoom(_ delta: CGFloat?) {
        guard let webView = selectedTab?.webView else { return }
        if let delta {
            webView.pageZoom = min(3, max(0.5, webView.pageZoom + delta))
        } else {
            webView.pageZoom = 1
        }
    }

    func copyLink() {
        guard let url = selectedTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast(String(localized: "Link copied."))
    }

    func shareToX() {
        guard let tab = selectedTab, let url = tab.url, !tab.isHome,
              let intent = XLinks.intent(text: tab.title, url: url) else { return }
        openInNewTab(intent)
    }

    func sendToBot() {
        guard let tab = selectedTab, let url = tab.url, !tab.isHome else {
            showToast(String(localized: "Open a page first."))
            return
        }
        botHandoff = BotHandoff(title: tab.title, url: url)
    }

    func openGrokBot() {
        if !GrokBot.open() {
            openInNewTab(GrokBot.downloadPage)
        }
    }

    /// Opens a non-web link (mailto:, an app's own scheme) after a click on the tab on screen.
    /// Mail links open directly; anything else asks first and names the site asking. One prompt
    /// at a time, so a page can't stack them.
    func openExternally(_ url: URL, fromSite site: String?) {
        let workspace = NSWorkspace.shared
        guard let appURL = workspace.urlForApplication(toOpen: url) else {
            let scheme = url.scheme ?? String(localized: "this")
            showToast(String(localized: "No app on this Mac can open “\(scheme)” links."))
            return
        }
        if url.scheme?.lowercased() == "mailto" {
            workspace.open(url)
            return
        }
        guard !externalPromptOpen, let window else { return }
        externalPromptOpen = true
        let appName = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        let alert = NSAlert()
        alert.messageText = String(localized: "Open \(appName)?")
        alert.informativeText = site.map { String(localized: "“\($0)” wants to open \(appName).") }
            ?? String(localized: "This page wants to open \(appName).")
        alert.addButton(withTitle: String(localized: "Open"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.externalPromptOpen = false
            if response == .alertFirstButtonReturn { workspace.open(url) }
        }
    }

    // MARK: - Toasts

    func showToast(_ message: String, actionTitle: String? = nil, duration: Double? = nil, action: (() -> Void)? = nil) {
        toastTask?.cancel()
        toast = Toast(message: message, actionTitle: actionTitle, action: action)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration ?? (actionTitle == nil ? 3.2 : 6)))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
