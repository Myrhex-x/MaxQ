//
//  RemoteImage.swift
//  Max Q
//
//  Loads an image from a list of candidates (first that works wins), with an optional Referer
//  (Grokipedia's image server serves article images to grokipedia.com pages). Ephemeral session,
//  no cookies; decoded images are kept in memory only.
//

import AppKit
import SwiftUI

@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpCookieStorage = nil
        config.urlCache = URLCache(memoryCapacity: 48 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: config)
    }()

    /// Results pages show many pictures (avatars, posts' photos, an article's figures): enough are
    /// kept that scrolling back doesn't load them again. Memory only.
    init() { cache.countLimit = 220 }

    func image(from candidates: [URL], referer: String?) async -> NSImage? {
        for url in candidates.prefix(5) {
            if let cached = cache.object(forKey: url as NSURL) { return cached }
            if url.isFileURL {
                // Pictures made on this Mac (Imagine).
                guard let image = NSImage(contentsOf: url) else { continue }
                cache.setObject(image, forKey: url as NSURL)
                return image
            }
            var request = URLRequest(url: url)
            // Grokipedia's pictures with the same honest agent as its pages; anything else (X's
            // pictures, site icons) as the browser Max Q is.
            let grokipedia = url.host?.hasSuffix("grokipedia.com") == true
            request.setValue(grokipedia ? GrokipediaArticleClient.userAgent : WebViewFactory.safariUserAgent,
                             forHTTPHeaderField: "User-Agent")
            if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count < 8_000_000, let image = NSImage(data: data), image.size.width >= 32 else { continue }
            cache.setObject(image, forKey: url as NSURL)
            return image
        }
        return nil
    }
}

struct RemoteImage: View {
    let candidates: [URL]
    var referer: String? = nil
    var contentMode: ContentMode = .fill
    /// Draw a quiet fill while loading.
    var showsPlaceholder = true
    /// Called when none of the candidates loaded, so the caller can hide the space.
    var onFailure: () -> Void = {}
    /// Called with the picture's size once it's loaded.
    var onLoad: (CGSize) -> Void = { _ in }

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if !failed, showsPlaceholder {
                Rectangle().fill(Theme.hover)
            }
        }
        .animation(Motion.standard(0.36), value: image != nil)
        .task(id: candidates.first) {
            image = nil
            failed = false
            let loaded = await RemoteImageCache.shared.image(from: candidates, referer: referer)
            image = loaded
            failed = loaded == nil
            if loaded == nil, !Task.isCancelled { onFailure() }
            if let loaded { onLoad(loaded.size) }
        }
    }
}

/// A picture that fills whatever frame it's given, cropped to it, without ever asking for more
/// room than that frame: the layout comes from the frame, not from the picture.
struct FillImage: View {
    let candidates: [URL]
    var referer: String? = nil
    var showsPlaceholder = true
    var onFailure: () -> Void = {}
    var onLoad: (CGSize) -> Void = { _ in }

    var body: some View {
        Color.clear
            .overlay {
                RemoteImage(candidates: candidates, referer: referer, contentMode: .fill,
                            showsPlaceholder: showsPlaceholder, onFailure: onFailure, onLoad: onLoad)
            }
            .clipped()
    }
}
