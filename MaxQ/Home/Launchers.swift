//
//  Launchers.swift
//  Max Q
//
//  SpaceXAI's and X's own products: Grok, Grokipedia, X and Grok Bot. The three sites are pinned
//  at the top of the sidebar, each with a tab of its own that stays put (see BrowserModel's
//  pinned tabs); Grok Bot opens its Mac app. Each site's own icon is loaded at runtime. No logos
//  are bundled with Max Q.
//

import AppKit
import SwiftUI

enum Launcher: String, CaseIterable, Identifiable {
    case grok, grokipedia, x, grokBot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grok: "Grok"
        case .grokBot: "Grok Bot"
        case .grokipedia: "Grokipedia"
        case .x: "X"
        }
    }

    var subtitle: String {
        switch self {
        case .grok: "grok.com"
        case .grokBot: GrokBot.isInstalled ? String(localized: "Open the app") : String(localized: "Get the app")
        case .grokipedia: "grokipedia.com"
        case .x: "x.com"
        }
    }

    /// The site whose own icon represents this launcher.
    var iconSite: URL {
        switch self {
        case .grok: URL(string: "https://grok.com")!
        case .grokBot: URL(string: "https://x.ai")!
        case .grokipedia: GrokipediaLinks.home
        case .x: XLinks.home
        }
    }

    var destination: URL? {
        switch self {
        case .grok: URL(string: "https://grok.com")!
        case .grokBot: nil
        case .grokipedia: GrokipediaLinks.home
        case .x: XLinks.home
        }
    }

    /// The launchers that keep a pinned tab (Grok Bot is an app, not a site).
    static var pinnable: [Launcher] { allCases.filter { $0.destination != nil } }

    /// The launcher's own sites.
    private var sites: [String] {
        switch self {
        case .grok: ["grok.com"]
        case .grokipedia: ["grokipedia.com"]
        case .x: ["x.com", "twitter.com"]
        case .grokBot: []
        }
    }

    /// Sign-in pages a pinned site sends people through (SpaceXAI's accounts, Google, Apple, X).
    nonisolated private static let signInHosts = [
        "accounts.x.ai", "accounts.google.com", "appleid.apple.com", "challenges.cloudflare.com",
        "api.x.com", "api.twitter.com",
    ]

    nonisolated private static func host(_ host: String, isIn sites: [String]) -> Bool {
        let host = host.lowercased()
        return sites.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// Whether a tab is on this launcher's site.
    func matches(_ tab: BrowserTab) -> Bool {
        guard destination != nil, let host = tab.host else { return false }
        return Self.host(host, isIn: sites)
    }

    /// Whether a link clicked in the pinned tab stays there (its own site, or a sign-in page)
    /// rather than opening as a tab of its own.
    func keepsInPinnedTab(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return url.scheme == "about" }
        if Self.host(host, isIn: sites) || Self.host(host, isIn: Self.signInHosts) { return true }
        // Signing in with X passes through x.com's own authorization pages.
        if Self.host(host, isIn: ["x.com", "twitter.com"]) {
            let path = url.path.lowercased()
            return path.hasPrefix("/i/oauth2") || path.hasPrefix("/oauth") || path.hasPrefix("/i/flow/login")
        }
        return false
    }

    /// Whether `url` is the site's front page (x.com's "/home" counts).
    func isFrontPage(_ url: URL) -> Bool {
        guard let host = url.host, Self.host(host, isIn: sites) else { return false }
        return ["", "/", "/home"].contains(url.path)
    }

    /// Switches to the launcher's pinned tab (opening it the first time), or opens Grok Bot.
    @MainActor
    func activate(in browser: BrowserModel) {
        browser.openPinned(self)
    }
}

struct LauncherIcon: View {
    let launcher: Launcher
    var size: CGFloat
    private var favicons: FaviconStore { FaviconStore.shared }

    var body: some View {
        Group {
            if launcher == .grokBot, let appIcon = GrokBot.appIcon {
                Image(nsImage: appIcon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size * 1.3, height: size * 1.3)
            } else if let icon = favicons.icon(for: launcher.iconSite.host) {
                SiteIcon(image: icon, tone: favicons.tone(for: launcher.iconSite.host), size: size)
            } else {
                Text(String(launcher.title.prefix(1)))
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: size, height: size)
            }
        }
        .onAppear { favicons.prefetchIcon(forSite: launcher.iconSite) }
    }
}

/// SpaceXAI's sites under the home composer, in Grokipedia's "Trending" chips: a quiet label,
/// then outlined capsules that brighten on hover.
struct LauncherChips: View {
    @Bindable var browser: BrowserModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Open")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .padding(.trailing, 4)
            ForEach(Launcher.allCases) { launcher in
                LauncherChip(launcher: launcher) { launcher.activate(in: browser) }
            }
        }
    }
}

private struct LauncherChip: View {
    let launcher: Launcher
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                LauncherIcon(launcher: launcher, size: 14)
                    .frame(width: 16, height: 16)
                Text(launcher.title)
                    .font(.system(size: 13.5))
            }
            .padding(.leading, 10)
            .padding(.trailing, 13)
            .frame(height: 32)
            .background(Capsule().fill(hovering ? Theme.hover : .clear))
            .overlay(Capsule().strokeBorder(hovering ? Theme.borderStrong : Theme.border, lineWidth: 1))
            .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .tip(verbatim: launcher == .grokBot && !GrokBot.isInstalled ? String(localized: "Grok Bot isn't installed: opens its download page") : launcher.subtitle)
        .accessibilityLabel("Open \(launcher.title)")
    }
}
