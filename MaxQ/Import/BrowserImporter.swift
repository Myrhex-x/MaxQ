//
//  BrowserImporter.swift
//  Max Q
//
//  Brings bookmarks and history over from another browser on this Mac. Max Q can only read a
//  folder the user picks (it runs in a sandbox), so the user points it at the browser's own
//  folder, or at a Safari export, and Max Q looks inside for what it knows:
//    - Chrome, Arc, Brave, Edge, Vivaldi, Opera: "Bookmarks" (JSON) and "History" (SQLite), every
//      profile; Arc's pinned tabs from "StorableSidebar.json".
//    - Firefox: "places.sqlite".
//    - Safari: its export ("Bookmarks.html", "History.json") or its own "Bookmarks.plist" and
//      "History.db".
//    - Any browser's exported bookmarks file (the Netscape HTML every browser writes).
//  Databases are copied before they're read, so a browser that's open keeps its lock. Nothing
//  leaves the Mac. Passwords aren't touched.
//

import AppKit
import Foundation
import SQLite3

/// A browser Max Q can import from, when it's installed here.
nonisolated struct ImportSource: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let bundleID: String
    /// The folder to point the Open panel at, under the user's home.
    let folder: String
    /// Safari is read from its export.
    var isSafari: Bool { id == "safari" }

    static let all: [ImportSource] = [
        ImportSource(id: "chrome", name: "Chrome", bundleID: "com.google.Chrome", folder: "Library/Application Support/Google/Chrome"),
        ImportSource(id: "arc", name: "Arc", bundleID: "company.thebrowser.Browser", folder: "Library/Application Support/Arc"),
        ImportSource(id: "safari", name: "Safari", bundleID: "com.apple.Safari", folder: "Downloads"),
        ImportSource(id: "brave", name: "Brave", bundleID: "com.brave.Browser", folder: "Library/Application Support/BraveSoftware/Brave-Browser"),
        ImportSource(id: "edge", name: "Edge", bundleID: "com.microsoft.edgemac", folder: "Library/Application Support/Microsoft Edge"),
        ImportSource(id: "firefox", name: "Firefox", bundleID: "org.mozilla.firefox", folder: "Library/Application Support/Firefox"),
        ImportSource(id: "vivaldi", name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", folder: "Library/Application Support/Vivaldi"),
        ImportSource(id: "opera", name: "Opera", bundleID: "com.operasoftware.Opera", folder: "Library/Application Support/com.operasoftware.Opera"),
    ]
}

nonisolated struct ImportedHistory: Equatable, Sendable {
    let url: String
    let title: String
    let lastVisit: Date
    let visitCount: Int
}

nonisolated struct ImportResult: Equatable, Sendable {
    var bookmarks: [Bookmark] = []
    var history: [ImportedHistory] = []
    var isEmpty: Bool { bookmarks.isEmpty && history.isEmpty }
}

nonisolated enum BrowserImporter {
    /// The user's real home folder (in the sandbox, NSHomeDirectory() is the app's container).
    static var realHome: URL {
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    // MARK: - Reading a folder

    /// Everything Max Q can read in `folder` (or the file itself), looking a few levels down.
    static func read(_ location: URL) -> ImportResult {
        var result = ImportResult()
        for file in candidateFiles(in: location) {
            let name = file.lastPathComponent
            switch name {
            case "Bookmarks":
                if let data = try? Data(contentsOf: file) { result.bookmarks += chromiumBookmarks(data) }
            case "History":
                result.history += sqliteRows(file, chromiumHistorySQL, chromiumHistoryRow)
            case "StorableSidebar.json":
                if let data = try? Data(contentsOf: file) { result.bookmarks += arcSidebar(data) }
            case "places.sqlite":
                result.bookmarks += sqliteRows(file, firefoxBookmarksSQL, firefoxBookmarkRow)
                result.history += sqliteRows(file, firefoxHistorySQL, firefoxHistoryRow)
            case "Bookmarks.plist":
                if let data = try? Data(contentsOf: file) { result.bookmarks += safariBookmarks(data) }
            case "History.db":
                result.history += sqliteRows(file, safariHistorySQL, safariHistoryRow)
            case "History.json":
                if let data = try? Data(contentsOf: file) { result.history += safariExportHistory(data) }
            default:
                if file.pathExtension.lowercased() == "html", let html = try? String(contentsOf: file, encoding: .utf8),
                   html.contains("NETSCAPE-Bookmark-file") {
                    result.bookmarks += netscapeBookmarks(html)
                }
            }
        }
        result.bookmarks = unique(result.bookmarks, by: \.url)
        result.history = unique(result.history.sorted { $0.lastVisit > $1.lastVisit }, by: \.url)
        return result
    }

    /// Files worth reading under `location`, skipping caches and the like.
    static func candidateFiles(in location: URL) -> [URL] {
        let names: Set<String> = ["Bookmarks", "History", "StorableSidebar.json", "places.sqlite", "Bookmarks.plist",
                                  "History.db", "History.json"]
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [location] }
        let skip = ["cache", "service worker", "indexeddb", "local storage", "session storage", "blob_storage",
                    "extensions", "webstorage", "gpucache", "crashpad", "storage", "optimization", "safe browsing"]
        var found: [URL] = []
        guard let walker = FileManager.default.enumerator(at: location, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        for case let url as URL in walker {
            if walker.level > 4 { walker.skipDescendants(); continue }
            let name = url.lastPathComponent
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if skip.contains(where: { name.lowercased().contains($0) }) { walker.skipDescendants() }
                continue
            }
            if names.contains(name) || url.pathExtension.lowercased() == "html" { found.append(url) }
            if found.count > 60 { break }
        }
        return found
    }

    private static func unique<T>(_ items: [T], by key: KeyPath<T, String>) -> [T] {
        var seen = Set<String>()
        return items.filter { seen.insert($0[keyPath: key]).inserted }
    }

    // MARK: - Chromium

    static func chromiumBookmarks(_ data: Data) -> [Bookmark] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return [] }
        var found: [Bookmark] = []
        func walk(_ node: [String: Any], path: [String]) {
            let name = node["name"] as? String ?? ""
            if node["type"] as? String == "url", let url = node["url"] as? String {
                found.append(Bookmark(url: url, title: name, folder: path.joined(separator: " › ")))
            }
            for child in node["children"] as? [[String: Any]] ?? [] {
                walk(child, path: node["type"] as? String == "folder" ? path + [name] : path)
            }
        }
        for key in ["bookmark_bar", "other", "synced"] {
            if let root = roots[key] as? [String: Any] { walk(root, path: []) }
        }
        return found
    }

    static let chromiumHistorySQL = "SELECT url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT 6000"

    static func chromiumHistoryRow(_ row: OpaquePointer) -> ImportedHistory? {
        guard let url = text(row, 0) else { return nil }
        // Microseconds since 1601.
        let seconds = Double(sqlite3_column_int64(row, 3)) / 1_000_000 - 11_644_473_600
        return ImportedHistory(url: url, title: text(row, 1) ?? "", lastVisit: Date(timeIntervalSince1970: seconds),
                               visitCount: Int(sqlite3_column_int64(row, 2)))
    }

    /// Arc's pinned and favorite tabs: every saved page in its sidebar, with the space or folder
    /// it sits in.
    static func arcSidebar(_ data: Data) -> [Bookmark] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var found: [Bookmark] = []
        func walk(_ value: Any, folder: String) {
            if let dict = value as? [String: Any] {
                if let tab = dict["savedURL"] as? String {
                    let title = (dict["savedTitle"] as? String) ?? ""
                    found.append(Bookmark(url: tab, title: title, folder: folder))
                }
                let name = (dict["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                for child in dict.values { walk(child, folder: name ?? folder) }
            } else if let list = value as? [Any] {
                for child in list { walk(child, folder: folder) }
            }
        }
        walk(json, folder: "Arc")
        return found
    }

    // MARK: - Firefox

    static let firefoxBookmarksSQL = """
    SELECT p.url, b.title, parent.title FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id
    LEFT JOIN moz_bookmarks parent ON b.parent = parent.id WHERE b.type = 1
    """

    static func firefoxBookmarkRow(_ row: OpaquePointer) -> Bookmark? {
        guard let url = text(row, 0) else { return nil }
        return Bookmark(url: url, title: text(row, 1) ?? "", folder: text(row, 2) ?? "")
    }

    static let firefoxHistorySQL = "SELECT url, title, visit_count, last_visit_date FROM moz_places WHERE last_visit_date IS NOT NULL ORDER BY last_visit_date DESC LIMIT 6000"

    static func firefoxHistoryRow(_ row: OpaquePointer) -> ImportedHistory? {
        guard let url = text(row, 0) else { return nil }
        // Microseconds since 1970.
        let seconds = Double(sqlite3_column_int64(row, 3)) / 1_000_000
        return ImportedHistory(url: url, title: text(row, 1) ?? "", lastVisit: Date(timeIntervalSince1970: seconds),
                               visitCount: Int(sqlite3_column_int64(row, 2)))
    }

    // MARK: - Safari

    static func safariBookmarks(_ data: Data) -> [Bookmark] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        var found: [Bookmark] = []
        func walk(_ node: [String: Any], path: [String]) {
            if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf", let url = node["URLString"] as? String {
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""
                found.append(Bookmark(url: url, title: title, folder: path.joined(separator: " › ")))
            }
            var title = node["Title"] as? String ?? ""
            if title == "com.apple.ReadingList" { title = String(localized: "Reading List") }
            if title == "BookmarksBar" { title = String(localized: "Favorites") }
            if title == "BookmarksMenu" { title = String(localized: "Bookmarks Menu") }
            for child in node["Children"] as? [[String: Any]] ?? [] {
                walk(child, path: title.isEmpty ? path : path + [title])
            }
        }
        walk(plist, path: [])
        return found
    }

    static let safariHistorySQL = """
    SELECT i.url, v.title, i.visit_count, MAX(v.visit_time) FROM history_items i
    JOIN history_visits v ON v.history_item = i.id GROUP BY i.id ORDER BY 4 DESC LIMIT 6000
    """

    static func safariHistoryRow(_ row: OpaquePointer) -> ImportedHistory? {
        guard let url = text(row, 0) else { return nil }
        // Seconds since 2001.
        let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(row, 3))
        return ImportedHistory(url: url, title: text(row, 1) ?? "", lastVisit: date, visitCount: Int(sqlite3_column_int64(row, 2)))
    }

    /// Safari's "Export Browsing Data to File": a list of visits with their time in microseconds.
    static func safariExportHistory(_ data: Data) -> [ImportedHistory] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = (json["history"] as? [[String: Any]]) ?? (json["items"] as? [[String: Any]]) else { return [] }
        return items.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            let micro = (item["time_usec"] as? Double) ?? (item["time_usec"] as? Int).map(Double.init) ?? 0
            return ImportedHistory(url: url, title: item["title"] as? String ?? "",
                                   lastVisit: micro > 0 ? Date(timeIntervalSince1970: micro / 1_000_000) : .distantPast,
                                   visitCount: item["visit_count"] as? Int ?? 1)
        }
    }

    // MARK: - Netscape bookmarks HTML

    /// The bookmarks file every browser exports: <H3> folders, <A HREF> links, <DL> nesting.
    static func netscapeBookmarks(_ html: String) -> [Bookmark] {
        var found: [Bookmark] = []
        var folders: [String] = []
        var pendingFolder: String?
        let pattern = #"<DL>|</DL>|<H3[^>]*>(.*?)</H3>|<A\s[^>]*HREF="([^"]+)"[^>]*>(.*?)</A>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let whole = Range(match.range, in: html) else { continue }
            let token = html[whole].uppercased()
            if token.hasPrefix("<DL") {
                folders.append(pendingFolder ?? "")
                pendingFolder = nil
            } else if token.hasPrefix("</DL") {
                if !folders.isEmpty { folders.removeLast() }
            } else if token.hasPrefix("<H3"), let name = Range(match.range(at: 1), in: html) {
                pendingFolder = decode(String(html[name]))
            } else if let href = Range(match.range(at: 2), in: html), let title = Range(match.range(at: 3), in: html) {
                found.append(Bookmark(url: decode(String(html[href])), title: decode(String(html[title])),
                                      folder: folders.filter { !$0.isEmpty }.joined(separator: " › ")))
            }
        }
        return found
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - SQLite

    /// Rows of a query on a copy of the database (the browser may have the original open).
    static func sqliteRows<T>(_ file: URL, _ sql: String, _ map: (OpaquePointer) -> T?) -> [T] {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("maxq-import-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: copy.path + suffix) }
        }
        do {
            try FileManager.default.copyItem(at: file, to: copy)
            // A database in WAL mode keeps its latest writes beside it.
            for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: file.path + suffix) {
                try? FileManager.default.copyItem(atPath: file.path + suffix, toPath: copy.path + suffix)
            }
        } catch {
            return []
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let row = map(statement) { rows.append(row) }
        }
        return rows
    }

    private static func text(_ row: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(row, column) else { return nil }
        return String(cString: pointer)
    }
}
