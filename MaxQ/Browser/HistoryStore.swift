//
//  HistoryStore.swift
//  Max Q
//
//  Local browsing history, used for address bar suggestions. Stays on this Mac; cleared from
//  Settings. Capped so it never grows without bound.
//

import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { url }
    let url: String
    var title: String
    var lastVisit: Date
    var visitCount: Int
}

@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var entries: [String: HistoryEntry] = [:]
    private let fileName = "history.json"
    private let maxEntries = 5000
    private var saveTask: Task<Void, Never>?

    private init() {
        if let saved = Storage.load([HistoryEntry].self, from: fileName) {
            entries = Dictionary(saved.map { ($0.url, $0) }, uniquingKeysWith: { a, b in a.lastVisit > b.lastVisit ? a : b })
        }
    }

    func recordVisit(url: URL, title: String) {
        guard let scheme = url.scheme, scheme == "https" || scheme == "http" else { return }
        let key = url.absoluteString
        if var existing = entries[key] {
            existing.visitCount += 1
            existing.lastVisit = Date()
            if !title.isEmpty { existing.title = title }
            entries[key] = existing
        } else {
            entries[key] = HistoryEntry(url: key, title: title, lastVisit: Date(), visitCount: 1)
        }
        trimIfNeeded()
        scheduleSave()
    }

    /// Merges history brought over from another browser: a page new here is added, one already
    /// here keeps its own record unless the other browser saw it more recently. The cap holds.
    /// Returns how many pages were new.
    @discardableResult
    func merge(_ imported: [ImportedHistory]) -> Int {
        var added = 0
        for item in imported {
            guard let scheme = URL(string: item.url)?.scheme, scheme == "https" || scheme == "http" else { continue }
            if var existing = entries[item.url] {
                guard item.lastVisit > existing.lastVisit else { continue }
                existing.lastVisit = item.lastVisit
                existing.visitCount += max(0, item.visitCount)
                if existing.title.isEmpty { existing.title = item.title }
                entries[item.url] = existing
            } else {
                entries[item.url] = HistoryEntry(url: item.url, title: item.title, lastVisit: item.lastVisit,
                                                 visitCount: max(1, item.visitCount))
                added += 1
            }
        }
        trimIfNeeded()
        flush()
        return added
    }

    func updateTitle(url: URL, title: String) {
        let key = url.absoluteString
        guard !title.isEmpty, var existing = entries[key], existing.title != title else { return }
        existing.title = title
        entries[key] = existing
        scheduleSave()
    }

    /// Best matches for what the user is typing: host and title matches, ranked by how often and
    /// how recently the page was visited.
    func matches(for query: String, limit: Int = 4) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 1 else { return [] }
        let now = Date()
        return entries.values
            .compactMap { entry -> (HistoryEntry, Double)? in
                let url = entry.url.lowercased()
                let stripped = url.replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                    .replacingOccurrences(of: "www.", with: "")
                var score = 0.0
                if stripped.hasPrefix(q) { score += 6 }
                else if stripped.contains(q) { score += 2 }
                if entry.title.lowercased().contains(q) { score += 2 }
                guard score > 0 else { return nil }
                let ageDays = now.timeIntervalSince(entry.lastVisit) / 86_400
                score += log(Double(entry.visitCount) + 1) * 1.5
                score -= min(ageDays / 30, 3)
                // Prefer short URLs (home pages) for prefix matches.
                score -= Double(stripped.count) / 200
                return (entry, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    var recent: [HistoryEntry] {
        entries.values.sorted { $0.lastVisit > $1.lastVisit }
    }

    func clear() {
        entries = [:]
        saveTask?.cancel()
        Storage.remove(fileName)
    }

    private func trimIfNeeded() {
        guard entries.count > maxEntries else { return }
        let keep = entries.values.sorted { $0.lastVisit > $1.lastVisit }.prefix(maxEntries)
        entries = Dictionary(keep.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            Storage.save(Array(self.entries.values), to: self.fileName)
        }
    }

    /// Writes immediately (used when the app quits).
    func flush() {
        saveTask?.cancel()
        Storage.save(Array(entries.values), to: fileName)
    }
}
