//
//  AddressField.swift
//  Max Q
//
//  The address and search field in two forms:
//    - On the new-tab page, grok.com's composer: a 24-point rounded box, hints that roll by in the
//      empty field (Grokipedia's search does this), the search engine chosen like grok.com's
//      model ("Google" with a chevron), Ask Grok, and the blue send button.
//    - In the toolbar, Grokipedia's header search pill. While a page loads, grok.com's spectrum
//      line runs along its bottom edge. At rest it shows the site, its registrable domain in full
//      strength and any subdomain dimmed, so "apple.com.evil.example" reads as what it is.
//

import AppKit
import SwiftUI

struct AddressField: View {
    @Bindable var browser: BrowserModel
    var focus: FocusState<Bool>.Binding
    var isHero: Bool = false

    @State private var hovering = false

    private var tab: BrowserTab? { browser.selectedTab }
    private var isFocused: Bool { focus.wrappedValue }
    private var showsPage: Bool { !(tab?.isHome ?? true) && !isHero }

    private var emphasizedHost: (prefix: String, registrable: String)? {
        guard showsPage, !isFocused, tab?.searchQuery == nil, tab?.nativePage == nil,
              var host = tab?.url?.host, !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return DomainDisplay.split(host: host)
    }

    var body: some View {
        if isHero { composer } else { pill }
    }

    // MARK: - Home composer

    private static let hints = [
        String(localized: "Search the web or type an address"),
        String(localized: "Ask Grok anything with ⌘ Return"),
        String(localized: "Look up any topic on Grokipedia"),
        String(localized: "See what X is saying about a page"),
        String(localized: "Type !yt, !w or !gp to search there"),
        String(localized: "Paste a link to open it"),
    ]

    /// With Max Q as the engine, the hints say what its results page brings.
    private static let maxQHints = [
        String(localized: "Search with Max Q or type an address"),
        String(localized: "Grok's answer, the web and Grokipedia on one page"),
        String(localized: "Ask Grok anything with ⌘ Return"),
        String(localized: "See what X is saying about anything"),
        String(localized: "Type !x or !gp to open that tab"),
        String(localized: "Paste a link to open it"),
    ]

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                if browser.addressText.isEmpty {
                    HintCycler(hints: AppSettings.shared.searchEngine.isMaxQ ? Self.maxQHints : Self.hints, interval: 3.4, font: .system(size: 16),
                               color: Theme.textTertiary, lineHeight: 22, active: !isFocused)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                field(placeholder: "", size: 16)
            }
            .frame(height: 24)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            HStack(spacing: 6) {
                EngineMenu()
                Spacer(minLength: 8)
                Button {
                    askGrokFromField()
                } label: {
                    HStack(spacing: 6) {
                        Icon(.bubble, size: 16)
                        Text("Ask Grok")
                    }
                }
                .pill(.ghost, size: .mini)
                .tip("Ask Grok instead of searching", shortcut: "⌘↩")

                Button {
                    browser.submitAddress()
                } label: {
                    Icon(.arrowUp, size: 20, weight: 2.2)
                }
                .sendButton(size: 38)
                .disabled(!hasText)
                .tip("Go", shortcut: "↩")
                .accessibilityLabel("Go")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous)
                .fill(browser.isPrivate ? Theme.privateRaised : Theme.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous)
                .strokeBorder(isFocused ? Theme.border : (hovering ? Theme.hairline : Theme.composerBorder), lineWidth: 1)
        )
        .elevation(.composer)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous))
        .onTapGesture { takeFocus() }
        .onHover { hovering = $0 }
        .animation(Motion.standard(0.18), value: isFocused)
        .animation(Motion.hover, value: hovering)
        .animation(Motion.standard(0.2), value: browser.addressText.isEmpty)
    }

    private var hasText: Bool {
        !browser.addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Toolbar pill

    private var pill: some View {
        HStack(spacing: 8) {
            leadingIcon
            field(placeholder: String(localized: "Search or type an address"), size: 14)
                .overlay(alignment: .leading) {
                    if let host = emphasizedHost {
                        // Switching tabs, the site's name keeps its shared letters and glides.
                        HStack(spacing: 0) {
                            MorphLabel(text: host.prefix, font: .system(size: 14))
                                .foregroundStyle(Theme.textTertiary)
                            MorphLabel(text: host.registrable, font: .system(size: 14))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .allowsHitTesting(false)
                    }
                }
            if isFocused, !browser.addressText.isEmpty {
                Button { browser.addressText = "" } label: { Icon(.close, size: 13) }
                    .iconButton(size: 22)
                    .tip("Clear")
                    .accessibilityLabel("Clear")
                    .transition(.opacity)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, isFocused && !browser.addressText.isEmpty ? 6 : 14)
        .frame(height: 36)
        .background(Capsule().fill(isFocused || hovering ? Theme.input : Theme.raised))
        .overlay(Capsule().strokeBorder(isFocused ? Theme.border : Theme.hairline, lineWidth: 1))
        .overlay(alignment: .bottom) {
            if let tab, tab.isLoading {
                SpectrumLine(height: 2, growDelay: 0, sweepDelay: 0.1, looping: true, restingOpacity: 0.6)
                    .padding(.horizontal, 20)
                    .offset(y: -1)
                    .transition(.opacity.animation(Motion.outQuint(0.5)))
            }
        }
        .elevation(isFocused ? .composer : .raised)
        .contentShape(Capsule())
        .onTapGesture { takeFocus() }
        .onHover { hovering = $0 }
        .animation(Motion.standard(0.18), value: isFocused)
        .animation(Motion.hover, value: hovering)
        .animation(Motion.outQuint(0.4), value: tab?.isLoading)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        let (icon, tip): (MQIcon, String?) = {
            if isFocused || !showsPage || tab?.searchQuery != nil { return (.search, nil) }
            if let page = tab?.nativePage { return (page.icon, nil) }
            switch tab?.url?.scheme {
            case "https": return (.lock, String(localized: "Secure connection"))
            case "http": return (.warning, String(localized: "This page isn't encrypted"))
            default: return (.globe, nil)
            }
        }()
        Icon(icon, size: 15)
            .foregroundStyle(icon == .warning ? Theme.warning : Theme.textTertiary)
            .frame(width: 16)
            .modifier(OptionalTip(text: tip))
    }

    // MARK: - Shared text field

    private func field(placeholder: String, size: CGFloat) -> some View {
        TextField(placeholder, text: $browser.addressText)
            .textFieldStyle(.plain)
            .font(.system(size: size))
            .foregroundStyle(emphasizedHost == nil ? Theme.textPrimary : .clear)
            .focused(focus)
            .onSubmit { browser.submitAddress() }
            .onChange(of: browser.addressText) { _, _ in
                if isFocused { browser.addressTextChanged() }
            }
            .onKeyPress(.downArrow) {
                browser.moveSuggestionSelection(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                browser.moveSuggestionSelection(by: -1)
                return .handled
            }
            .onKeyPress(.tab) {
                // Tab completes a shortcut being typed ("!y" → "!yt ").
                browser.completeShortcut() ? .handled : .ignored
            }
            .onKeyPress(.escape) {
                if !browser.suggestions.isEmpty {
                    browser.dismissSuggestions()
                } else {
                    browser.syncAddressText()
                    focus.wrappedValue = false
                }
                return .handled
            }
            .onKeyPress(.return, phases: .down) { press in
                // Command-Return asks Grok instead of searching.
                guard press.modifiers.contains(.command) else { return .ignored }
                askGrokFromField()
                return .handled
            }
    }

    private func askGrokFromField() {
        let text = browser.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            browser.grokPanelVisible = true
            browser.requestComposerFocus()
        } else {
            browser.activate(AddressSuggestion(kind: .askGrok(text)))
        }
    }

    /// A focused web view can hold on to keyboard focus; take it back for clicks on the field's
    /// padding or icons. Clicks while already editing just place the cursor.
    private func takeFocus() {
        guard !focus.wrappedValue else { return }
        browser.window?.makeFirstResponder(nil)
        DispatchQueue.main.async { focus.wrappedValue = true }
    }
}

private struct OptionalTip: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text { content.tip(verbatim: text) } else { content }
    }
}

/// The search engine, chosen the way grok.com picks a model: its name and a chevron, opening a
/// menu of engines with their own icons.
struct EngineMenu: View {
    @State private var settings = AppSettings.shared

    private var engines: [SearchEngineID] {
        SearchEngineID.allCases.filter { $0 != .custom || SearchEngine.isValidTemplate(settings.customSearchTemplate) }
    }

    var body: some View {
        MenuButton(placement: .below(.leading)) { isOpen in
            HStack(spacing: 6) {
                EngineIcon(engine: settings.searchEngine, size: 15)
                Text(settings.searchEngine.name)
                MorphChevron(open: isOpen, size: 14)
            }
        } content: {
            MenuCard(width: 230) {
                MenuSectionTitle("Search with")
                ForEach(engines) { id in
                    let engine = SearchEngine.builtIn(id) ?? SearchEngine.custom(template: settings.customSearchTemplate)
                    if id == .maxq {
                        MenuRow(icon: .search, title: "Max Q", detail: "Grok's answer, web, X", checked: settings.searchEngineID == id) {
                            settings.searchEngineID = id
                        }
                        MenuDivider()
                    } else {
                        MenuRow(image: engine.flatMap { FaviconStore.shared.icon(for: $0.siteURL?.host) },
                                verbatim: engine?.name ?? String(localized: "Custom"),
                                checked: settings.searchEngineID == id) {
                            settings.searchEngineID = id
                        }
                    }
                }
            }
        }
        .pill(.ghost, size: .mini)
        .tip("Search engine")
        .onAppear {
            for id in SearchEngineID.allCases {
                if let url = SearchEngine.builtIn(id)?.siteURL { FaviconStore.shared.prefetchIcon(forSite: url) }
            }
        }
    }
}

struct EngineIcon: View {
    let engine: SearchEngine
    var size: CGFloat = 16

    var body: some View {
        if engine.isMaxQ {
            MaxQMark(size: size + 2, glow: false)
        } else if let image = FaviconStore.shared.icon(for: engine.siteURL?.host) {
            SiteIcon(image: image, tone: FaviconStore.shared.tone(for: engine.siteURL?.host), size: size, cornerRadius: size * 0.22)
        } else {
            Icon(.globe, size: size)
        }
    }
}

extension SearchEngine {
    /// The engine's own site, for its icon.
    var siteURL: URL? {
        guard !isMaxQ, let host = URLComponents(string: searchTemplate.replacingOccurrences(of: "%s", with: "q"))?.host else { return nil }
        return URL(string: "https://\(host)")
    }
}

/// Splits a host into a dimmed prefix and the bold registrable domain ("news." + "example.co.uk").
enum DomainDisplay {
    /// Second-level labels that act as public suffixes under a country code ("co.uk", "com.au").
    nonisolated private static let secondLevel: Set<String> = ["co", "com", "net", "org", "gov", "ac", "edu", "ne", "or", "go", "gv", "nic", "ltd", "plc"]

    nonisolated static func split(host: String) -> (prefix: String, registrable: String) {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return ("", host) }
        var keep = 2
        if let tld = labels.last, tld.count == 2, secondLevel.contains(labels[labels.count - 2]) {
            keep = 3
        }
        guard labels.count > keep else { return ("", host) }
        let registrable = labels.suffix(keep).joined(separator: ".")
        let prefix = labels.dropLast(keep).joined(separator: ".") + "."
        return (prefix, registrable)
    }
}
