//
//  ImportTests.swift
//  Max Q
//

import Foundation
import SQLite3
import Testing
@testable import MaxQ

struct ImportTests {
    @Test func readsChromiumBookmarks() {
        let json = """
        {"roots": {"bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "children": [
            {"type": "url", "name": "SpaceX", "url": "https://www.spacex.com/"},
            {"type": "folder", "name": "Work", "children": [{"type": "url", "name": "Grok", "url": "https://grok.com/"}]}
        ]}, "other": {"type": "folder", "name": "Other", "children": []}}}
        """
        let bookmarks = BrowserImporter.chromiumBookmarks(Data(json.utf8))
        #expect(bookmarks.count == 2)
        #expect(bookmarks[1].title == "Grok")
        #expect(bookmarks[1].folder == "Bookmarks bar › Work")
    }

    @Test func readsArcsSidebar() {
        let json = """
        {"sidebar": {"containers": [{"items": ["id1", {"title": "Space", "data": {"tab": {"savedURL": "https://x.com/home", "savedTitle": "Home / X"}}}]}]}}
        """
        let bookmarks = BrowserImporter.arcSidebar(Data(json.utf8))
        #expect(bookmarks.first?.url == "https://x.com/home")
        #expect(bookmarks.first?.title == "Home / X")
    }

    @Test func readsTheNetscapeFile() {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
          <DT><H3>Bookmarks Bar</H3>
          <DL><p>
            <DT><A HREF="https://grokipedia.com/" ADD_DATE="1">Grokipedia &amp; more</A>
            <DT><H3>News</H3>
            <DL><p>
              <DT><A HREF="https://www.theverge.com/">The Verge</A>
            </DL><p>
          </DL><p>
        </DL><p>
        """
        let bookmarks = BrowserImporter.netscapeBookmarks(html)
        #expect(bookmarks.count == 2)
        #expect(bookmarks[0].title == "Grokipedia & more")
        #expect(bookmarks[0].folder == "Bookmarks Bar")
        #expect(bookmarks[1].folder == "Bookmarks Bar › News")
    }

    @Test func readsSafarisPlist() throws {
        let plist: [String: Any] = ["Children": [
            ["Title": "BookmarksBar", "WebBookmarkType": "WebBookmarkTypeList", "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://x.ai/", "URIDictionary": ["title": "xAI"]],
            ]],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let bookmarks = BrowserImporter.safariBookmarks(data)
        #expect(bookmarks.first?.url == "https://x.ai/")
        #expect(bookmarks.first?.folder == "Favorites")
    }

    @Test func readsChromiumHistoryFromACopy() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("History-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        var db: OpaquePointer?
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
        // 13,400,000,000,000,000 µs since 1601 is in 2025.
        let sql = """
        CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, last_visit_time INTEGER, hidden INTEGER);
        INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES ('https://grok.com/', 'Grok', 7, 13400000000000000, 0);
        INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES ('https://hidden.example/', 'Hidden', 1, 13300000000000000, 1);
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let rows = BrowserImporter.sqliteRows(file, BrowserImporter.chromiumHistorySQL, BrowserImporter.chromiumHistoryRow)
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Grok")
        #expect(rows.first?.visitCount == 7)
        let year = Calendar(identifier: .gregorian).component(.year, from: rows.first?.lastVisit ?? .distantPast)
        #expect(year == 2025)
    }
}
