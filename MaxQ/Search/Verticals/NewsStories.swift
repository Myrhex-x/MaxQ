//
//  NewsStories.swift
//  Max Q
//
//  Groups the same event as covered by several outlets into one story, with the lead headline and
//  the other sources behind it ("Full coverage · 6 sources"), and says how fresh a story is.
//
//  Headlines are reduced to their significant words (no stopwords, and none of the search's own
//  words, which every result shares), then merged greedily by overlap. Splitting two reports of one
//  event is better than merging two different events, so the threshold leans strict.
//

import Foundation

/// One event, as one or more outlets reported it.
nonisolated struct NewsStory: Identifiable, Hashable, Sendable, Codable {
    /// The highest-ranked report, the one shown.
    let lead: NewsItem
    /// Other outlets' reports of the same event, one per outlet.
    let others: [NewsItem]

    var id: String { lead.id }
    var reports: [NewsItem] { [lead] + others }
    var sourceCount: Int { 1 + others.count }

    /// The newest report's time.
    var latest: Date? { reports.compactMap(\.date).max() }

    /// The lead's picture, or the first other report's when the lead has none.
    var image: URL? { lead.image ?? others.first(where: { $0.image != nil })?.image }

    /// Several outlets within the last few hours.
    var isBreaking: Bool {
        let recent = reports.filter { ($0.date.map { -$0.timeIntervalSinceNow } ?? .infinity) < 3 * 3600 }
        return recent.count >= 3
    }
}

/// How recent a report is.
nonisolated enum NewsFreshness: Equatable, Sendable {
    /// Within the hour.
    case live
    /// Within the day.
    case today
    case thisWeek
    case older
    case unknown

    init(_ date: Date?, now: Date = Date()) {
        guard let date else { self = .unknown; return }
        let age = now.timeIntervalSince(date)
        self = if age < 3600 { .live } else if age < 86_400 { .today } else if age < 7 * 86_400 { .thisWeek } else { .older }
    }
}

nonisolated enum NewsClustering {
    /// Overlap at or above which two headlines are one story.
    static let threshold = 0.5

    /// Stories in the order their leads came in (the feed's own ranking). A second report from an
    /// outlet already in a story is dropped rather than listed twice.
    static func stories(_ items: [NewsItem], query: String) -> [NewsStory] {
        let strip = words(query, minimumLength: 1)
        var groups: [(tokens: Set<String>, lead: NewsItem, others: [NewsItem], outlets: Set<String>)] = []
        for item in items {
            let tokens = words(item.title, minimumLength: 3).subtracting(strip).subtracting(stopwords)
            var best = -1
            var bestScore = 0.0
            if !tokens.isEmpty {
                for (index, group) in groups.enumerated() {
                    let score = similarity(tokens, group.tokens)
                    if score > bestScore { bestScore = score; best = index }
                }
            }
            let outlet = outletKey(item)
            if best >= 0, bestScore >= threshold {
                if !groups[best].outlets.contains(outlet) {
                    groups[best].others.append(item)
                    groups[best].outlets.insert(outlet)
                }
            } else {
                groups.append((tokens, item, [], [outlet]))
            }
        }
        return groups.map { NewsStory(lead: $0.lead, others: $0.others) }
    }

    /// Jaccard overlap, or containment when one headline's words mostly sit inside the other's (at
    /// least three shared, so short headlines don't merge on a word or two).
    static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let shared = a.intersection(b).count
        guard shared > 0 else { return 0 }
        let jaccard = Double(shared) / Double(a.union(b).count)
        let containment = shared >= 3 ? Double(shared) / Double(min(a.count, b.count)) : 0
        return max(jaccard, containment)
    }

    /// Lowercased words without accents ("Élection" → "election"), any script.
    static func words(_ text: String, minimumLength: Int) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return Set(folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { $0.count >= minimumLength })
    }

    /// The outlet, by name or else by site.
    private static func outletKey(_ item: NewsItem) -> String {
        item.source.isEmpty ? item.host.lowercased() : item.source.lowercased()
    }

    static let stopwords: Set<String> = [
        // English
        "the", "and", "for", "that", "this", "with", "from", "says", "say", "what", "how", "why", "are", "was", "were",
        "has", "have", "had", "its", "his", "her", "she", "him", "not", "but", "you", "your", "out", "who", "new", "now",
        "get", "got", "will", "would", "could", "should", "about", "after", "over", "into", "than", "then", "them",
        "they", "their", "been", "being", "just", "more", "most", "some", "such", "only", "also", "did", "does", "done",
        "off", "per", "via", "amp", "here", "when", "where", "which", "while", "amid", "first", "latest", "news", "live",
        "update", "updates", "report", "reports",
        // French
        "les", "des", "une", "dans", "pour", "par", "sur", "avec", "qui", "que", "est", "son", "ses", "aux", "plus",
        "pas", "ont", "sont", "apres", "avant", "entre", "selon", "cette", "ces", "leur", "leurs",
    ]
}
