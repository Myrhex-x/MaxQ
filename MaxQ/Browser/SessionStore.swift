//
//  SessionStore.swift
//  Max Q
//
//  Remembers the open tabs of the last normal (non-private) window so they come back next launch.
//  Restored tabs load lazily: only the selected one fetches its page right away.
//

import Foundation

struct SavedSession: Codable {
    struct Tab: Codable {
        let url: String
        let title: String
        /// The tab group it's in.
        var group: String? = nil
    }
    struct Group: Codable {
        let id: String
        let name: String
        var collapsed = false
    }
    var tabs: [Tab]
    var groups: [Group]? = nil
    var selectedIndex: Int
    /// The pinned sites' tabs, by launcher, and the one on screen if a pinned site was.
    var pinned: [String: Tab]? = nil
    var selectedPinned: String? = nil
}

@MainActor
enum SessionStore {
    /// Each space keeps its tabs in a file of its own ("session.json" for Personal).
    private static func fileName(for space: UUID?) -> String {
        space.map { "session-\($0.uuidString).json" } ?? "session.json"
    }
    private static var saveTask: Task<Void, Never>?
    /// The first window to open claims the saved session; later windows start fresh.
    private static var claimed = false

    static func claimSavedSession(space: UUID? = nil) -> SavedSession? {
        guard !claimed else { return nil }
        claimed = true
        guard AppSettings.shared.restoreSession else { return nil }
        return Storage.load(SavedSession.self, from: fileName(for: space))
    }

    /// A space's tabs, when a window switches to it.
    static func load(space: UUID?) -> SavedSession? {
        Storage.load(SavedSession.self, from: fileName(for: space))
    }

    static func save(_ browser: BrowserModel) {
        guard let session = snapshot(browser) else { return }
        let name = fileName(for: browser.spaceID)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            Storage.save(session, to: name)
        }
    }

    /// Writes immediately (on quit, or leaving a space, when a delayed save would never run).
    static func saveNow(_ browser: BrowserModel) {
        guard let session = snapshot(browser) else { return }
        saveTask?.cancel()
        Storage.save(session, to: fileName(for: browser.spaceID))
    }

    static func clear(space: UUID) {
        Storage.remove(fileName(for: space))
    }

    private static func snapshot(_ browser: BrowserModel) -> SavedSession? {
        guard !browser.isPrivate else { return nil }
        var tabs: [SavedSession.Tab] = []
        var selected = 0
        let listSelection = browser.selectedPinned == nil ? browser.selectedTabID : browser.lastListSelection
        for tab in browser.tabs {
            if tab.id == listSelection { selected = max(tabs.count - 1, 0) }
            guard let url = tab.url, isRestorable(url) else { continue }
            if tab.id == listSelection { selected = tabs.count }
            tabs.append(SavedSession.Tab(url: url.absoluteString, title: tab.title, group: tab.group?.uuidString))
        }
        var pinned: [String: SavedSession.Tab] = [:]
        for (launcher, tab) in browser.pinnedTabs {
            guard let url = tab.url, isRestorable(url) else { continue }
            pinned[launcher.rawValue] = SavedSession.Tab(url: url.absoluteString, title: tab.title)
        }
        let groups = browser.groups.map { SavedSession.Group(id: $0.id.uuidString, name: $0.name, collapsed: $0.collapsed) }
        return SavedSession(tabs: tabs, groups: groups.isEmpty ? nil : groups, selectedIndex: min(selected, max(tabs.count - 1, 0)),
                            pinned: pinned.isEmpty ? nil : pinned,
                            selectedPinned: browser.selectedPinned.flatMap { pinned[$0.rawValue] == nil ? nil : $0.rawValue })
    }

    /// Web pages and Max Q's own search pages come back next launch; nothing else does.
    nonisolated static func isRestorable(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https", "http": true
        case MaxQScheme.scheme: url.host == "search" || MaxQScheme.nativePage(from: url) != nil
        default: false
        }
    }

    static func clear() {
        saveTask?.cancel()
        Storage.remove(fileName(for: nil))
        for space in SpaceStore.shared.spaces { Storage.remove(fileName(for: space.id)) }
    }
}
