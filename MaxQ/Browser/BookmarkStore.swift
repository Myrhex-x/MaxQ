//
//  BookmarkStore.swift
//  Max Q
//
//  Bookmarks brought over from another browser. Max Q has no bookmarks bar: they come back as
//  suggestions in the address bar and the ⌘K bar, ranked above history, folder and all. Stays on
//  this Mac; removed from Settings.
//

import Foundation
import Observation

nonisolated struct Bookmark: Codable, Hashable, Identifiable, Sendable {
    var id: String { url }
    let url: String
    var title: String
    /// The folder it was in, in its own browser ("Bookmarks Bar › Work").
    var folder: String
}

@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()

    private(set) var bookmarks: [String: Bookmark] = [:]
    private let fileName = "bookmarks.json"
    private let maxBookmarks = 20_000

    private init() {
        if let saved = Storage.load([Bookmark].self, from: fileName) {
            bookmarks = Dictionary(saved.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    var count: Int { bookmarks.count }

    /// Adds bookmarks, keeping any already there. Returns how many were new.
    @discardableResult
    func add(_ new: [Bookmark]) -> Int {
        var added = 0
        for bookmark in new where bookmarks[bookmark.url] == nil && bookmarks.count < maxBookmarks {
            guard let scheme = URL(string: bookmark.url)?.scheme, scheme == "https" || scheme == "http" else { continue }
            bookmarks[bookmark.url] = bookmark
            added += 1
        }
        Storage.save(Array(bookmarks.values), to: fileName)
        CloudSync.shared.noteChange(Self.syncName)
        return added
    }

    func removeAll() {
        bookmarks = [:]
        Storage.remove(fileName)
        CloudSync.shared.noteChange(Self.syncName)
    }

    /// Bookmarks matching what's typed: address and title, every word anywhere.
    func matches(for query: String, limit: Int = 3) -> [Bookmark] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return bookmarks.values
            .compactMap { bookmark -> (Bookmark, Int)? in
                let address = bookmark.url.lowercased()
                    .replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                    .replacingOccurrences(of: "www.", with: "")
                let title = bookmark.title.lowercased()
                guard words.allSatisfy({ address.contains($0) || title.contains($0) }) else { return nil }
                var score = 0
                if address.hasPrefix(words[0]) { score += 4 }
                if title.hasPrefix(words[0]) { score += 2 }
                score -= address.count / 40
                return (bookmark, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

// MARK: - iCloud

extension BookmarkStore: SyncedStore {
    static let syncName = "bookmarks"

    func syncItems() -> [String: Data] {
        bookmarks.mapValues { SyncCoding.encode($0) }
    }

    func applySynced(_ items: [String: Data]) {
        bookmarks = items.compactMapValues { SyncCoding.decode(Bookmark.self, $0) }
        Storage.save(Array(bookmarks.values), to: fileName)
    }

    func normalized(_ data: Data) -> Data? {
        SyncCoding.decode(Bookmark.self, data).map(SyncCoding.encode)
    }
}
