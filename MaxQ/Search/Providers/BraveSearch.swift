//
//  BraveSearch.swift
//  Max Q
//
//  Web, image, news and video results for Max Q's results page, from the Brave Search API with
//  the user's own key. A Brave account comes with $5 of searches a month (about a thousand);
//  Max Q has no key of its own and no server. The key stays in the Keychain, requests go straight
//  from this Mac to Brave, and results are kept only while they're on screen, as Brave's terms
//  ask. Without a key the results page says so, and the same search opens on DuckDuckGo's own
//  page.
//

import Foundation
import Observation
import Security

// MARK: - The key

/// The Brave Search API key, in the Keychain.
nonisolated enum BraveKeyStore {
    nonisolated(unsafe) static var service: String = {
        #if DEBUG
        if let id = Bundle.main.bundleIdentifier, id != "com.myrhex.MaxQ" { return id + ".brave-search-key" }
        #endif
        return "com.myrhex.MaxQ.brave-search-key"
    }()

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "default"]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8), !key.isEmpty else { return false }
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Max Q: Brave Search API key"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Whether there's a key for web results, for the screens; the key itself for the requests.
@MainActor
@Observable
final class SearchAPIAccount {
    static let shared = SearchAPIAccount()

    private(set) var hasKey = false
    private(set) var keyHint = ""
    /// A key is being tried before it's saved.
    private(set) var checking = false

    /// The key, readable off the main actor by the requests (read from the Keychain the first time).
    nonisolated static var currentKey: String? {
        lock.lock(); defer { lock.unlock() }
        if !loaded {
            loaded = true
            stored = initialKey()
        }
        return stored
    }
    nonisolated(unsafe) private static var stored: String?
    nonisolated(unsafe) private static var loaded = false
    nonisolated private static let lock = NSLock()

    nonisolated private static func initialKey() -> String? {
        #if DEBUG
        // Pretend results for checking the screens (see BraveSearchClient.simulated): nothing is sent.
        if UserDefaults.standard.bool(forKey: "MaxQSimulatedSearch") { return BraveSearchClient.simulatedKey }
        #endif
        return BraveKeyStore.read()
    }

    private init() {
        if let key = Self.currentKey { show(key) }
    }

    /// Tries a key with one small search, then saves it. Returns why it wasn't saved, or nil. A key
    /// Brave knows is saved even when it's out of credit or busy; one that can't be tried (offline)
    /// is saved as it is, and the first search says if it's wrong.
    func setKey(_ raw: String) async -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return String(localized: "Paste your Brave Search API key first.") }
        checking = true
        let problem = await BraveSearchClient.check(key)
        checking = false
        if problem == .invalidKey { return String(localized: "Brave didn't accept this key. Check that it's copied whole.") }
        guard BraveKeyStore.save(key) else { return String(localized: "Couldn't save the key to your Keychain.") }
        use(key)
        return nil
    }

    func removeKey() {
        BraveKeyStore.delete()
        Self.lock.lock()
        Self.stored = nil
        Self.loaded = true
        Self.lock.unlock()
        hasKey = false
        keyHint = ""
    }

    private func use(_ key: String) {
        Self.lock.lock()
        Self.stored = key
        Self.loaded = true
        Self.lock.unlock()
        show(key)
    }

    private func show(_ key: String) {
        hasKey = true
        keyHint = key == BraveSearchClient.simulatedKey ? "Simulated"
            : key.count > 8 ? "\(key.prefix(4))…\(key.suffix(4))" : String(localized: "Saved")
    }
}

// MARK: - Errors

nonisolated enum SearchProviderError: LocalizedError, Equatable {
    case needsKey
    case invalidKey
    case outOfCredit
    case rateLimited
    case offline
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .needsKey: String(localized: "Web results need a Brave Search API key.")
        case .invalidKey: String(localized: "Brave didn't accept the search key. Check it in Settings.")
        case .outOfCredit: String(localized: "This month's searches on your Brave key are used up.")
        case .rateLimited: String(localized: "Brave asked Max Q to slow down. Try again in a moment.")
        case .offline: String(localized: "Your Mac isn't connected to the internet.")
        case .failed(let detail): String(localized: "Results didn't load (\(detail)).")
        }
    }
}

// MARK: - Requests

/// A page of web results.
nonisolated struct BraveWebPage: Sendable {
    let results: [WebResult]
    let related: [String]
    let moreAvailable: Bool
}

nonisolated enum BraveSearchClient {
    static let simulatedKey = "simulated"
    /// Brave pages its results ten deep at most.
    static let lastPage = 9

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Web results, page `page` (0 to 9) of 20.
    static func web(_ query: String, time: SearchTime = .any, page: Int = 0) async throws -> BraveWebPage {
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "count", value: "20"),
                     URLQueryItem(name: "offset", value: String(min(max(page, 0), lastPage)))]
        if let freshness = time.freshness { items.append(URLQueryItem(name: "freshness", value: freshness)) }
        let json = try await get("web/search", items + localeItems(countries: webCountries), query: query, kind: "web")
        return parseWeb(json)
    }

    static func news(_ query: String, time: SearchTime = .any, page: Int = 0) async throws -> VerticalPage<NewsItem> {
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "count", value: "20"),
                     URLQueryItem(name: "offset", value: String(min(max(page, 0), lastPage)))]
        if let freshness = time.freshness { items.append(URLQueryItem(name: "freshness", value: freshness)) }
        let json = try await get("news/search", items + localeItems(countries: webCountries), query: query, kind: "news")
        let found = parseNews(json)
        return VerticalPage(items: found, next: found.count >= 20 && page < lastPage ? page + 1 : nil)
    }

    /// Up to a hundred pictures (Brave doesn't page its image results).
    static func images(_ query: String) async throws -> VerticalPage<ImageItem> {
        let items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "count", value: "100")]
        let json = try await get("images/search", items + localeItems(countries: webCountries), query: query, kind: "images")
        return VerticalPage(items: parseImages(json), next: nil)
    }

    static func videos(_ query: String, time: SearchTime = .any, page: Int = 0) async throws -> VerticalPage<VideoItem> {
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "count", value: "20"),
                     URLQueryItem(name: "offset", value: String(min(max(page, 0), lastPage)))]
        if let freshness = time.freshness { items.append(URLQueryItem(name: "freshness", value: freshness)) }
        let json = try await get("videos/search", items + localeItems(countries: webCountries), query: query, kind: "videos")
        let found = parseVideos(json)
        return VerticalPage(items: found, next: found.count >= 20 && page < lastPage ? page + 1 : nil)
    }

    /// Whether Brave takes `key`: one search for a single result, about half a cent of Brave's
    /// monthly credit. Nil when it does.
    static func check(_ key: String) async -> SearchProviderError? {
        #if DEBUG
        if key == simulatedKey { return nil }
        #endif
        do {
            _ = try await get("web/search", [URLQueryItem(name: "q", value: "brave"), URLQueryItem(name: "count", value: "1")],
                              query: "brave", kind: "web", key: key)
            return nil
        } catch let error as SearchProviderError {
            return error
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func get(_ path: String, _ items: [URLQueryItem], query: String, kind: String,
                            key candidate: String? = nil) async throws -> [String: Any] {
        guard let key = candidate ?? SearchAPIAccount.currentKey else { throw SearchProviderError.needsKey }
        #if DEBUG
        if key == simulatedKey { return try await simulated(kind, query: query) }
        #endif
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/" + path)!
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw SearchProviderError.offline
        } catch {
            throw SearchProviderError.failed(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let error = error(status: status, json: json) { throw error }
        return json
    }

    /// What an answer's status and error body mean. Brave answers a wrong key with 422
    /// SUBSCRIPTION_TOKEN_INVALID, a spent month with 402 or 429 QUOTA_LIMITED.
    static func error(status: Int, json: [String: Any]) -> SearchProviderError? {
        let body = json["error"] as? [String: Any]
        let code = body?["code"] as? String
        let component = (body?["meta"] as? [String: Any])?["component"] as? String
        switch status {
        case 200..<300: return nil
        case 401, 403: return .invalidKey
        case 422 where code == "SUBSCRIPTION_TOKEN_INVALID" || component == "authentication": return .invalidKey
        case 402: return .outOfCredit
        case 429: return code == "QUOTA_LIMITED" ? .outOfCredit : .rateLimited
        default: return .failed("HTTP \(status)")
        }
    }

    /// Countries Brave serves results for, by their two-letter codes.
    private static let webCountries: Set<String> = [
        "AR", "AU", "AT", "BE", "BR", "CA", "CL", "DK", "FI", "FR", "DE", "HK", "IN", "ID", "IT", "JP", "KR", "MY",
        "MX", "NL", "NZ", "NO", "CN", "PL", "PT", "PH", "RU", "SA", "ZA", "ES", "SE", "CH", "TW", "TR", "GB", "US",
    ]

    /// The Mac's language and country, so a French Mac gets French results.
    private static func localeItems(countries: Set<String>) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        items.append(URLQueryItem(name: "search_lang", value: language))
        if let region = Locale.current.region?.identifier.uppercased(), countries.contains(region) {
            items.append(URLQueryItem(name: "country", value: region))
        }
        return items
    }

    // MARK: Parsing

    static func parseWeb(_ json: [String: Any]) -> BraveWebPage {
        let query = json["query"] as? [String: Any]
        var seen = Set<String>()
        let results = ((json["web"] as? [String: Any])?["results"] as? [[String: Any]] ?? []).compactMap { entry -> WebResult? in
            guard let url = (entry["url"] as? String).flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true,
                  let title = (entry["title"] as? String).map(WebSearchClient.plainText), !title.isEmpty,
                  seen.insert(url.absoluteString).inserted else { return nil }
            var result = WebResult(title: title, url: url, snippet: WebSearchClient.snippetRuns(entry["description"] as? String ?? ""))
            result.date = date(entry["page_age"] as? String)
            result.dateIsDay = isDay(entry["page_age"] as? String)
            result.favicon = favicon(entry)
            result.still = ((entry["thumbnail"] as? [String: Any])?["src"] as? String).flatMap(URL.init(string:))
            return result
        }
        let related = (query?["related_queries"] as? [String] ?? []).map(WebSearchClient.plainText).filter { !$0.isEmpty }
        let more = query?["more_results_available"] as? Bool ?? (results.count >= 20)
        return BraveWebPage(results: results, related: related, moreAvailable: more)
    }

    static func parseNews(_ json: [String: Any]) -> [NewsItem] {
        var seen = Set<String>()
        return (json["results"] as? [[String: Any]] ?? []).compactMap { entry -> NewsItem? in
            guard let url = (entry["url"] as? String).flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true,
                  let title = (entry["title"] as? String).map(WebSearchClient.plainText), !title.isEmpty,
                  seen.insert(url.absoluteString).inserted else { return nil }
            let meta = entry["meta_url"] as? [String: Any]
            let source = ((entry["profile"] as? [String: Any])?["name"] as? String).map(WebSearchClient.plainText)
                ?? (meta?["hostname"] as? String).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
            let image = ((entry["thumbnail"] as? [String: Any])?["src"] as? String).flatMap(URL.init(string:))
            return NewsItem(title: title, url: url, excerpt: WebSearchClient.plainText(entry["description"] as? String ?? ""),
                            source: source, date: date(entry["page_age"] as? String), image: image, viaSearchAPI: true)
        }
    }

    static func parseImages(_ json: [String: Any]) -> [ImageItem] {
        var seen = Set<String>()
        return (json["results"] as? [[String: Any]] ?? []).compactMap { entry -> ImageItem? in
            let properties = entry["properties"] as? [String: Any]
            let thumbnail = entry["thumbnail"] as? [String: Any]
            guard let image = (properties?["url"] as? String).flatMap(URL.init(string:)), image.scheme?.hasPrefix("http") == true,
                  let still = (thumbnail?["src"] as? String).flatMap(URL.init(string:)),
                  let page = (entry["url"] as? String).flatMap(URL.init(string:)), page.scheme?.hasPrefix("http") == true,
                  seen.insert(image.absoluteString).inserted else { return nil }
            let width = (properties?["width"] as? Int) ?? (thumbnail?["width"] as? Int) ?? 0
            let height = (properties?["height"] as? Int) ?? (thumbnail?["height"] as? Int) ?? 0
            return ImageItem(title: WebSearchClient.plainText(entry["title"] as? String ?? ""), image: image, thumbnail: still,
                             page: page, width: width, height: height)
        }
    }

    static func parseVideos(_ json: [String: Any]) -> [VideoItem] {
        var seen = Set<String>()
        return (json["results"] as? [[String: Any]] ?? []).compactMap { entry -> VideoItem? in
            guard let url = (entry["url"] as? String).flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true,
                  let title = (entry["title"] as? String).map(WebSearchClient.plainText), !title.isEmpty,
                  seen.insert(url.absoluteString).inserted else { return nil }
            let video = entry["video"] as? [String: Any]
            let still = ((entry["thumbnail"] as? [String: Any])?["src"] as? String).flatMap(URL.init(string:))
            let views = (video?["views"] as? Int) ?? (video?["views"] as? String).flatMap { Int($0) }
            let uploader = (video?["creator"] as? String) ?? ((video?["author"] as? [String: Any])?["name"] as? String)
            return VideoItem(title: title, url: url, summary: WebSearchClient.plainText(entry["description"] as? String ?? ""),
                             still: still, duration: (video?["duration"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             publisher: (video?["publisher"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             uploader: uploader.flatMap { $0.isEmpty ? nil : WebSearchClient.plainText($0) },
                             published: date(entry["page_age"] as? String), views: views)
        }
    }

    /// The site's icon, as Brave serves it.
    private static func favicon(_ entry: [String: Any]) -> URL? {
        ((entry["meta_url"] as? [String: Any])?["favicon"] as? String).flatMap(URL.init(string:))
    }

    /// "2026-10-06T18:16:41" (UTC unless it says otherwise).
    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        let digits = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard digits.count >= 3, (1990...2100).contains(digits[0]) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        (components.year, components.month, components.day) = (digits[0], digits[1], digits[2])
        if digits.count >= 6 { (components.hour, components.minute, components.second) = (digits[3], digits[4], digits[5]) }
        guard let date = components.date, date.timeIntervalSinceNow < 86_400 else { return nil }
        return date
    }

    /// Whether a date Brave gives is a day rather than a moment: no time, or midnight on the dot,
    /// which is how it gives pages that only say their day.
    static func isDay(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        guard let time = text.firstIndex(of: "T") else { return true }
        return String(text[time...]).range(of: #"^T00:00:00(\.0+)?(Z|[+-]00:?00)?$"#, options: .regularExpression) != nil
    }

    #if DEBUG
    /// Pretend results with Brave's shapes, for test copies (`-MaxQSimulatedSearch YES`).
    private static func simulated(_ kind: String, query: String) async throws -> [String: Any] {
        try await Task.sleep(for: .milliseconds(350))
        // Made-up sites (".example" never resolves): nothing here looks like a real outlet's page.
        let hosts = ["reference.example", "gazette.example", "journal.example", "almanac.example", "review.example",
                     "bulletin.example", "digest.example", "chronicle.example"]
        let age = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7_200)).replacingOccurrences(of: "Z", with: "")
        func entry(_ index: Int) -> [String: Any] {
            let host = hosts[index % hosts.count]
            let path = host.contains("youtube") ? "/watch?v=simulated\(index)" : "/simulated/\(index)"
            return ["title": "Simulated result \(index + 1) about \(query)", "url": "https://\(host)\(path)",
                    "description": "A simulated <strong>\(query)</strong> result: test copies show this instead of asking Brave.",
                    "page_age": age, "meta_url": ["hostname": host], "profile": ["name": host]]
        }
        switch kind {
        case "images":
            return ["results": (0..<24).map { index -> [String: Any] in
                let width = [1600, 900, 1200, 1920][index % 4], height = [900, 1200, 1200, 1080][index % 4]
                return ["title": "Simulated picture \(index + 1)", "url": "https://example.com/picture/\(index)",
                        "thumbnail": ["src": "https://picsum.photos/seed/maxq\(index)/\(width / 4)/\(height / 4)"],
                        "properties": ["url": "https://picsum.photos/seed/maxq\(index)/\(width)/\(height)", "width": width, "height": height]]
            }]
        case "videos":
            return ["results": (0..<8).map { index -> [String: Any] in
                var item = entry(index)
                item["url"] = "https://www.youtube.com/watch?v=simulated\(index)"
                item["video"] = ["duration": ["3:12", "12:40", "1:02:05"][index % 3], "views": 12_000 * (index + 1), "creator": "Simulated channel"]
                return item
            }]
        case "news":
            return ["results": (0..<12).map(entry)]
        default:
            return ["query": ["original": query, "more_results_available": false,
                              "related_queries": ["\(query) news", "\(query) history", "what is \(query)"]],
                    "web": ["results": (0..<10).map(entry)]]
        }
    }
    #endif
}

extension SearchTime {
    /// Brave's `freshness`: the past day, week, month or year.
    nonisolated var freshness: String? {
        switch self {
        case .any: nil
        case .day: "pd"
        case .week: "pw"
        case .month: "pm"
        case .year: "py"
        }
    }
}
