//
//  HomeNewsFeed.swift
//  Max Q
//
//  The news under the new-tab page: today's headlines and a handful of topics, from the outlets'
//  own RSS feeds in the Mac's language (NewsFeeds.swift), grouped into stories (one event, the
//  outlets that covered it). Nothing loads until a new-tab page is on screen, the top of the feed first and the
//  topics as they scroll into view, two at a time. What loaded is kept for twenty minutes, and the
//  last feed is kept on disk so a new tab opens with it while the fresh one loads. Private windows
//  load nothing unless asked.
//

import Foundation
import Observation

@MainActor
@Observable
final class HomeNewsFeed {
    static let shared = HomeNewsFeed()

    struct Topic: Identifiable, Hashable {
        let id: String
        let title: String
        /// What's searched for the topic, in the Mac's language.
        let query: String
        let icon: MQIcon
        /// Hard news, which the top story is picked from.
        var hard = true
    }

    /// Every topic Max Q offers, in its own order. "top" is the day's headlines.
    static var topics: [Topic] {
        let french = Locale.current.language.languageCode?.identifier == "fr"
        func q(_ english: String, _ inFrench: String) -> String { french ? inFrench : english }
        return [
            Topic(id: "top", title: String(localized: "Headlines"), query: q("news", "actualité"), icon: .bolt),
            Topic(id: "world", title: String(localized: "World"), query: q("world news", "actualité internationale"), icon: .globe),
            Topic(id: "politics", title: String(localized: "Politics"), query: q("politics", "politique"), icon: .flag),
            Topic(id: "business", title: String(localized: "Business"), query: q("business economy", "économie"), icon: .stack),
            Topic(id: "technology", title: String(localized: "Technology"), query: q("technology", "technologie"), icon: .command),
            Topic(id: "ai", title: String(localized: "AI"), query: q("artificial intelligence", "intelligence artificielle"), icon: .bubble),
            Topic(id: "science", title: String(localized: "Science"), query: q("science", "science"), icon: .eye),
            Topic(id: "space", title: String(localized: "Space"), query: q("space launch rocket", "espace fusée"), icon: .arrowUpRight),
            Topic(id: "health", title: String(localized: "Health"), query: q("health", "santé"), icon: .heart),
            Topic(id: "sports", title: String(localized: "Sports"), query: q("sports", "sport"), icon: .play, hard: false),
            Topic(id: "culture", title: String(localized: "Culture"), query: q("entertainment culture", "culture"), icon: .image, hard: false),
        ]
    }

    /// The topics on show, in the user's order.
    var visibleTopics: [Topic] {
        let all = Self.topics
        guard let chosen = AppSettings.shared.homeNewsTopics else { return all }
        return chosen.compactMap { id in all.first { $0.id == id } }
    }

    private(set) var stories: [String: [NewsStory]] = [:]
    private(set) var loading: Set<String> = []
    private(set) var failed: Set<String> = []
    private(set) var updated: Date?
    private(set) var refreshing = false

    @ObservationIgnored private var fetched: [String: Date] = [:]
    @ObservationIgnored private var queue: [Topic] = []
    @ObservationIgnored private var running = 0
    @ObservationIgnored private var restored = false

    private static let lifetime: TimeInterval = 20 * 60
    /// The feeds' language: French outlets on a French Mac, English ones otherwise.
    private static var language: String { Locale.current.language.languageCode?.identifier == "fr" ? "fr" : "en" }
    private static let concurrency = 2
    private static let cacheName = "HomeNews.json"

    private init() {}

    // MARK: - Loading

    /// The feed is about to be seen: bring back the last one, then refresh what's stale.
    func prime() {
        if !restored {
            restored = true
            if let cache = Storage.load(Cache.self, from: Self.cacheName), cache.language == Self.language {
                stories = cache.stories
                updated = cache.date
                // Old enough to refresh, recent enough to show while it does.
                for id in cache.stories.keys { fetched[id] = cache.date }
            }
        }
        if let top = visibleTopics.first { loadIfNeeded(top) }
        for topic in visibleTopics.dropFirst().prefix(2) { loadIfNeeded(topic) }
    }

    /// Loads `topic` unless it's fresh, loading, or waiting its turn.
    func loadIfNeeded(_ topic: Topic) {
        if let date = fetched[topic.id], Date().timeIntervalSince(date) < Self.lifetime { return }
        guard !loading.contains(topic.id), !queue.contains(topic) else { return }
        queue.append(topic)
        pump()
    }

    /// Everything again, now (the Refresh button). What's on screen stays until it's replaced.
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        fetched = [:]
        failed = []
        for topic in visibleTopics where !loading.contains(topic.id) && !queue.contains(topic) {
            queue.append(topic)
        }
        pump()
    }

    private func pump() {
        while running < Self.concurrency, !queue.isEmpty {
            let topic = queue.removeFirst()
            running += 1
            loading.insert(topic.id)
            failed.remove(topic.id)
            Task { [weak self] in
                await self?.fetch(topic)
                guard let self else { return }
                self.running -= 1
                self.loading.remove(topic.id)
                if self.queue.isEmpty, self.running == 0 {
                    self.refreshing = false
                    self.save()
                }
                self.pump()
            }
        }
    }

    private func fetch(_ topic: Topic) async {
        let items = await NewsFeedClient.items(from: NewsFeedCatalog.feeds(for: topic.id))
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        if items.isEmpty {
            failed.insert(topic.id)
        } else {
            stories[topic.id] = Self.select(items, query: topic.query)
            fetched[topic.id] = Date()
            updated = Date()
        }
    }

    /// The freshest reports first (the last three days when there are enough), grouped into stories,
    /// the ones with pictures ahead of the rest.
    static func select(_ items: [NewsItem], query: String, now: Date = Date()) -> [NewsStory] {
        let recent = items.filter { ($0.date.map { now.timeIntervalSince($0) } ?? .infinity) < 3 * 86_400 }
        let pool = recent.count >= 6 ? recent : items
        let stories = NewsClustering.stories(pool, query: query)
        return Array(stories.enumerated().sorted { a, b in
            score(a.element, rank: a.offset, now: now) > score(b.element, rank: b.offset, now: now)
        }.map(\.element).prefix(12))
    }

    /// How much a story belongs at the top: how many outlets ran it, how fresh it is, whether it has
    /// a picture, and how recent it is among the rest.
    static func score(_ story: NewsStory, rank: Int, now: Date = Date()) -> Double {
        var score = Double(story.sourceCount) * 90 - Double(rank) * 6
        switch NewsFreshness(story.latest, now: now) {
        case .live: score += 240
        case .today: score += 140
        case .thisWeek: score += 20
        case .older, .unknown: break
        }
        if story.isBreaking { score += 300 }
        if story.image != nil { score += 60 }
        return score
    }

    // MARK: - The day's top story

    /// The one story at the top of the feed: the strongest among the hard-news topics.
    var topStory: NewsStory? {
        let hard = Set(Self.topics.filter(\.hard).map(\.id))
        let pool = stories.filter { hard.contains($0.key) }.values.flatMap { $0 }.filter { $0.image != nil }
        return pool.max { Self.score($0, rank: 0) < Self.score($1, rank: 0) }
    }

    /// A topic's stories, without the top story or ones an earlier topic already shows.
    func stories(for topic: Topic) -> [NewsStory] {
        var shown = Set<String>()
        if let top = topStory { top.reports.forEach { shown.insert($0.url.citationKey) } }
        for earlier in visibleTopics {
            if earlier.id == topic.id { break }
            for story in Array((stories[earlier.id] ?? []).prefix(Self.perTopic)) {
                shown.insert(story.lead.url.citationKey)
            }
        }
        return (stories[topic.id] ?? []).filter { !shown.contains($0.lead.url.citationKey) }
    }

    static let perTopic = 5

    // MARK: - Choosing topics

    func setVisible(_ id: String, _ visible: Bool) {
        var ids = visibleTopics.map(\.id)
        if visible, !ids.contains(id) {
            // Back in Max Q's own order.
            let order = Self.topics.map(\.id)
            ids.append(id)
            ids.sort { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
        } else if !visible {
            ids.removeAll { $0 == id }
        }
        AppSettings.shared.homeNewsTopics = ids
        if visible, let topic = Self.topics.first(where: { $0.id == id }) { loadIfNeeded(topic) }
    }

    // MARK: - On disk

    private struct Cache: Codable {
        let language: String
        let date: Date
        let stories: [String: [NewsStory]]
    }

    private func save() {
        let cache = Cache(language: Self.language, date: updated ?? Date(), stories: stories)
        Task.detached(priority: .utility) { Storage.save(cache, to: Self.cacheName) }
    }

    /// Forgets the feed, on disk too (clearing browsing data).
    func clear() {
        stories = [:]
        fetched = [:]
        updated = nil
        Storage.remove(Self.cacheName)
    }
}
