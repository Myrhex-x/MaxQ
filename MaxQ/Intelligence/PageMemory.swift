//
//  PageMemory.swift
//  Max Q
//
//  Ask your history: "the article about heat shields I read last week" finds it in ⌘K, by what the
//  page said rather than its exact words. When it's on (it's off until turned on), Max Q keeps the
//  opening of each page read in a normal window, with a description of its meaning made on this Mac
//  (Apple's sentence embeddings), in a file in Max Q's own folder. Nothing is sent anywhere.
//
//  Never kept: private windows, pages with a password field, mail, banking, sign-in and checkout
//  pages, Max Q's own pages. Settings forgets everything at once.
//

import Foundation
import NaturalLanguage
import Observation

nonisolated struct RememberedPage: Codable, Equatable, Sendable {
    let url: String
    var title: String
    var date: Date
    var language: String
    /// The page's opening, for the snippet and words.
    var text: String
    /// The meaning of the title and opening (Float32s, little-endian), in `language`'s space.
    var vector: Data
}

@MainActor
@Observable
final class PageMemory {
    static let shared = PageMemory()

    private(set) var count = 0
    @ObservationIgnored private var pages: [RememberedPage] = []
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let fileName = "PageMemory.json"
    private static let limit = 2_500

    private init() {}

    /// Reads the file once, so `count` is right (Settings shows it).
    func prepare() { load() }

    private func load() {
        guard !loaded else { return }
        loaded = true
        pages = Storage.load([RememberedPage].self, from: Self.fileName) ?? []
        count = pages.count
    }

    // MARK: - Keeping

    /// Whether a page is never kept, from its address alone.
    nonisolated static func isExcluded(_ url: URL) -> Bool {
        guard url.scheme == "https" || url.scheme == "http", let host = url.host?.lowercased() else { return true }
        let hostWords = ["mail.", "accounts.", "login.", "auth.", "signin.", "checkout.", "pay.", "banking.", "secure.", "my."]
        if hostWords.contains(where: { host.hasPrefix($0) }) { return true }
        if ["paypal.com", "stripe.com", "bank", "credit", "chase.com", "wellsfargo.com", "revolut.com", "boursorama.com",
            "1password.com", "bitwarden.com", "lastpass.com", "icloud.com", "mail.google.com", "outlook.live.com"]
            .contains(where: { host.contains($0) }) { return true }
        let path = url.path.lowercased()
        return ["/login", "/signin", "/sign-in", "/account", "/checkout", "/cart", "/settings", "/password", "/billing", "/inbox"]
            .contains { path.hasPrefix($0) }
    }

    /// Keeps a page read in a normal window (when Remember What Pages Say is on).
    func remember(url: URL, title: String, text: String) {
        guard AppSettings.shared.rememberPages, !Self.isExcluded(url) else { return }
        let opening = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3_000))
        guard opening.count >= 200 else { return }
        load()
        let language = NLLanguageRecognizer.dominantLanguage(for: String(opening.prefix(800)))?.rawValue ?? "en"
        let meaning = title + ". " + String(opening.prefix(900))
        guard let vector = Self.vector(for: meaning, language: language) else { return }
        let entry = RememberedPage(url: url.absoluteString, title: title, date: Date(), language: language, text: opening, vector: vector)
        pages.removeAll { $0.url == entry.url }
        pages.append(entry)
        if pages.count > Self.limit { pages.removeFirst(pages.count - Self.limit) }
        count = pages.count
        scheduleSave()
    }

    func forgetAll() {
        pages = []
        count = 0
        loaded = true
        saveTask?.cancel()
        Storage.remove(Self.fileName)
    }

    // MARK: - Finding

    struct Match: Identifiable {
        var id: String { page.url }
        let page: RememberedPage
        let score: Double
        /// The sentence that best matches, for the snippet.
        let snippet: String
    }

    /// The pages read whose meaning (or words) best match `query`.
    func search(_ query: String, limit: Int = 4) -> [Match] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return [] }
        load()
        guard !pages.isEmpty else { return [] }
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 })
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "en"
        let queryVector = Self.vector(for: text, language: language).map(Self.floats)
        var matches: [Match] = []
        for page in pages {
            var score = 0.0
            if let queryVector, page.language == language {
                score += max(0, Self.cosine(queryVector, Self.floats(page.vector))) * 0.75
            }
            if !words.isEmpty {
                let haystack = (page.title + " " + page.text).lowercased()
                let found = words.filter { haystack.contains($0) }.count
                score += Double(found) / Double(words.count) * 0.4
            }
            // A little for recency: last week ahead of last year.
            score += max(0, 0.05 - Date().timeIntervalSince(page.date) / (86_400 * 365) * 0.05)
            if score > 0.32 { matches.append(Match(page: page, score: score, snippet: Self.snippet(page.text, words: words))) }
        }
        return Array(matches.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: - Meaning

    nonisolated static func vector(for text: String, language: String) -> Data? {
        let lang = NLLanguage(rawValue: language)
        guard let embedding = NLEmbedding.sentenceEmbedding(for: lang) ?? (lang == .english ? nil : NLEmbedding.sentenceEmbedding(for: .english)),
              let values = embedding.vector(for: String(text.prefix(1_000))) else { return nil }
        let floats = values.map { Float($0) }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    nonisolated static func floats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    nonisolated static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            na += a[index] * a[index]
            nb += b[index] * b[index]
        }
        guard na > 0, nb > 0 else { return 0 }
        return Double(dot / (na.squareRoot() * nb.squareRoot()))
    }

    nonisolated static func snippet(_ text: String, words: Set<String>) -> String {
        let sentences = text.split(whereSeparator: { ".!?\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 30 }
        let best = sentences.max { a, b in
            words.filter { a.lowercased().contains($0) }.count < words.filter { b.lowercased().contains($0) }.count
        } ?? sentences.first ?? String(text.prefix(140))
        return String(best.prefix(160))
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = pages
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            Storage.save(snapshot, to: Self.fileName)
        }
    }
}
