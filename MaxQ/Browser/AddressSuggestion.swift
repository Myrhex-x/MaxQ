//
//  AddressSuggestion.swift
//  Max Q
//
//  Rows under the address bar: the default action, "Ask Grok", history matches and the search
//  engine's own suggestions.
//

import Foundation

struct AddressSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case open(URL)
        case search(String)
        case askGrok(String)
        case history(URL, title: String)
        /// A bookmark brought over from another browser.
        case bookmark(URL, title: String, folder: String)
        case engineSuggestion(String)
        /// A shortcut with the words to send it ("!yt lofi").
        case bang(trigger: String, words: String)
        /// A shortcut offered while "!" is being typed: picking it puts it in the field.
        case bangHint(trigger: String)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .open(let url): "open:\(url.absoluteString)"
        case .search(let q): "search:\(q)"
        case .askGrok(let q): "grok:\(q)"
        case .history(let url, _): "history:\(url.absoluteString)"
        case .bookmark(let url, _, _): "bookmark:\(url.absoluteString)"
        case .engineSuggestion(let q): "suggest:\(q)"
        case let .bang(trigger, words): "bang:\(trigger):\(words)"
        case .bangHint(let trigger): "bangHint:\(trigger)"
        }
    }

    var symbol: String {
        switch kind {
        case .open: "globe"
        case .search, .engineSuggestion, .bang, .bangHint: "magnifyingglass"
        case .askGrok: "text.bubble"
        case .history: "clock"
        case .bookmark: "bookmark"
        }
    }

    /// The shortcut a row stands for, if it's one.
    var bang: Bang? {
        switch kind {
        case .bang(let trigger, _), .bangHint(let trigger): Bangs.find(trigger)
        default: nil
        }
    }

    func title(engineName: String) -> String {
        switch kind {
        case .open(let url): Self.displayURL(url)
        case .search(let q): q
        case .askGrok(let q): q
        case .history(let url, let title): title.isEmpty ? Self.displayURL(url) : title
        case .bookmark(let url, let title, _): title.isEmpty ? Self.displayURL(url) : title
        case .engineSuggestion(let q): q
        case let .bang(trigger, words): words.isEmpty ? (Bangs.find(trigger)?.name ?? trigger) : words
        case .bangHint(let trigger): Bangs.find(trigger)?.name ?? trigger
        }
    }

    func subtitle(engineName: String) -> String? {
        switch kind {
        case .open: String(localized: "Open website")
        case .search: String(localized: "Search \(engineName)")
        case .askGrok: String(localized: "Ask Grok")
        case .history(let url, _): Self.displayURL(url)
        case .bookmark(let url, _, let folder): folder.isEmpty ? Self.displayURL(url) : "\(folder) · \(Self.displayURL(url))"
        case .engineSuggestion: nil
        case let .bang(trigger, words): Bangs.find(trigger)?.action(for: words)
        case .bangHint: nil
        }
    }

    nonisolated static func displayURL(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
