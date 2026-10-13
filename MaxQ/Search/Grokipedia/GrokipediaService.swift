//
//  GrokipediaService.swift
//  Max Q
//
//  Turns a search into a Grokipedia card: decides whether the query is a topic, finds the right
//  article (curated slug, inferred slug, Wikipedia canonical title, then a typo correction),
//  checks the article is really about the query, and assembles the card. Adapted from Searxly's
//  knowledge panel resolver. A wrong card is worse than no card, so every uncertain step is gated.
//

import Foundation

nonisolated struct KnowledgeFact: Equatable, Identifiable, Sendable {
    var id: String { label }
    let label: String
    let value: String
}

nonisolated struct GrokipediaCard: Equatable, Sendable {
    let query: String
    let title: String
    let summary: String
    let facts: [KnowledgeFact]
    let articleURL: URL
    /// Lead image candidates from the article itself (assets CDN), tried in order.
    let imageCandidates: [URL]
    let officialSite: URL?
    let kind: OfficialEntityDatabase.EntityKind?
    /// Top-level sections, linked into the article.
    var sections: [GrokipediaSection] = []
    /// When Grokipedia last updated the article, which its page calls fact-checked by Grok.
    var updated: Date? = nil
    /// The whole article, set natively in the Grokipedia tab.
    var article: GrokipediaArticle? = nil

    /// The page's name in its address ("SpaceX_Starship").
    var page: String { articleURL.lastPathComponent }

    var officialSiteLabel: String? {
        guard let host = officialSite?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

nonisolated enum GrokipediaService {

    /// The card for `query`, or nil when it isn't a topic or Grokipedia has no matching article.
    static func card(for query: String) async -> GrokipediaCard? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, KnowledgeQueryDetector.classify(trimmed) != .none else { return nil }

        if let cached = cachedResult(for: trimmed) { return cached.card }

        let (card, cacheable) = await resolveUncached(query: trimmed)
        // A miss is only remembered when it was a confirmed "no article", never after a network blip.
        if cacheable { store(card, for: trimmed) }
        return card
    }

    private static func resolveUncached(query: String) async -> (card: GrokipediaCard?, cacheable: Bool) {
        let entity = EntityQueryMatcher.bestEntity(for: query)
        let subject = EntityQueryMatcher.strippedSubject(from: query)
        let resolution = await resolveArticle(subject: subject, entity: entity)
        guard let (slug, snippet) = resolution.hit else {
            return (nil, !resolution.sawTransientFailure)
        }

        return (makeCard(query: query, subject: subject, slug: slug, snippet: snippet, entity: entity), true)
    }

    /// The card for one article, from its page name: a link from another Grokipedia article, so
    /// it needs no checking against the search.
    static func card(forPage page: String, query: String) async -> GrokipediaCard? {
        guard case .article(let snippet) = await GrokipediaArticleClient.fetchOutcome(slug: page) else { return nil }
        return makeCard(query: query, subject: query, slug: page, snippet: snippet,
                        entity: EntityQueryMatcher.bestEntity(for: snippet.title))
    }

    private static func makeCard(query: String, subject: String, slug: String, snippet: GrokipediaArticleSnippet,
                                 entity: OfficialEntityDatabase.OfficialEntity?) -> GrokipediaCard? {
        let paragraph = snippet.firstParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard paragraph.count >= 48, let articleURL = URL(string: GrokipediaSlugCatalog.pageURL(for: slug)) else {
            return nil
        }

        var kind = entity?.entityKind
        if kind == nil, describesPerson(snippet.facts) { kind = .person }

        let title = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return GrokipediaCard(
            query: query,
            title: title.isEmpty ? displaySubject(subject) : title,
            summary: paragraph,
            facts: Array(snippet.facts.prefix(10)),
            articleURL: articleURL,
            imageCandidates: snippet.imageURLs,
            officialSite: entity.flatMap { URL(string: $0.primaryURL) },
            kind: kind,
            sections: snippet.sections,
            updated: snippet.updated,
            article: snippet.article
        )
    }

    // MARK: - Finding the article

    private static func resolveArticle(subject: String, entity: OfficialEntityDatabase.OfficialEntity?)
        async -> (hit: (slug: String, snippet: GrokipediaArticleSnippet)?, sawTransientFailure: Bool) {
        var tried = Set<String>()
        var sawTransient = false

        /// Fetches the slug's article and returns it only when the match can be trusted: a curated
        /// source, or an article that passes the relevance gate against the query.
        func attempt(_ slug: String?, trusted: Bool) async -> (String, GrokipediaArticleSnippet)? {
            guard let slug, !slug.isEmpty, tried.insert(slug).inserted else { return nil }
            let snippet: GrokipediaArticleSnippet
            switch await GrokipediaArticleClient.fetchOutcome(slug: slug) {
            case .article(let fetched): snippet = fetched
            case .notFound: return nil
            case .transient: sawTransient = true; return nil
            }
            guard trusted || isArticleRelevant(subject: subject, slug: slug, snippet: snippet) else { return nil }
            return (slug, snippet)
        }

        // 1. Curated entity (strong match only, so trusted).
        if let hit = await attempt(GrokipediaSlugCatalog.slug(for: entity), trusted: true) { return (hit, sawTransient) }

        // 2. A subject the catalog names itself (trusted). Nothing else is guessed from the words.
        if GrokipediaSlugCatalog.hasExplicitSlug(for: subject) || OfficialEntityDatabase.entity(for: subject) != nil,
           let hit = await attempt(GrokipediaSlugCatalog.slug(forSubject: subject), trusted: true) {
            return (hit, sawTransient)
        }

        // 3. Grokipedia's own search: its first results that are about the subject.
        let found = await GrokipediaSearchClient.results(for: subject)
        for result in found.prefix(3) where isTitleRelevant(subject: subject, title: result.title) {
            if let hit = await attempt(result.slug, trusted: false) { return (hit, sawTransient) }
        }

        // 4. Typo rescue: Grokipedia's top result, or Wikipedia's suggestion searched on Grokipedia,
        //    when it's a likely fix for a misspelling.
        if let first = found.first, isLikelyTypoCorrection(subject: subject, title: first.title),
           let hit = await attempt(first.slug, trusted: true) {
            return (hit, sawTransient)
        }
        if found.isEmpty, let correction = await WikipediaTitleResolver.canonicalTitles(for: subject, limit: 1).first,
           isLikelyTypoCorrection(subject: subject, title: correction),
           let match = await GrokipediaSearchClient.results(for: correction).first(where: { isTitleRelevant(subject: correction, title: $0.title) }),
           let hit = await attempt(match.slug, trusted: true) {
            return (hit, sawTransient)
        }

        return (nil, sawTransient)
    }

    // MARK: - Relevance

    static func isArticleRelevant(subject: String, slug: String, snippet: GrokipediaArticleSnippet) -> Bool {
        let titleSource = snippet.title.isEmpty ? slug.replacingOccurrences(of: "_", with: " ") : snippet.title
        let titleTokens = EntityQueryMatcher.significantTokens(titleSource)
        let slugTokens = EntityQueryMatcher.significantTokens(slug.replacingOccurrences(of: "_", with: " "))
        return subjectMatches(subject: subject, groups: [titleTokens, slugTokens])
    }

    static func isTitleRelevant(subject: String, title: String) -> Bool {
        subjectMatches(subject: subject, groups: [EntityQueryMatcher.significantTokens(title)])
    }

    /// Every query token appears in the article's tokens and the article adds at most one more
    /// ("tor" → "Tor Project" yes, "barack obama" → "Barack Obama 2008 Presidential Campaign" no),
    /// or the de-spaced query equals the de-spaced title ("torproject" == "tor project").
    static func subjectMatches(subject: String, groups: [[String]]) -> Bool {
        let queryTokens = EntityQueryMatcher.significantTokens(subject)
        guard !queryTokens.isEmpty else { return false }
        let querySet = Set(queryTokens)
        for group in groups where !group.isEmpty {
            if querySet.isSubset(of: Set(group)) && group.count <= queryTokens.count + 1 { return true }
        }
        let joined = queryTokens.joined()
        return !joined.isEmpty && groups.contains { $0.joined() == joined }
    }

    static func isLikelyTypoCorrection(subject: String, title: String) -> Bool {
        let a = EntityQueryMatcher.significantTokens(subject).joined(separator: " ")
        let b = EntityQueryMatcher.significantTokens(title).joined(separator: " ")
        guard !a.isEmpty, !b.isEmpty, a != b else { return false }
        let distance = editDistance(a, b)
        // At most two edits, and at most one per five characters: "elon muskk" → "Elon Musk" is
        // a fix, while a short word like "mars" can't be "corrected" into "bars".
        return distance <= 2 && distance * 5 <= a.count
    }

    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    private static let personLabels: Set<String> = [
        "born", "birth date", "birthplace", "birth place", "date of birth", "place of birth",
        "died", "death date", "nationality", "occupation", "spouse", "spouses",
        "children", "education", "alma mater", "known for", "years active", "partner",
    ]

    static func describesPerson(_ facts: [KnowledgeFact]) -> Bool {
        facts.contains { personLabels.contains($0.label.lowercased()) }
    }

    private static func displaySubject(_ subject: String) -> String {
        subject.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: - Cache

    private struct Cached {
        let card: GrokipediaCard?
        let storedAt: Date
    }

    nonisolated(unsafe) private static var cache: [String: Cached] = [:]
    private static let lock = NSLock()
    private static let positiveTTL: TimeInterval = 2 * 60 * 60
    private static let negativeTTL: TimeInterval = 5 * 60

    private static func key(_ query: String) -> String {
        query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cachedResult(for query: String) -> Cached? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[key(query)] else { return nil }
        let ttl = entry.card == nil ? negativeTTL : positiveTTL
        if Date().timeIntervalSince(entry.storedAt) > ttl {
            cache[key(query)] = nil
            return nil
        }
        return entry
    }

    private static func store(_ card: GrokipediaCard?, for query: String) {
        lock.lock(); defer { lock.unlock() }
        if cache.count >= 128, let oldest = cache.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            cache[oldest] = nil
        }
        cache[key(query)] = Cached(card: card, storedAt: Date())
    }
}
