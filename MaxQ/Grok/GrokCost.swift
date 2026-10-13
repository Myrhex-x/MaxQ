//
//  GrokCost.swift
//  Max Q
//
//  What a Grok answer costs on the user's own key, and the controls that keep it small:
//    - How hard Grok works (Fast, Auto, Expert): which model, how much it reasons, how many rounds
//      of searching it may take.
//    - When Grok may search X, which SpaceXAI bills by the post read ($5 per 1,000 posts, about
//      $0.10 a search, ten times the rest of a short answer).
//    - A monthly limit, kept on this Mac from SpaceXAI's own per-request cost figures.
//  Prices from docs.x.ai (October 2026); the live model list overrides them when it has them.
//

import Foundation

/// How hard Grok works on an answer, in grok.com's words.
nonisolated enum GrokEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Grok 4.3 without reasoning, one round of web search.
    case fast
    /// Grok 4.3 reasoning lightly, up to two rounds of search.
    case auto
    /// Grok 4.7, SpaceXAI's most capable model, reasoning at medium, up to four rounds.
    case expert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: String(localized: "Fast")
        case .auto: String(localized: "Auto")
        case .expert: String(localized: "Expert")
        }
    }

    /// One line on what it does, for menus.
    var detail: String {
        switch self {
        case .fast: String(localized: "Quick answers, no thinking first")
        case .auto: String(localized: "Thinks a little, then answers")
        case .expert: String(localized: "Thinks hard, with Grok 4.7")
        }
    }

    /// Models to use, best first. The live model list decides what's actually available.
    var preferredModels: [String] {
        switch self {
        case .fast: ["grok-4.3", "grok-4.20-0309-non-reasoning"]
        case .auto: ["grok-4.3", "grok-4.20-0309-reasoning"]
        case .expert: ["grok-4.7", "grok-4.6", "grok-4.5", "grok-4.3"]
        }
    }

    /// The reasoning effort to ask for on `model`, when the model takes one. Grok 4.3 can skip
    /// reasoning entirely; Grok 4.7 always reasons, so Expert asks for medium, not its default high.
    func reasoningEffort(for model: String, supported: [String]?) -> String? {
        let wanted: [String] = switch self {
        case .fast: ["none", "low"]
        case .auto: ["low"]
        case .expert: model.hasPrefix("grok-4.3") ? ["high"] : ["medium", "high"]
        }
        let accepted = supported ?? Self.knownEfforts(for: model)
        return wanted.first { accepted.contains($0) }
    }

    /// Reasoning efforts SpaceXAI documents for its models, for when the model list hasn't said.
    static func knownEfforts(for model: String) -> [String] {
        if model.hasPrefix("grok-4.3") { return ["none", "low", "medium", "high", "xhigh"] }
        if model.hasPrefix("grok-4.7") || model.hasPrefix("grok-4.6") { return ["low", "medium", "high", "xhigh"] }
        if model.hasPrefix("grok-4.5") { return ["low", "medium", "high"] }
        return []
    }

    /// Rounds of searching an answer on the results page may take.
    var searchTurns: Int {
        switch self {
        case .fast: 1
        case .auto: 2
        case .expert: 4
        }
    }

    /// Rounds of tool use for a chat message in the side panel.
    var chatTurns: Int {
        switch self {
        case .fast: 2
        case .auto: 4
        case .expert: 6
        }
    }

    /// A typical results-page answer without X, before this Mac has seen real ones: about 6,000
    /// tokens read (the search results count), 250 written, the reasoning, and the web searches.
    var typicalCostUSD: Double {
        switch self {
        case .fast: 0.013
        case .auto: 0.018
        case .expert: 0.055
        }
    }
}

/// When Grok's answers on the results page may search X.
nonisolated enum XSearchPolicy: String, CaseIterable, Identifiable, Sendable {
    case off
    /// Only for searches about news, live events and reactions.
    case news
    case always

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: String(localized: "Never")
        case .news: String(localized: "For news")
        case .always: String(localized: "Always")
        }
    }

    /// Whether an answer to `query` gets the X search tool.
    func allows(_ query: String) -> Bool {
        switch self {
        case .off: false
        case .news: NewsDetector.isNews(query)
        case .always: true
        }
    }
}

/// Spots searches about news, live events and what people are saying, the searches where posts
/// on X earn their cost. Pure logic, unit-tested.
nonisolated enum NewsDetector {
    /// Words that mark a search as news. Kept narrow on purpose: "live", "down" or "war" alone
    /// would send everyday searches ("where does she live") to a paid X search.
    private static let words: Set<String> = [
        "news", "today", "tonight", "yesterday", "latest", "breaking", "update", "updates", "announced",
        "announcement", "reaction", "reactions", "tweet", "tweets", "tweeted", "viral", "trending", "rumor",
        "rumors", "rumour", "rumours", "leak", "leaks", "leaked", "outage", "election", "elections", "earnings",
        "happening", "controversy", "lawsuit", "arrested", "resigns", "resigned", "verdict", "ceasefire",
        "livestream", "actualité", "actualités", "aujourd'hui",
    ]

    private static let phrases = [
        "what happened", "what is happening", "what's happening", "is it down", "is down", "right now",
        "this week", "this morning", "live score", "live updates", "release date", "what are people saying",
        "people saying", "on x", "on twitter",
    ]

    static func isNews(_ query: String) -> Bool {
        let lower = query.lowercased()
        // A handle or a hashtag ("@SpaceX", "#starship"), not "c#" or an email address.
        if lower.contains("x.com") || lower.range(of: #"(^|\s)[@#][a-z0-9_]"#, options: .regularExpression) != nil { return true }
        let tokens = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        // Whole words only: "on x" mustn't match "on xenon".
        let padded = " " + tokens.joined(separator: " ") + " "
        if phrases.contains(where: { padded.contains(" \($0) ") }) { return true }
        if tokens.contains(where: words.contains) { return true }
        // This year or last: "starship 2026".
        let year = Calendar.current.component(.year, from: Date())
        return tokens.contains(String(year)) || tokens.contains(String(year - 1))
    }
}

/// Prices SpaceXAI charges for its search tools (docs.x.ai pricing, October 2026).
nonisolated enum GrokToolPrices {
    static let webSearchCall = 0.005
    static let xPostRead = 0.005
    static let xProfileRead = 0.01
    /// A typical X search: about 19 posts read in SpaceXAI's own example.
    static let typicalXSearch = 0.10
}

/// US dollars, written the way the user's language writes them: "$1.20" in English, "1,20 $US" in
/// French. SpaceXAI bills in dollars whatever the language.
nonisolated enum Money {
    static func usd(_ value: Double, digits: Int = 2, locale: Locale = .current) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(digits)).locale(locale))
    }
}

extension GrokAccount {
    /// Money as a person says it: "under 1¢", "about 2¢", "$1.20".
    nonisolated static func friendlyCost(_ usd: Double, approximate: Bool = false) -> String {
        if usd < 0.005 { return approximate ? String(localized: "under 1¢") : String(localized: "<1¢") }
        if usd < 0.995 {
            let cents = Int((usd * 100).rounded())
            return approximate ? String(localized: "about \(cents)¢") : String(localized: "\(cents)¢")
        }
        let dollars = Money.usd(usd)
        return approximate ? String(localized: "about \(dollars)") : dollars
    }
}
