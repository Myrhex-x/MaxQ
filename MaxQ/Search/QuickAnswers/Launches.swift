//
//  Launches.swift
//  Max Q
//
//  Rocket launches, for searches about one ("next starship launch", "falcon heavy", "ariane 6
//  lancement"): the next launch with a live countdown when its time is firm, where and what it
//  carries, and the ones after it. The data is The Space Devs' Launch Library, a free public
//  database, asked only for searches like these and kept a quarter of an hour (it allows a few
//  requests an hour). A rough date stays a rough date: "Q4 2026", never a countdown to a guess.
//

import Foundation

nonisolated struct Launch: Identifiable, Equatable, Sendable {
    let id: String
    /// "Starship | Flight 15".
    let name: String
    let net: Date
    /// How firm `net` is: "SEC", "MIN", "HR" are firm; "D", "M", "Q4", "Y" are rough.
    let precision: String
    let precisionName: String
    /// "Go", "TBD", "TBC", "Hold", "Success", "Failure", "In Flight".
    let status: String
    let statusName: String
    let provider: String
    let rocket: String
    let mission: String?
    let missionDescription: String?
    let orbit: String?
    let pad: String
    let location: String
    let image: URL?
    let webcastLive: Bool
    let webcast: URL?

    /// The time is firm enough to count down to.
    var hasFirmTime: Bool { ["SEC", "MIN", "HR", "H"].contains(precision.uppercased()) }

    /// "Q4 2026", "October 2026", "Oct 14": the date as precisely as it's known.
    var roughDate: String {
        switch precision.uppercased() {
        case "Y": return net.formatted(.dateTime.year())
        case "M": return net.formatted(.dateTime.month(.wide).year())
        case "Q1", "Q2", "Q3", "Q4": return "\(precision.uppercased()) \(net.formatted(.dateTime.year()))"
        case "H1", "H2": return "\(precision.uppercased()) \(net.formatted(.dateTime.year()))"
        case "D", "W": return net.formatted(.dateTime.month(.abbreviated).day().year())
        default: return net.formatted(date: .abbreviated, time: .shortened)
        }
    }
}

nonisolated enum LaunchQuery {
    /// Rockets, spacecraft and the companies and agencies that fly them, as searched for.
    static let vehicles: [String: String] = [
        "starship": "starship", "super heavy": "starship", "falcon heavy": "falcon heavy", "falcon 9": "falcon 9",
        "falcon": "falcon", "new glenn": "new glenn", "new shepard": "new shepard", "vulcan": "vulcan",
        "ariane 6": "ariane 6", "ariane": "ariane", "vega": "vega", "electron": "electron", "neutron": "neutron",
        "soyuz": "soyuz", "long march": "long march", "h3": "h3", "sls": "sls", "artemis": "artemis",
        "crew dragon": "dragon", "dragon": "dragon", "starliner": "starliner", "pslv": "pslv", "gslv": "gslv",
        "starlink": "starlink", "kuiper": "kuiper", "spacex": "spacex", "blue origin": "blue origin",
        "rocket lab": "rocket lab", "ula": "ula", "arianespace": "arianespace", "isro": "isro", "jaxa": "jaxa",
        "gaganyaan": "gaganyaan", "crew-": "crew", "axiom": "axiom", "polaris": "polaris", "tianzhou": "tianzhou",
        "shenzhou": "shenzhou",
    ]

    static let launchWords = ["launch", "liftoff", "lift off", "lift-off", "next flight", "flight test", "countdown",
                              "lancement", "décollage", "decollage", "lanzamiento", "launches"]

    /// What to look launches up by, when the search is about one: a vehicle's name, or "" for any.
    static func detect(_ query: String) -> String? {
        let text = " " + query.lowercased().folding(options: .diacriticInsensitive, locale: nil) + " "
        let mentionsLaunch = launchWords.contains { text.contains($0.folding(options: .diacriticInsensitive, locale: nil)) }
        let vehicle = vehicles.keys.sorted { $0.count > $1.count }.first { key in
            text.contains(" \(key) ") || text.contains(" \(key)") && key.hasSuffix("-")
        }.map { vehicles[$0]! }
        if let vehicle, mentionsLaunch || text.contains(" next ") || text.contains(" when ") || text.contains(" prochain") {
            return vehicle
        }
        if text.contains("rocket launch") || text.contains("next launch") || text.contains("upcoming launches")
            || text.contains("launch schedule") || text.contains("prochain lancement") || text.contains("lancement de fusee") {
            return ""
        }
        return nil
    }
}

nonisolated enum LaunchClient {
    private actor Cache {
        var entries: [String: (launches: [Launch], date: Date)] = [:]
        func get(_ key: String) -> [Launch]? {
            guard let entry = entries[key], Date().timeIntervalSince(entry.date) < 15 * 60 else { return nil }
            return entry.launches
        }
        func set(_ key: String, _ launches: [Launch]) { entries[key] = (launches, Date()) }
    }

    private static let cache = Cache()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// The next launches for `search` ("" for any), soonest first.
    static func upcoming(_ search: String) async throws -> [Launch] {
        if let cached = await cache.get(search) { return cached }
        var components = URLComponents(string: "https://ll.thespacedevs.com/2.3.0/launches/upcoming/")!
        var items = [URLQueryItem(name: "limit", value: "5"), URLQueryItem(name: "mode", value: "normal"),
                     URLQueryItem(name: "hide_recent_previous", value: "true")]
        if !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MaxQ/1.0 (macOS browser)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 429 { throw WebSearchError.blocked }
        guard (200..<300).contains(status), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebSearchError.failed("HTTP \(status)")
        }
        let launches = parse(json)
        await cache.set(search, launches)
        return launches
    }

    static func parse(_ json: [String: Any]) -> [Launch] {
        (json["results"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String,
                  let netText = item["net"] as? String, let net = ISO8601DateFormatter().date(from: netText) else { return nil }
            let precision = item["net_precision"] as? [String: Any]
            let status = item["status"] as? [String: Any]
            let provider = (item["launch_service_provider"] as? [String: Any])?["name"] as? String ?? ""
            let configuration = (item["rocket"] as? [String: Any])?["configuration"] as? [String: Any]
            let mission = item["mission"] as? [String: Any]
            let pad = item["pad"] as? [String: Any]
            let location = (pad?["location"] as? [String: Any])?["name"] as? String ?? ""
            let image: URL? = {
                if let object = item["image"] as? [String: Any] {
                    return ((object["thumbnail_url"] as? String) ?? (object["image_url"] as? String)).flatMap(URL.init(string:))
                }
                return (item["image"] as? String).flatMap(URL.init(string:))
            }()
            let videos = (item["vid_urls"] as? [[String: Any]] ?? []) + (mission?["vid_urls"] as? [[String: Any]] ?? [])
            let webcast = videos.sorted { ($0["priority"] as? Int ?? 99) < ($1["priority"] as? Int ?? 99) }
                .compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.first
            return Launch(id: id, name: name, net: net,
                          precision: precision?["abbrev"] as? String ?? "SEC", precisionName: precision?["name"] as? String ?? "",
                          status: status?["abbrev"] as? String ?? "", statusName: status?["name"] as? String ?? "",
                          provider: provider,
                          rocket: (configuration?["full_name"] as? String) ?? (configuration?["name"] as? String) ?? "",
                          mission: mission?["name"] as? String, missionDescription: mission?["description"] as? String,
                          orbit: (mission?["orbit"] as? [String: Any])?["name"] as? String,
                          pad: pad?["name"] as? String ?? "", location: location, image: image,
                          webcastLive: item["webcast_live"] as? Bool ?? false, webcast: webcast)
        }
        .sorted { $0.net < $1.net }
    }
}
