//
//  ResultsKeyboard.swift
//  Max Q
//
//  The results page from the keyboard, with x.com's keys: J and K move a highlight through the
//  results, Return opens the one picked (⌘ Return in a new tab), ← and → slide between All,
//  Grokipedia and Posts on X, / goes back to the search field and ? lists the keys.
//
//  Keys only count while the page itself has the keyboard: typing in a field, or browsing x.com's
//  own page in the Posts on X tab, goes on as usual.
//

import AppKit
import SwiftUI
import WebKit

@MainActor
final class ResultsKeyboard {
    weak var search: GrokSearch?
    weak var browser: BrowserModel?
    weak var tab: BrowserTab?
    /// Shows (or hides) the list of keys.
    var toggleKeys: () -> Void = {}
    /// The list of keys is open: Escape closes it.
    var keysShown: () -> Bool = { false }

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let search, let browser, let tab, tab.isSelected, tab.nativeSearch == search.query,
              let window = browser.window, event.window === window, window.isKeyWindow,
              PopoverController.active == nil, !browser.addressFocused else { return false }
        let responder = window.firstResponder
        // Typing in a field, or x.com's own page under the Posts on X tab.
        if responder is NSText { return false }
        if let webView = responder as? WKWebView, webView !== tab.webView { return false }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers ?? ""

        if keysShown() {
            if event.keyCode == 53 || key == "?" { toggleKeys(); return true }
            return false
        }

        switch event.keyCode {
        case 36, 76: // Return
            guard flags.isSubset(of: [.command, .shift]), let url = search.pickedLink else { return false }
            if flags.contains(.command) {
                browser.openInNewTab(url, select: flags.contains(.shift))
            } else {
                browser.navigate(.url(url))
            }
            return true
        case 53: // Escape
            guard search.picked[search.tab] != nil else { return false }
            withAnimation(Motion.glide) { search.picked[search.tab] = nil }
            return true
        case 123, 124: // ← →
            guard flags.isEmpty else { return false }
            let tabs = GrokSearchTab.allCases
            let next = search.tab.index + (event.keyCode == 124 ? 1 : -1)
            guard tabs.indices.contains(next) else { return true }
            search.show(tabs[next])
            return true
        default:
            break
        }

        guard flags.isSubset(of: [.shift]) else { return false }
        switch key {
        case "j", "k":
            guard flags.isEmpty else { return false }
            if search.tab == .grokipedia, search.showsWholeArticle {
                // In an article, J and K read on by section.
                search.stepSection(by: key == "j" ? 1 : -1)
                return true
            }
            withAnimation(Motion.glide) { search.movePick(by: key == "j" ? 1 : -1) }
            return true
        case "/":
            browser.requestAddressFocus()
            return true
        case "?":
            toggleKeys()
            return true
        default:
            return false
        }
    }
}

/// The keys of the results page, as x.com lists its own: what each does, and the key.
struct ResultsKeysSheet: View {
    let close: () -> Void

    private let rows: [(String, [String])] = [
        (String(localized: "Next result"), ["J"]),
        (String(localized: "Previous result"), ["K"]),
        (String(localized: "Next or previous section of an article"), ["J", "K"]),
        (String(localized: "Open the result"), ["↩"]),
        (String(localized: "Open it in a new tab"), ["⌘", "↩"]),
        (String(localized: "Previous or next tab"), ["←", "→"]),
        (String(localized: "Search again"), ["/"]),
        (String(localized: "Show these keys"), ["?"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard shortcuts")
                    .font(.heading(17))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: close) { Icon(.close, size: 15) }
                    .iconButton(size: 30)
                    .accessibilityLabel("Close")
            }
            .padding(.bottom, 10)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                HStack {
                    Text(row.0)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 16)
                    HStack(spacing: 4) {
                        ForEach(row.1, id: \.self) { key in
                            Text(key)
                                .font(.mono(12, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(minWidth: 24, minHeight: 24)
                                .padding(.horizontal, key.count > 1 ? 6 : 0)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.hover))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                        }
                    }
                }
                .frame(height: 42)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(width: 400)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
    }
}
