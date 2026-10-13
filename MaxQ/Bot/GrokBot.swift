//
//  GrokBot.swift
//  Max Q
//
//  Hand-offs to SpaceXAI's Grok Bot app. Grok Bot has no public API, so Max Q only does what any
//  app may do: open it if it's installed, link to its download page if not, and email its own
//  inbox (the documented way to give it work) through the user's mail app.
//

import AppKit

enum GrokBot {
    /// Bundle identifier of the Grok Bot desktop app (built by Cursor, hence the Anysphere id).
    nonisolated static let bundleIdentifier = "com.anysphere.sand"
    nonisolated static let urlScheme = "grokbot"
    nonisolated static let downloadPage = URL(string: "https://x.ai/bot")!

    static var appURL: URL? {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) { return url }
        if let scheme = URL(string: "\(urlScheme)://") { return workspace.urlForApplication(toOpen: scheme) }
        return nil
    }

    static var isInstalled: Bool { appURL != nil }

    static var appIcon: NSImage? {
        guard let url = appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Opens the app. Returns false when it isn't installed.
    @discardableResult
    static func open() -> Bool {
        guard let url = appURL else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    /// A mailto: link that hands a page to the Bot's inbox, with the user's instruction.
    nonisolated static func mailto(address: String, pageTitle: String, pageURL: URL, instruction: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address.trimmingCharacters(in: .whitespaces)
        let subject = pageTitle.isEmpty ? String(localized: "Page from Max Q") : String(pageTitle.prefix(120))
        var body = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        body += body.isEmpty ? pageURL.absoluteString : "\n\n\(pageURL.absoluteString)"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
