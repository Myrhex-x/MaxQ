//
//  FollowStore.swift
//  Max Q
//
//  Searches the user follows. While Max Q is open it looks again every so often (the first time a
//  little after launch, then every twenty minutes, one search at a time) for news from the past
//  day, and keeps what it hasn't seen before as new. The sidebar shows how much is
//  new; opening the search shows it, and from then on it counts as seen. With notifications on, a
//  search with news says so.
//
//  Everything stays on this Mac: the searches, what was seen, what's new. The look-ups read the
//  outlets' own news feeds, without cookies, as the new-tab page does.
//

import Foundation
import Observation
import UserNotifications

/// Something new on a followed search.
nonisolated struct FollowItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case news, post }
    var id: String { url }
    let kind: Kind
    let title: String
    let url: String
    /// The outlet, or the account on X.
    let source: String
    let date: Date?
}

nonisolated struct FollowedSearch: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var query: String
    var created: Date
    var lastChecked: Date?
    /// When the user last opened the search: what came before counts as seen.
    var lastOpened: Date
    /// Addresses already seen (or there before the search was followed), newest last.
    var known: [String] = []
    /// What's new since the search was last opened, newest first.
    var fresh: [FollowItem] = []
    /// Say so with a notification when there's news.
    var notify = true

    init(query: String) {
        id = UUID()
        self.query = query
        created = Date()
        lastOpened = Date()
    }
}

@MainActor
@Observable
final class FollowStore {
    static let shared = FollowStore()

    private(set) var searches: [FollowedSearch] = []
    /// The search being looked up right now.
    private(set) var checking: UUID?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var running = false

    private static let fileName = "Following.json"
    /// How long between two looks at the same search.
    static let interval: TimeInterval = 20 * 60

    private init() {
        searches = Storage.load([FollowedSearch].self, from: Self.fileName) ?? []
    }

    /// Starts looking every so often (a minute after launch first).
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDue() }
        }
    }

    // MARK: - Following

    func isFollowing(_ query: String) -> Bool {
        searches.contains { Self.key($0.query) == Self.key(query) }
    }

    func search(for query: String) -> FollowedSearch? {
        searches.first { Self.key($0.query) == Self.key(query) }
    }

    func follow(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isFollowing(trimmed) else { return }
        searches.insert(FollowedSearch(query: trimmed), at: 0)
        save()
        start()
        // What's there now is the baseline: only what comes after is new.
        if let id = searches.first?.id { Task { await check(id) } }
    }

    func unfollow(_ query: String) {
        searches.removeAll { Self.key($0.query) == Self.key(query) }
        save()
    }

    func toggle(_ query: String) {
        isFollowing(query) ? unfollow(query) : follow(query)
    }

    func setNotify(_ id: UUID, _ on: Bool) {
        guard let index = searches.firstIndex(where: { $0.id == id }) else { return }
        searches[index].notify = on
        save()
        if on { Self.requestNotifications() }
    }

    /// The user opened the search: what's new is now seen. Returns what was new, to show once.
    @discardableResult
    func markOpened(_ query: String) -> [FollowItem] {
        guard let index = searches.firstIndex(where: { Self.key($0.query) == Self.key(query) }) else { return [] }
        let fresh = searches[index].fresh
        searches[index].fresh = []
        searches[index].lastOpened = Date()
        save()
        return fresh
    }

    /// New items across every followed search.
    var newCount: Int { searches.reduce(0) { $0 + $1.fresh.count } }

    // MARK: - Looking

    private func checkDue() {
        guard !running else { return }
        let now = Date()
        // The most overdue first, one at a time.
        let due = searches.filter { ($0.lastChecked.map { now.timeIntervalSince($0) } ?? .infinity) >= Self.interval }
            .sorted { ($0.lastChecked ?? .distantPast) < ($1.lastChecked ?? .distantPast) }
        guard let next = due.first else { return }
        Task { await check(next.id) }
    }

    /// Looks again now (the sidebar's Refresh).
    func refreshAll() {
        guard !running else { return }
        Task {
            for search in searches { await check(search.id) }
        }
    }

    func check(_ id: UUID) async {
        guard let search = searches.first(where: { $0.id == id }) else { return }
        running = true
        checking = id
        defer {
            running = false
            checking = nil
        }
        // The outlets' own feeds that mention the search (NewsFeeds.swift): free, and theirs to read.
        let found = await NewsFeedClient.matching(search.query, within: .day).prefix(20).map {
            FollowItem(kind: .news, title: $0.title, url: $0.url.absoluteString, source: $0.source, date: $0.date)
        }
        guard let index = searches.firstIndex(where: { $0.id == id }) else { return }
        let firstLook = searches[index].lastChecked == nil
        let known = Set(searches[index].known)
        let new = found.filter { !known.contains($0.url) }
        searches[index].lastChecked = Date()
        searches[index].known = Array((searches[index].known + new.map(\.url)).suffix(600))
        if !firstLook, !new.isEmpty {
            let fresh = (new + searches[index].fresh)
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            searches[index].fresh = Array(fresh.prefix(40))
            if searches[index].notify { Self.notify(searches[index], new: new) }
        }
        save()
    }

    // MARK: - Notifications

    static func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func notify(_ search: FollowedSearch, new: [FollowItem]) {
        let content = UNMutableNotificationContent()
        content.title = search.query
        let lead = new.first { $0.kind == .news } ?? new[0]
        content.body = new.count == 1 ? lead.title
            : String(localized: "\(new.count) new: \(lead.title)")
        content.threadIdentifier = search.id.uuidString
        content.userInfo = ["followedQuery": search.query]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - On disk

    private func save() {
        let snapshot = searches
        Task.detached(priority: .utility) { Storage.save(snapshot, to: Self.fileName) }
        CloudSync.shared.noteChange(Self.syncName)
    }

    /// Forgets every followed search (clearing browsing data).
    func removeAll() {
        searches = []
        Storage.remove(Self.fileName)
    }

    /// Searches compare without case or extra spaces.
    nonisolated static func key(_ query: String) -> String {
        query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - iCloud

/// What syncs of a followed search: the search itself. What was seen and what's new stay on each Mac.
nonisolated private struct SyncedFollow: Codable {
    let query: String
    let created: Date
    let notify: Bool
}

extension FollowStore: SyncedStore {
    static let syncName = "following"

    func syncItems() -> [String: Data] {
        Dictionary(searches.map { (Self.key($0.query), SyncCoding.encode(SyncedFollow(query: $0.query, created: $0.created, notify: $0.notify))) },
                   uniquingKeysWith: { first, _ in first })
    }

    func applySynced(_ items: [String: Data]) {
        let synced = items.compactMapValues { SyncCoding.decode(SyncedFollow.self, $0) }
        searches.removeAll { synced[Self.key($0.query)] == nil }
        for (key, follow) in synced {
            let index = searches.firstIndex { Self.key($0.query) == key } ?? {
                // Looked up at the next minute: what's there then is its starting point.
                searches.append(FollowedSearch(query: follow.query))
                return searches.count - 1
            }()
            searches[index].query = follow.query
            searches[index].created = follow.created
            searches[index].notify = follow.notify
        }
        searches.sort { $0.created > $1.created }
        save()
        start()
    }

    func normalized(_ data: Data) -> Data? {
        SyncCoding.decode(SyncedFollow.self, data).map(SyncCoding.encode)
    }
}
