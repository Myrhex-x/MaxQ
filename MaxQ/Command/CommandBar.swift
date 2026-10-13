//
//  CommandBar.swift
//  Max Q
//
//  ⌘K: one field for everything, the way cmdk works (Benji Taylor keeps it). Type to search
//  your tabs, what's written in them, your history and Max Q's commands; Return runs the one
//  picked, ⌘ Return asks Grok. Groups with nothing to show stay hidden, a command with choices
//  opens them as a page of their own (Escape or Backspace goes back), and there's always
//  something to do with what's typed.
//
//  "In your tabs" reads the text of the pages already open, here on this Mac, when the bar opens:
//  nothing leaves the Mac unless the user picks "Ask Grok about your tabs".
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class CommandBar {
    enum Page: Equatable {
        case root
        case effort
        case theme
        /// Picking the tab to put beside the one on screen.
        case splitWith
    }

    enum Section: String, CaseIterable {
        case top, tabs, inTabs, bookmarks, commands, memory, history, choices

        var title: String? {
            switch self {
            case .top, .choices: nil
            case .tabs: String(localized: "Tabs")
            case .inTabs: String(localized: "In your tabs")
            case .bookmarks: String(localized: "Bookmarks")
            case .commands: String(localized: "Commands")
            case .memory: String(localized: "Pages you've read")
            case .history: String(localized: "History")
            }
        }
    }

    enum Glyph: Equatable {
        case icon(MQIcon)
        case site(String)
    }

    struct Item: Identifiable {
        let id: String
        let section: Section
        let title: String
        var detail: String? = nil
        var glyph: Glyph
        var shortcut: String? = nil
        /// A few words of a page around what was typed, the match in full strength.
        var snippet: AttributedString? = nil
        var checked = false
        let run: @MainActor () -> Void
    }

    var isOpen = false
    var query = "" {
        didSet { selection = 0 }
    }
    private(set) var page: Page = .root
    var selection = 0
    /// Reading the open pages' text, the first time the bar opens on them.
    private(set) var readingTabs = false

    @ObservationIgnored weak var browser: BrowserModel?
    /// Each tab's text, kept for as long as its page is the same one. Observed, so matches inside
    /// pages appear as soon as the pages are read.
    private var tabText: [UUID: (token: String, text: String)] = [:]
    @ObservationIgnored private var readTask: Task<Void, Never>?

    // MARK: - Opening

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard !isOpen else { return }
        query = ""
        page = .root
        selection = 0
        isOpen = true
        browser?.dismissSuggestions()
        browser?.window?.makeFirstResponder(nil)
        readTabs()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        readTask?.cancel()
    }

    func push(_ next: Page) {
        page = next
        query = ""
    }

    /// Escape, or Backspace in an empty field: back a page, or close from the first.
    func back() {
        if page == .root { close() } else { page = .root; query = "" }
    }

    func moveSelection(by delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    func runSelected() {
        let list = items
        guard list.indices.contains(selection) else { return }
        list[selection].run()
    }

    /// ⌘ Return: what's typed goes to Grok.
    func askGrok() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        close()
        guard let browser else { return }
        if text.isEmpty {
            browser.grokPanelVisible = true
            browser.requestComposerFocus()
        } else {
            browser.askGrok(text)
        }
    }

    // MARK: - Reading the tabs

    private func readTabs() {
        guard let browser else { return }
        let tabs = browser.allTabs.filter { !$0.isHome && $0.nativeSearch == nil && $0.webView != nil && $0.loadError == nil }
        let stale = tabs.filter { tabText[$0.id]?.token != $0.pageToken }
        // Forget tabs that closed.
        let open = Set(browser.allTabs.map(\.id))
        tabText = tabText.filter { open.contains($0.key) }
        guard !stale.isEmpty else { return }
        readingTabs = true
        readTask?.cancel()
        readTask = Task { [weak self] in
            for tab in stale {
                guard !Task.isCancelled, let webView = tab.webView else { continue }
                let token = tab.pageToken
                let result = await PageScripts.run(PageScripts.visibleText, arguments: ["max": 60_000], in: webView) as? [String: Any]
                guard let self, !Task.isCancelled else { return }
                if let text = result?["text"] as? String, tab.pageToken == token {
                    self.tabText[tab.id] = (token, text)
                }
            }
            self?.readingTabs = false
        }
    }

    /// Where `words` appear on a tab's page, a few words either side.
    func snippet(for tab: BrowserTab, matching words: String) -> AttributedString? {
        guard let cached = tabText[tab.id], cached.token == tab.pageToken else { return nil }
        return Self.snippet(in: cached.text, matching: words)
    }

    nonisolated static func snippet(in text: String, matching words: String, radius: Int = 70) -> AttributedString? {
        let needle = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 3, let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        var start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        var end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        // Whole words at the edges.
        if start > text.startIndex, let space = text[start..<range.lowerBound].firstIndex(where: \.isWhitespace) { start = text.index(after: space) }
        if end < text.endIndex, let space = text[range.upperBound..<end].lastIndex(where: \.isWhitespace) { end = space }
        func clean(_ part: Substring) -> String {
            part.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        var result = AttributedString((start > text.startIndex ? "…" : "") + clean(text[start..<range.lowerBound]))
        var match = AttributedString(clean(text[range]))
        match.inlinePresentationIntent = .stronglyEmphasized
        result += match
        result += AttributedString(clean(text[range.upperBound..<end]) + (end < text.endIndex ? "…" : ""))
        return result
    }

    // MARK: - What's listed

    var items: [Item] {
        guard let browser else { return [] }
        switch page {
        case .effort: return effortChoices()
        case .theme: return themeChoices()
        case .splitWith: return splitChoices(browser)
        case .root: break
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return tabItems(browser, matching: "", limit: 6) + commandItems(browser, matching: "", limit: 7)
        }
        var list = topItems(browser, for: text)
        list += tabItems(browser, matching: text, limit: 5)
        list += inTabItems(browser, matching: text)
        list += bookmarkItems(browser, matching: text)
        list += commandItems(browser, matching: text, limit: 6)
        list += memoryItems(browser, matching: text)
        list += historyItems(browser, matching: text)
        return list
    }

    /// Pages read before whose meaning matches what's typed (when Max Q remembers what pages say).
    private func memoryItems(_ browser: BrowserModel, matching text: String) -> [Item] {
        guard AppSettings.shared.rememberPages, !browser.isPrivate, text.count >= 4 else { return [] }
        return PageMemory.shared.search(text).compactMap { match in
            guard let url = URL(string: match.page.url) else { return nil }
            return Item(id: "memory:\(match.page.url)", section: .memory, title: match.page.title,
                        detail: ResultDate.label(match.page.date, isDay: false), glyph: .site(url.host ?? ""),
                        snippet: AttributedString(match.snippet)) { [weak self] in
                self?.close()
                browser.navigate(.url(url))
            }
        }
    }

    /// What can be done with the words themselves: a shortcut, opening an address, searching,
    /// asking Grok.
    private func topItems(_ browser: BrowserModel, for text: String) -> [Item] {
        var list: [Item] = []
        if let (bang, words) = Bangs.parse(text) {
            list.append(Item(id: "bang", section: .top, title: words.isEmpty ? bang.name : words,
                             detail: bang.action(for: words), glyph: .site(bang.host), shortcut: "!" + bang.trigger) { [weak self] in
                self?.close()
                browser.follow(bang, words: words)
            })
        }
        if case .url(let url) = AddressInput.classify(text) {
            list.append(Item(id: "open", section: .top, title: AddressSuggestion.displayURL(url), detail: String(localized: "Open website"),
                             glyph: .site(url.host ?? "")) { [weak self] in
                self?.close()
                browser.navigate(.url(url))
            })
        }
        let engine = AppSettings.shared.searchEngine.name
        list.append(Item(id: "search", section: .top, title: text, detail: String(localized: "Search \(engine)"), glyph: .icon(.search)) { [weak self] in
            self?.close()
            browser.navigate(.search(text))
        })
        list.append(Item(id: "ask", section: .top, title: text, detail: String(localized: "Ask Grok"), glyph: .icon(.bubble), shortcut: "⌘↩") { [weak self] in
            self?.askGrok()
        })
        return list
    }

    private func tabItems(_ browser: BrowserModel, matching text: String, limit: Int) -> [Item] {
        let tabs = browser.allTabs.filter { !$0.isHome }
        let matched = text.isEmpty ? tabs : tabs.filter { tab in
            Self.matches(tab.displayTitle, text) || Self.matches(tab.url?.absoluteString ?? "", text)
                || Self.matches(tab.nativeSearch ?? "", text)
        }
        return matched.prefix(limit).map { tab in
            let current = tab.id == browser.selectedTabID
            let search = isSearch(tab)
            return Item(id: "tab:\(tab.id)", section: .tabs, title: tabTitle(tab),
                        detail: current ? String(localized: "On screen") : (search ? "Max Q" : tab.url.flatMap { $0.host }.map(DomainDisplay.shortHost)),
                        glyph: search ? .icon(.search) : .site(tab.url?.host ?? "")) { [weak self] in
                self?.close()
                browser.select(tab)
            }
        }
    }

    /// Max Q's own results page (also before a restored tab has loaded it).
    private func isSearch(_ tab: BrowserTab) -> Bool {
        tab.nativeSearch != nil || MaxQScheme.isNative(tab.url)
    }

    private func tabTitle(_ tab: BrowserTab) -> String {
        if let query = tab.nativeSearch ?? MaxQScheme.query(from: tab.url) { return query }
        return tab.displayTitle
    }

    /// Pages already open that mention the words, with the words in context, and Grok for the
    /// questions a word search can't answer.
    private func inTabItems(_ browser: BrowserModel, matching text: String) -> [Item] {
        guard text.count >= 3 else { return [] }
        var list: [Item] = []
        for tab in browser.allTabs where !tab.isHome {
            guard let snippet = snippet(for: tab, matching: text) else { continue }
            // A tab whose title already matched is listed under Tabs.
            if Self.matches(tab.displayTitle, text) { continue }
            list.append(Item(id: "text:\(tab.id)", section: .inTabs, title: tabTitle(tab),
                             glyph: .site(tab.url?.host ?? ""), snippet: snippet) { [weak self] in
                self?.close()
                browser.select(tab)
                browser.findText = text
                browser.showFindBar()
                browser.find()
            })
            if list.count == 4 { break }
        }
        let pages = browser.allTabs.filter { !$0.isHome && $0.nativeSearch == nil }.count
        if pages >= 1 {
            list.append(Item(id: "askTabs", section: .inTabs, title: String(localized: "Ask Grok about your tabs"),
                             detail: pages == 1 ? String(localized: "1 page") : String(localized: "\(pages) pages"), glyph: .icon(.stack)) { [weak self] in
                self?.close()
                browser.askAboutTabs(text)
            })
        }
        return list
    }

    private func bookmarkItems(_ browser: BrowserModel, matching text: String) -> [Item] {
        guard !browser.isPrivate else { return [] }
        return BookmarkStore.shared.matches(for: text, limit: 4).compactMap { bookmark in
            guard let url = URL(string: bookmark.url) else { return nil }
            return Item(id: "bookmark:\(bookmark.url)", section: .bookmarks,
                        title: bookmark.title.isEmpty ? AddressSuggestion.displayURL(url) : bookmark.title,
                        detail: bookmark.folder.isEmpty ? url.host.map(DomainDisplay.shortHost) : bookmark.folder,
                        glyph: .site(url.host ?? "")) { [weak self] in
                self?.close()
                browser.navigate(.url(url))
            }
        }
    }

    private func historyItems(_ browser: BrowserModel, matching text: String) -> [Item] {
        guard !browser.isPrivate else { return [] }
        let open = Set(browser.allTabs.compactMap { $0.url?.absoluteString })
        return HistoryStore.shared.matches(for: text, limit: 4)
            .filter { !open.contains($0.url) }
            .compactMap { entry in
                guard let url = URL(string: entry.url) else { return nil }
                return Item(id: "history:\(entry.url)", section: .history,
                            title: entry.title.isEmpty ? AddressSuggestion.displayURL(url) : entry.title,
                            detail: url.host.map(DomainDisplay.shortHost), glyph: .site(url.host ?? "")) { [weak self] in
                    self?.close()
                    browser.navigate(.url(url))
                }
            }
    }

    // MARK: - Commands

    private struct Command {
        let title: String
        let icon: MQIcon
        var shortcut: String? = nil
        /// Other words it answers to.
        var keywords = ""
        var available = true
        let run: @MainActor () -> Void
    }

    private func commands(_ browser: BrowserModel) -> [Command] {
        let onPage = !(browser.selectedTab?.isHome ?? true) && browser.selectedTab?.nativeSearch == nil
        let tab = browser.selectedTab
        return [
            Command(title: String(localized: "New Tab"), icon: .plus, shortcut: "⌘T", keywords: "open") { browser.newTab() },
            Command(title: String(localized: "New Window"), icon: .stack, shortcut: "⌘N") { BrowserCommandRouter.openWindow?("browser") },
            Command(title: String(localized: "New Private Window"), icon: .ghost, shortcut: "⇧⌘N", keywords: "incognito") { BrowserCommandRouter.openWindow?("private") },
            Command(title: String(localized: "Reopen Closed Tab"), icon: .reload, shortcut: "⇧⌘T", keywords: "undo restore", available: browser.canReopenClosedTab) {
                browser.reopenClosedTab()
            },
            Command(title: browser.grokPanelVisible ? String(localized: "Hide Grok") : String(localized: "Show Grok"), icon: .bubble, shortcut: "⌘J", keywords: "panel chat") {
                withAnimation(Motion.smooth) { browser.toggleGrokPanel() }
            },
            Command(title: String(localized: "What Is X Saying About This Page"), icon: .link, shortcut: "⌥⌘X", keywords: "posts twitter reactions", available: onPage) {
                browser.whatXSays()
            },
            Command(title: String(localized: "Check Selection with Grok"), icon: .sealCheck, shortcut: "⇧⌘F",
                    keywords: "fact check verify true false claim", available: onPage) {
                browser.checkSelection()
            },
            Command(title: tab?.reader == nil ? String(localized: "Show Reader") : String(localized: "Hide Reader"), icon: .book, shortcut: "⇧⌘R",
                    keywords: "read article clean text listen", available: onPage && (tab?.readerAvailable == true || tab?.reader != nil)) {
                browser.toggleReader()
            },
            Command(title: String(localized: "Summarize This Video"), icon: .play, keywords: "youtube transcript key moments grok",
                    available: browser.onVideoPage) {
                browser.askAboutVideo()
            },
            Command(title: String(localized: "Key Moments of This Video"), icon: .play, keywords: "youtube chapters timestamps",
                    available: browser.onVideoPage) {
                browser.askAboutVideo(String(localized: "List the key moments of this video, each with its time and one line on what happens."))
            },
            Command(title: String(localized: "Research with Grok"), icon: .stack, keywords: "deep report investigate study sources budget") {
                browser.startResearch(browser.selectedTab?.searchQuery ?? browser.selectedTab?.nativeSearch ?? "")
            },
            Command(title: String(localized: "Let Grok Do It"), icon: .pointer, keywords: "agent task do click fill form automate act operator") {
                browser.showAgent()
            },
            Command(title: String(localized: "Stop Grok's Task"), icon: .stop, keywords: "agent stop cancel", available: browser.agent.isActive) {
                browser.agent.stop()
            },
            Command(title: String(localized: "Imagine"), icon: .image, keywords: "picture image generate draw art create") {
                browser.openNative(.imagine, inNewTab: true)
            },
            Command(title: String(localized: "New Collection"), icon: .stack, keywords: "save board folder list", available: !browser.isPrivate) {
                let id = CollectionStore.shared.create(String(localized: "New collection"))
                browser.openNative(.collection(id), inNewTab: true)
            },
            Command(title: String(localized: "Add Page to Collection"), icon: .stack, keywords: "save keep bookmark", available: onPage && !browser.isPrivate) {
                guard let tab = browser.selectedTab else { return }
                let item = CollectionItem(kind: .page, title: tab.title, url: tab.url, source: tab.url?.host)
                if let id = CollectionStore.shared.lastUsed { CollectionStore.shared.add(item, to: id) }
                else { CollectionStore.shared.addToNew(item, named: tab.title) }
                browser.showToast(String(localized: "Added to “\(CollectionStore.shared.collections.first?.name ?? "")”."))
            },
            Command(title: String(localized: "Summarize This Page"), icon: .lines, shortcut: "⌥⌘S", keywords: "grok tldr", available: onPage) {
                browser.summarizeCurrentPage()
            },
            Command(title: String(localized: "Summarize on This Mac"), icon: .lines, keywords: "apple intelligence free private local on-device",
                    available: onPage && OnDevice.isAvailable) {
                browser.summarizeOnDevice()
            },
            Command(title: String(localized: "Tidy Tabs Into Groups"), icon: .stack, keywords: "organize sort group clean topic",
                    available: browser.tabs.filter { !$0.isHome }.count >= 3) {
                browser.tidyTabs()
            },
            Command(title: String(localized: "Summarize All Tabs"), icon: .stack, keywords: "grok", available: browser.tabs.filter { !$0.isHome }.count > 1) {
                browser.summarizeAllTabs()
            },
            Command(title: tab?.translation == .translated ? String(localized: "Show Original") : String(localized: "Translate This Page"), icon: .translate, shortcut: "⌥⌘T",
                    keywords: "language", available: onPage) {
                if let tab { browser.translator.toggle(tab) }
            },
            Command(title: String(localized: "Find on Page"), icon: .search, shortcut: "⌘F", available: onPage) { browser.showFindBar() },
            Command(title: String(localized: "Copy Link"), icon: .link, keywords: "url address", available: tab?.url != nil && !(tab?.isHome ?? true)) {
                browser.copyLink()
            },
            Command(title: String(localized: "Share on X"), icon: .share, keywords: "post tweet", available: onPage) { browser.shareToX() },
            Command(title: String(localized: "Send to Grok Bot"), icon: .envelope, keywords: "email bot", available: onPage) { browser.sendToBot() },
            Command(title: String(localized: "Reload"), icon: .reload, shortcut: "⌘R", available: !(tab?.isHome ?? true)) { tab?.reload() },
            Command(title: browser.sidebarVisible ? String(localized: "Hide Sidebar") : String(localized: "Show Sidebar"), icon: .sidebar, shortcut: "⌃⌘S", keywords: "tabs") {
                withAnimation(Motion.smooth) { browser.sidebarVisible.toggle() }
            },
            Command(title: String(localized: "Zoom In"), icon: .zoomIn, shortcut: "⌘+", keywords: "bigger larger", available: onPage) { browser.zoom(0.1) },
            Command(title: String(localized: "Zoom Out"), icon: .zoomOut, shortcut: "⌘−", keywords: "smaller", available: onPage) { browser.zoom(-0.1) },
            Command(title: String(localized: "Open Grok"), icon: .bubble, keywords: "grok.com") { browser.openPinned(.grok) },
            Command(title: String(localized: "Open Grokipedia"), icon: .book, keywords: "encyclopedia wiki") { browser.openPinned(.grokipedia) },
            Command(title: String(localized: "Open X"), icon: .link, keywords: "twitter x.com") { browser.openPinned(.x) },
            Command(title: String(localized: "Settings"), icon: .gear, shortcut: "⌘,", keywords: "preferences options") {
                SettingsRouter.shared.section = .general
                BrowserCommandRouter.openSettings?()
            },
            Command(title: String(localized: "Grok Spending"), icon: .gear, keywords: "cost money limit budget usage") {
                SettingsRouter.shared.section = .grok
                BrowserCommandRouter.openSettings?()
            },
            Command(title: String(localized: "Set Up Max Q Again"), icon: .house, keywords: "welcome onboarding setup", available: !browser.isPrivate) {
                browser.showSetup()
            },
            Command(title: String(localized: "Import Bookmarks and History"), icon: .download, keywords: "chrome arc safari firefox brave edge switch",
                    available: !browser.isPrivate) {
                browser.showingImport = true
            },
        ].filter(\.available)
    }

    private func commandItems(_ browser: BrowserModel, matching text: String, limit: Int) -> [Item] {
        var list = commands(browser).map { command in
            Item(id: "command:\(command.title)", section: .commands, title: command.title, glyph: .icon(command.icon),
                 shortcut: command.shortcut) { [weak self] in
                self?.close()
                command.run()
            }
        }
        // Commands with choices of their own open them as a page.
        list.insert(Item(id: "command:effort", section: .commands, title: String(localized: "Grok Effort"),
                         detail: AppSettings.shared.grokEffort.title, glyph: .icon(.bolt)) { [weak self] in
            self?.push(.effort)
        }, at: min(5, list.count))
        list.append(Item(id: "command:theme", section: .commands, title: String(localized: "Theme"), detail: AppSettings.shared.appearance.label,
                         glyph: .icon(.system)) { [weak self] in
            self?.push(.theme)
        })
        if !browser.isPrivate {
            // Moving between spaces: Personal and the others.
            let spaces: [(UUID?, String)] = [(nil, String(localized: "Personal"))] + SpaceStore.shared.spaces.map { ($0.id, $0.name) }
            for (id, name) in spaces where id != browser.spaceID && spaces.count > 1 {
                list.append(Item(id: "command:space:\(id?.uuidString ?? "personal")", section: .commands,
                                 title: String(localized: "Switch to \(name)"), glyph: .icon(.stack)) { [weak self] in
                    self?.close()
                    browser.switchSpace(to: id)
                })
            }
            list.append(Item(id: "command:newSpace", section: .commands, title: String(localized: "New Space…"), glyph: .icon(.plus)) { [weak self] in
                self?.close()
                browser.newSpace()
            })
        }
        if browser.activeSplit != nil {
            list.append(Item(id: "command:closeSplit", section: .commands, title: String(localized: "Close Split View"), glyph: .icon(.splitView)) { [weak self] in
                self?.close()
                browser.closeSplit()
            })
            list.append(Item(id: "command:swapSplit", section: .commands, title: String(localized: "Swap Split Panes"), glyph: .icon(.splitView)) { [weak self] in
                self?.close()
                browser.swapSplit()
            })
        } else if browser.allTabs.filter({ !$0.isHome && $0.id != browser.selectedTabID }).count > 0 {
            list.append(Item(id: "command:split", section: .commands, title: String(localized: "Split View With…"), glyph: .icon(.splitView)) { [weak self] in
                self?.push(.splitWith)
            })
        }
        guard !text.isEmpty else { return Array(list.prefix(limit)) }
        let keywords = Dictionary(uniqueKeysWithValues: commands(browser).map { ("command:\($0.title)", $0.keywords) })
        let scored = list.compactMap { item -> (Item, Int)? in
            let title = item.title.lowercased(), needle = text.lowercased()
            if title.hasPrefix(needle) { return (item, 3) }
            if title.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return (item, 2) }
            if title.contains(needle) || (keywords[item.id] ?? "").contains(needle) || item.id == "command:effort" && "effort fast auto expert thinking".contains(needle)
                || item.id.hasPrefix("command:split") && "split side by side beside panes".contains(needle)
                || item.id == "command:theme" && "theme dark light appearance mode".contains(needle) {
                return (item, 1)
            }
            return nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private func effortChoices() -> [Item] {
        GrokEffort.allCases.filter { query.isEmpty || $0.title.lowercased().hasPrefix(query.lowercased()) }.map { effort in
            Item(id: "effort:\(effort.rawValue)", section: .choices, title: effort.title, detail: effort.detail,
                 glyph: .icon(.bolt), shortcut: GrokAccount.friendlyCost(GrokAccount.shared.typicalAnswerCost(effort, searchingX: false)),
                 checked: AppSettings.shared.grokEffort == effort) { [weak self] in
                AppSettings.shared.grokEffort = effort
                self?.close()
            }
        }
    }

    private func splitChoices(_ browser: BrowserModel) -> [Item] {
        browser.allTabs
            .filter { !$0.isHome && $0.id != browser.selectedTabID }
            .filter { query.isEmpty || Self.matches(tabTitle($0), query) || Self.matches($0.url?.absoluteString ?? "", query) }
            .map { tab in
                Item(id: "split:\(tab.id)", section: .choices, title: tabTitle(tab),
                     detail: isSearch(tab) ? "Max Q" : tab.url?.host.map(DomainDisplay.shortHost),
                     glyph: isSearch(tab) ? .icon(.search) : .site(tab.url?.host ?? "")) { [weak self] in
                    self?.close()
                    browser.splitView(with: tab)
                }
            }
    }

    private func themeChoices() -> [Item] {
        AppearancePreference.allCases.map { appearance in
            Item(id: "theme:\(appearance.rawValue)", section: .choices, title: appearance.label,
                 glyph: .icon(appearance == .light ? .sun : appearance == .dark ? .moon : .system),
                 checked: AppSettings.shared.appearance == appearance) { [weak self] in
                withAnimation(Motion.standard(0.3)) { AppSettings.shared.appearance = appearance }
                self?.close()
            }
        }
    }

    /// Words anywhere in the text, in any order ("starship verge" finds "The Verge: Starship …").
    nonisolated static func matches(_ text: String, _ query: String) -> Bool {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return words.allSatisfy { haystack.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
    }
}

/// SwiftUI's window and Settings openers, kept where the command bar can reach them.
@MainActor
enum BrowserCommandRouter {
    static var openWindow: ((String) -> Void)?
    static var openSettings: (() -> Void)?
}

extension DomainDisplay {
    /// "www.theverge.com" → "theverge.com".
    nonisolated static func shortHost(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
