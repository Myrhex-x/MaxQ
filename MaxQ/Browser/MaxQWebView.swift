//
//  MaxQWebView.swift
//  Max Q
//
//  WKWebView subclass that adds Max Q's items to the page context menu: ask Grok about a
//  selection, rewrite a selection in a text field, look things up on X and Grokipedia, and fill
//  in the Grok Bot's email address. Nothing runs until the user picks an item.
//

import AppKit
import WebKit

enum RewriteStyle: String, CaseIterable, Identifiable {
    case improve, grammar, shorter, formal, casual
    var id: String { rawValue }

    var title: String {
        switch self {
        case .improve: String(localized: "Improve Writing")
        case .grammar: String(localized: "Fix Spelling and Grammar")
        case .shorter: String(localized: "Make Shorter")
        case .formal: String(localized: "Make More Formal")
        case .casual: String(localized: "Make More Casual")
        }
    }

    var instruction: String {
        switch self {
        case .improve: "Improve the clarity and flow of this text while keeping its meaning, voice and language."
        case .grammar: "Fix spelling, grammar and punctuation only. Change nothing else."
        case .shorter: "Make this text noticeably shorter while keeping every important point."
        case .formal: "Rewrite this text in a more formal, professional tone."
        case .casual: "Rewrite this text in a more relaxed, casual tone."
        }
    }
}

enum PageMenuAction {
    case askGrok
    case check
    case explain
    case translate
    case rewrite(RewriteStyle)
    case searchX
    case grokipedia
    case searchWeb
    case fillBotEmail
    /// The selection (or the page) into a collection, or a new one (nil).
    case addToCollection(UUID?)
}

@MainActor
protocol PageMenuHandler: AnyObject {
    func webView(_ webView: MaxQWebView, perform action: PageMenuAction)
    var searchEngineName: String { get }
    var botEmailAvailable: Bool { get }
    /// The collections a selection or page can go into, most recent first.
    var collections: [(id: UUID, name: String)] { get }
}

final class MaxQWebView: WKWebView {
    weak var menuHandler: PageMenuHandler?
    /// The tab this web view shows, for messages from its page.
    weak var tab: BrowserTab?

    /// A click in a split pane gives that pane the keyboard (and makes it the selected tab).
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, let tab { tab.browser?.focusPane(tab) }
        return became
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        func item(_ id: String) -> NSMenuItem? {
            menu.items.first { $0.identifier?.rawValue == id }
        }

        // New windows open as tabs in Max Q, so say so.
        item("WKMenuItemIdentifierOpenLinkInNewWindow")?.title = String(localized: "Open Link in New Tab")
        item("WKMenuItemIdentifierOpenImageInNewWindow")?.title = String(localized: "Open Image in New Tab")
        item("WKMenuItemIdentifierOpenMediaInNewWindow")?.title = String(localized: "Open Video in New Tab")
        item("WKMenuItemIdentifierOpenFrameInNewWindow")?.title = String(localized: "Open Frame in New Tab")

        guard let handler = menuHandler else { return }

        // In a text field WebKit shows Copy even with nothing selected, just disabled.
        let hasSelection = item("WKMenuItemIdentifierCopy")?.isEnabled ?? false
        let isEditable = item("WKMenuItemIdentifierPaste") != nil

        // "Search with Google" would hand off to Safari; route it to the user's engine instead.
        if let search = item("WKMenuItemIdentifierSearchWeb") {
            search.title = String(localized: "Search with \(handler.searchEngineName)")
            search.target = self
            search.action = #selector(menuSearchWeb)
        }

        var additions: [NSMenuItem] = []

        if hasSelection {
            additions.append(makeItem(String(localized: "Ask Grok About Selection"), #selector(menuAskGrok), symbol: "text.bubble"))
            additions.append(makeItem(String(localized: "Check with Grok"), #selector(menuCheck), symbol: "checkmark.seal"))
            additions.append(makeItem(String(localized: "Explain with Grok"), #selector(menuExplain), symbol: "text.magnifyingglass"))
            additions.append(makeItem(String(localized: "Translate with Grok"), #selector(menuTranslate), symbol: "character.bubble"))
            if isEditable {
                let rewrite = NSMenuItem(title: String(localized: "Rewrite with Grok"), action: nil, keyEquivalent: "")
                rewrite.image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: nil)
                let sub = NSMenu(title: String(localized: "Rewrite with Grok"))
                for (index, style) in RewriteStyle.allCases.enumerated() {
                    let entry = NSMenuItem(title: style.title, action: #selector(menuRewrite(_:)), keyEquivalent: "")
                    entry.target = self
                    entry.tag = index
                    sub.addItem(entry)
                }
                rewrite.submenu = sub
                additions.append(rewrite)
            }
            additions.append(.separator())
            additions.append(makeItem(String(localized: "Search X for Selection"), #selector(menuSearchX), symbol: "magnifyingglass"))
            additions.append(makeItem(String(localized: "Look Up on Grokipedia"), #selector(menuGrokipedia), symbol: "book"))
        }

        // Into a collection: the selection as a quote, or the page itself.
        if !isEditable {
            if !additions.isEmpty { additions.append(.separator()) }
            let add = NSMenuItem(title: hasSelection ? String(localized: "Add Selection to Collection") : String(localized: "Add Page to Collection"),
                                 action: nil, keyEquivalent: "")
            add.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)
            let sub = NSMenu(title: add.title)
            for (index, collection) in handler.collections.prefix(12).enumerated() {
                let entry = NSMenuItem(title: collection.name, action: #selector(menuAddToCollection(_:)), keyEquivalent: "")
                entry.target = self
                entry.tag = index
                sub.addItem(entry)
            }
            if !handler.collections.isEmpty { sub.addItem(.separator()) }
            let new = NSMenuItem(title: String(localized: "New Collection"), action: #selector(menuAddToNewCollection), keyEquivalent: "")
            new.target = self
            sub.addItem(new)
            add.submenu = sub
            additions.append(add)
        }

        if isEditable && handler.botEmailAvailable {
            if !additions.isEmpty { additions.append(.separator()) }
            additions.append(makeItem(String(localized: "Use Grok Bot Email"), #selector(menuFillBotEmail), symbol: "envelope"))
        }

        guard !additions.isEmpty else { return }
        menu.insertItem(.separator(), at: 0)
        for (offset, entry) in additions.enumerated() {
            menu.insertItem(entry, at: offset)
        }
    }

    private func makeItem(_ title: String, _ action: Selector, symbol: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return entry
    }

    @objc private func menuAskGrok() { menuHandler?.webView(self, perform: .askGrok) }
    @objc private func menuCheck() { menuHandler?.webView(self, perform: .check) }
    @objc private func menuExplain() { menuHandler?.webView(self, perform: .explain) }
    @objc private func menuTranslate() { menuHandler?.webView(self, perform: .translate) }
    @objc private func menuSearchX() { menuHandler?.webView(self, perform: .searchX) }
    @objc private func menuGrokipedia() { menuHandler?.webView(self, perform: .grokipedia) }
    @objc private func menuSearchWeb() { menuHandler?.webView(self, perform: .searchWeb) }
    @objc private func menuFillBotEmail() { menuHandler?.webView(self, perform: .fillBotEmail) }
    @objc private func menuAddToCollection(_ sender: NSMenuItem) {
        guard let handler = menuHandler, handler.collections.indices.contains(sender.tag) else { return }
        handler.webView(self, perform: .addToCollection(handler.collections[sender.tag].id))
    }
    @objc private func menuAddToNewCollection() { menuHandler?.webView(self, perform: .addToCollection(nil)) }
    @objc private func menuRewrite(_ sender: NSMenuItem) {
        guard RewriteStyle.allCases.indices.contains(sender.tag) else { return }
        menuHandler?.webView(self, perform: .rewrite(RewriteStyle.allCases[sender.tag]))
    }

    /// Captures the selection the user right-clicked on and remembers where it is, tagged with the
    /// page's token so a later replace can't land on a different page.
    func captureSelection(token: String) async -> PageSelection {
        guard let result = await PageScripts.run(PageScripts.captureSelection, arguments: ["token": token], in: self) as? [String: Any] else {
            return PageSelection(text: "", editable: false, isField: false, isEmailField: false)
        }
        var rect: CGRect?
        if let box = result["rect"] as? [String: Any],
           let x = (box["x"] as? NSNumber)?.doubleValue, let y = (box["y"] as? NSNumber)?.doubleValue,
           let w = (box["w"] as? NSNumber)?.doubleValue, let h = (box["h"] as? NSNumber)?.doubleValue {
            rect = CGRect(x: x, y: y, width: w, height: h)
        }
        return PageSelection(
            text: (result["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            editable: result["editable"] as? Bool ?? false,
            isField: result["isField"] as? Bool ?? false,
            isEmailField: result["isEmailField"] as? Bool ?? false,
            rect: rect
        )
    }

    /// A rectangle in the page's own coordinates (CSS pixels from the top left of what's on
    /// screen), on screen.
    func screenRect(forPage rect: CGRect) -> NSRect? {
        guard let window else { return nil }
        let zoom = pageZoom * magnification
        var viewRect = CGRect(x: rect.minX * zoom, y: rect.minY * zoom, width: rect.width * zoom, height: rect.height * zoom)
        if !isFlipped { viewRect.origin.y = bounds.height - viewRect.maxY }
        viewRect = viewRect.intersection(bounds)
        guard !viewRect.isNull, !viewRect.isEmpty || viewRect.width > 0 else { return nil }
        return window.convertToScreen(convert(viewRect, to: nil))
    }
}

struct PageSelection {
    let text: String
    let editable: Bool
    let isField: Bool
    let isEmailField: Bool
    /// Where the selection is, in the page's coordinates.
    var rect: CGRect? = nil
}
