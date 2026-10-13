//
//  FaviconStore.swift
//  Max Q
//
//  Site icons for tabs and the home launcher. Icons are always the site's OWN icon, fetched at
//  runtime from the site itself (never bundled in the app), exactly like any browser shows them.
//  Fetches use an ephemeral session: no cookies, no credentials, nothing that identifies you.
//

import AppKit
import Observation

/// Whether an icon is a dark or light glyph on a transparent background, which would vanish on a
/// canvas of the same tone (Grokipedia's black "G" on Max Q's black dark mode, for example).
enum IconTone {
    case neutral
    case darkGlyph
    case lightGlyph

    nonisolated static func measure(_ image: NSImage) -> IconTone {
        let side = 24
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return .neutral }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var transparent = 0
        var luminance = 0.0
        var opaque = 0
        for i in 0..<(side * side) {
            let a = Double(pixels[i * 4 + 3]) / 255
            if a < 0.3 { transparent += 1; continue }
            // Un-premultiply before measuring.
            let r = Double(pixels[i * 4]) / 255 / a, g = Double(pixels[i * 4 + 1]) / 255 / a, b = Double(pixels[i * 4 + 2]) / 255 / a
            luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
            opaque += 1
        }
        guard opaque > 0, Double(transparent) / Double(side * side) > 0.2 else { return .neutral }
        let average = luminance / Double(opaque)
        if average < 0.22 { return .darkGlyph }
        if average > 0.85 { return .lightGlyph }
        return .neutral
    }
}

@MainActor
@Observable
final class FaviconStore {
    static let shared = FaviconStore()

    private(set) var icons: [String: NSImage] = [:]
    private(set) var tones: [String: IconTone] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var failedAt: [String: Date] = [:]

    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": WebViewFactory.safariUserAgent]
        return URLSession(configuration: config)
    }()

    private var diskDirectory: URL {
        let dir = Storage.cacheDirectory.appendingPathComponent("favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func key(for host: String) -> String {
        let h = host.lowercased()
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    func icon(for host: String?) -> NSImage? {
        guard let host, !host.isEmpty else { return nil }
        return icons[Self.key(for: host)]
    }

    func tone(for host: String?) -> IconTone {
        guard let host, !host.isEmpty else { return .neutral }
        return tones[Self.key(for: host)] ?? .neutral
    }

    private func store(_ image: NSImage, key: String) {
        icons[key] = image
        tones[key] = IconTone.measure(image)
    }

    /// Loads the icon for a page the user has open, using the icon links the page itself declares.
    /// `persist: false` (private windows) keeps the icon in memory only; `siteFallback: false`
    /// never asks the site itself for /favicon.ico.
    func loadIcon(host: String, candidates: [URL], persist: Bool = true, siteFallback: Bool = true) {
        let key = Self.key(for: host)
        guard icons[key] == nil else { return }
        if let cached = loadFromDisk(key) { store(cached, key: key); return }
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        var urls = candidates
        if siteFallback, let fallback = URL(string: "https://\(host)/favicon.ico") { urls.append(fallback) }
        Task {
            let image = await firstImage(from: urls)
            finish(key: key, image: image, persist: persist)
        }
    }

    /// Loads the icon for a site that is not open (home launcher): reads the site's home page
    /// for its declared icons, then falls back to /favicon.ico.
    func prefetchIcon(forSite url: URL) {
        guard let host = url.host else { return }
        let key = Self.key(for: host)
        guard icons[key] == nil else { return }
        if let cached = loadFromDisk(key) { store(cached, key: key); return }
        if let failed = failedAt[key], Date().timeIntervalSince(failed) < 600 { return }
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        Task {
            var candidates: [URL] = []
            if let (data, response) = try? await session.data(from: url),
               let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
               let html = String(data: data.prefix(400_000), encoding: .utf8) {
                candidates = Self.iconLinks(inHTML: html, baseURL: http.url ?? url)
            }
            if let fallback = URL(string: "https://\(host)/favicon.ico") { candidates.append(fallback) }
            let image = await firstImage(from: candidates)
            finish(key: key, image: image)
        }
    }

    func clearCache() {
        icons = [:]
        tones = [:]
        try? FileManager.default.removeItem(at: diskDirectory)
    }

    private func finish(key: String, image: NSImage?, persist: Bool = true) {
        inFlight.remove(key)
        if let image {
            store(image, key: key)
            if persist { saveToDisk(image, key: key) }
        } else {
            failedAt[key] = Date()
        }
    }

    private func firstImage(from urls: [URL]) async -> NSImage? {
        for url in urls.prefix(6) where url.scheme == "https" || url.scheme == "http" {
            guard let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count > 0, data.count < 1_500_000,
                  let image = NSImage(data: data), image.size.width >= 8 else { continue }
            return image
        }
        return nil
    }

    // MARK: - HTML parsing

    /// Extracts icon URLs from a page's `<link rel=...>` tags, best first: apple-touch-icon
    /// (large, square, opaque), then sized icons by size, then plain icons. SVG goes last.
    nonisolated static func iconLinks(inHTML html: String, baseURL: URL) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        var scored: [(URL, Int)] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: min(ns.length, 400_000))) {
            let tag = ns.substring(with: match.range)
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.contains("icon"),
                  let href = attribute("href", in: tag),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
            scored.append((url, score(rel: rel, sizes: attribute("sizes", in: tag) ?? "",
                                      type: attribute("type", in: tag) ?? "", url: url)))
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Same ranking for the icon links an open page reports through `PageScripts.iconLinks`.
    nonisolated static func iconLinks(declared links: [[String: Any]]) -> [URL] {
        links.compactMap { link -> (URL, Int)? in
            guard let href = link["href"] as? String, let url = URL(string: href),
                  url.scheme == "https" || url.scheme == "http" else { return nil }
            let rel = (link["rel"] as? String ?? "").lowercased()
            guard rel.contains("icon") else { return nil }
            return (url, score(rel: rel, sizes: link["sizes"] as? String ?? "", type: link["type"] as? String ?? "", url: url))
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    nonisolated private static func score(rel: String, sizes: String, type: String, url: URL) -> Int {
        var score = 0
        if rel.contains("apple-touch-icon") { score += 300 }
        if let first = sizes.lowercased().split(separator: "x").first, let px = Int(first) {
            score += min(px, 256)
        } else {
            score += 32
        }
        if url.pathExtension.lowercased() == "svg" || type.contains("svg") { score -= 400 }
        if rel.contains("mask-icon") { score -= 500 }
        return score
    }

    nonisolated private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) else { return nil }
        for group in [2, 3, 4] {
            let range = match.range(at: group)
            if range.location != NSNotFound {
                return (tag as NSString).substring(with: range)
                    .replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        return nil
    }

    // MARK: - Disk cache

    private func diskURL(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return diskDirectory.appendingPathComponent(safe + ".png")
    }

    private func loadFromDisk(_ key: String) -> NSImage? {
        let url = diskURL(key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 7 * 86_400 else { return nil }
        return NSImage(contentsOf: url)
    }

    private func saveToDisk(_ image: NSImage, key: String) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: diskURL(key), options: .atomic)
    }
}
