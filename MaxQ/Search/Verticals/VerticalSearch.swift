//
//  VerticalSearch.swift
//  Max Q
//
//  News, images and videos for the results page: what each is, the filters, and where they come
//  from (the Brave Search API with the user's own key, see BraveSearch.swift). Results are kept
//  only while they're on screen.
//

import Foundation

// MARK: - Results

/// A news story: the headline, the outlet that ran it, when, and its picture.
nonisolated struct NewsItem: Identifiable, Hashable, Sendable, Codable {
    var id: String { url.absoluteString }
    let title: String
    let url: URL
    let excerpt: String
    /// The outlet ("Space.com").
    let source: String
    let date: Date?
    let image: URL?
    /// Found by the search API, not read from the outlet's own feed: its text and picture are the
    /// search's, shown but not kept.
    var viaSearchAPI = false

    private enum CodingKeys: String, CodingKey { case title, url, excerpt, source, date, image }

    var host: String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A picture found on the web, with the page it's on.
nonisolated struct ImageItem: Identifiable, Hashable, Sendable {
    var id: String { image.absoluteString }
    let title: String
    /// The picture itself, full size.
    let image: URL
    /// A small copy, quick to show (the search's own).
    let thumbnail: URL
    /// The page the picture is on.
    let page: URL
    let width: Int
    let height: Int

    var aspect: Double { width > 0 && height > 0 ? Double(width) / Double(height) : 1.5 }

    var site: String {
        let host = page.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A video, with its still, length and channel.
nonisolated struct VideoItem: Identifiable, Hashable, Sendable {
    var id: String { url.absoluteString }
    let title: String
    let url: URL
    let summary: String
    let still: URL?
    /// "8:39".
    let duration: String?
    /// Where it's hosted ("YouTube").
    let publisher: String?
    /// Who posted it (the channel).
    let uploader: String?
    let published: Date?
    let views: Int?

    /// The YouTube video's id, when it's one.
    var youTubeID: String? { WebResult(title: title, url: url, snippet: []).youTubeID }
}

/// A page of results and where the next one starts.
nonisolated struct VerticalPage<Item: Sendable>: Sendable {
    let items: [Item]
    /// Where the next page starts, if there is one.
    let next: Int?
}

// MARK: - Filters

/// The picture filters Max Q applies to the pictures it has (Brave's image search has none).
nonisolated struct ImageFilters: Equatable, Hashable, Sendable {
    enum Size: String, CaseIterable, Identifiable, Sendable {
        case any, small, medium, large, wallpaper
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: String(localized: "Any size")
            case .small: String(localized: "Small")
            case .medium: String(localized: "Medium")
            case .large: String(localized: "Large")
            case .wallpaper: String(localized: "Wallpaper")
            }
        }
    }

    enum Layout: String, CaseIterable, Identifiable, Sendable {
        case any, square, tall, wide
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: String(localized: "Any layout")
            case .square: String(localized: "Square")
            case .tall: String(localized: "Tall")
            case .wide: String(localized: "Wide")
            }
        }
    }

    var size: Size = .any
    var layout: Layout = .any

    var isDefault: Bool { self == ImageFilters() }

    /// Whether a picture fits, by its size in pixels. One whose size isn't known fits only "any".
    func matches(_ item: ImageItem) -> Bool {
        guard !isDefault else { return true }
        let width = item.width, height = item.height
        guard width > 0, height > 0 else { return false }
        let longest = max(width, height)
        let sizeFits = switch size {
        case .any: true
        case .small: longest < 600
        case .medium: (600..<1600).contains(longest)
        case .large: longest >= 1600
        case .wallpaper: width >= 1920 && width > height
        }
        let aspect = Double(width) / Double(height)
        let layoutFits = switch layout {
        case .any: true
        case .square: abs(aspect - 1) <= 0.12
        case .tall: aspect < 0.88
        case .wide: aspect > 1.12
        }
        return sizeFits && layoutFits
    }
}

/// The video filters: how recent (Brave's), and how long (Max Q's, from each video's length).
nonisolated struct VideoFilters: Equatable, Hashable, Sendable {
    enum Length: String, CaseIterable, Identifiable, Sendable {
        case any, short, medium, long
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: String(localized: "Any length")
            case .short: String(localized: "Under 4 minutes")
            case .medium: String(localized: "4 to 20 minutes")
            case .long: String(localized: "Over 20 minutes")
            }
        }
    }

    var time: SearchTime = .any
    var length: Length = .any

    var isDefault: Bool { self == VideoFilters() }

    func matches(_ item: VideoItem) -> Bool {
        guard length != .any else { return true }
        guard let seconds = item.duration.flatMap(Self.seconds) else { return false }
        return switch length {
        case .any: true
        case .short: seconds < 240
        case .medium: (240...1200).contains(seconds)
        case .long: seconds > 1200
        }
    }

    /// "8:39" → 519, "1:02:05" → 3725.
    static func seconds(_ duration: String) -> Int? {
        let parts = duration.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0.map { $0 >= 0 } == true }) else { return nil }
        return parts.reduce(0) { $0 * 60 + ($1 ?? 0) }
    }
}

// MARK: - Client

/// Images, News and Videos for a search, from the search API the user has a key for.
nonisolated enum VerticalSearchClient {
    /// News for `query`; `offset` is the page (0, then what the last page said comes next).
    /// Without a search key, the outlets' own feeds that mention the search.
    static func news(_ query: String, time: SearchTime = .any, offset: Int = 0) async throws -> VerticalPage<NewsItem> {
        guard SearchAPIAccount.currentKey != nil else {
            guard offset == 0 else { return VerticalPage(items: [], next: nil) }
            return VerticalPage(items: Array(await NewsFeedClient.matching(query, within: time).prefix(60)), next: nil)
        }
        return try await BraveSearchClient.news(query, time: time, page: offset)
    }

    static func images(_ query: String, offset: Int = 0) async throws -> VerticalPage<ImageItem> {
        guard offset == 0 else { return VerticalPage(items: [], next: nil) }
        return try await BraveSearchClient.images(query)
    }

    static func videos(_ query: String, time: SearchTime = .any, offset: Int = 0) async throws -> VerticalPage<VideoItem> {
        try await BraveSearchClient.videos(query, time: time, page: offset)
    }

    /// Text without its tags and entities ("SpaceX&#x27;s <b>Starship</b>" → "SpaceX's Starship").
    static func clean(_ text: String) -> String {
        guard text.contains("<") || text.contains("&") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return WebSearchClient.plainText(text)
    }
}
