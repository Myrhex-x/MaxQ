//
//  SuggestionsPanel.swift
//  Max Q
//
//  The list under the address field, shaped like Grokipedia's search dropdown: a 20-point rounded
//  card that drops in from 4 points up, 40-point rows where the part you typed stands out and the
//  rest is dimmed, a chevron on each row, and a footer with the keys.
//

import SwiftUI

struct SuggestionsPanel: View {
    @Bindable var browser: BrowserModel
    var maxWidth: CGFloat = 640

    /// The list is offering shortcuts ("!" typed on its own).
    private var listsShortcuts: Bool {
        browser.suggestions.contains { if case .bangHint = $0.kind { true } else { false } }
    }

    /// The field holds a shortcut and its words ("!yt lofi").
    private var followsShortcut: Bool {
        if case .bang = browser.suggestions.first?.kind { true } else { false }
    }

    private var footer: String {
        if listsShortcuts { return String(localized: "↑↓ to move · Tab to pick a shortcut") }
        if followsShortcut { return String(localized: "↑↓ to move · Enter to open") }
        return String(localized: "↑↓ to move · Enter to open · ⌘ Enter to ask Grok")
    }

    var body: some View {
        let engine = AppSettings.shared.searchEngine.name
        let typed = browser.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                ForEach(Array(browser.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    SuggestionRow(suggestion: suggestion, typed: typed, engineName: engine,
                                  isSelected: index == browser.suggestionIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { browser.activate(suggestion) }
                        .onHover { hovering in if hovering { browser.suggestionIndex = index } }
                }
            }
            .padding(6)

            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 12)
            HStack {
                Text(footer)
                Spacer()
                Text(listsShortcuts || followsShortcut ? "Esc to close" : "Type ! for shortcuts")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 18)
            .frame(height: 34)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
    }
}

private struct SuggestionRow: View {
    let suggestion: AddressSuggestion
    let typed: String
    let engineName: String
    let isSelected: Bool

    private var isGrok: Bool {
        if case .askGrok = suggestion.kind { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 20, height: 20)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
            highlighted(suggestion.title(engineName: engineName))
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.middle)
            if let subtitle = suggestion.subtitle(engineName: engineName) {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 8)
            if isGrok {
                Text("⌘↩")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textQuaternary)
            }
            if let bang = suggestion.bang {
                // The shortcut itself, as a key to remember.
                Text("!" + bang.trigger)
                    .font(.mono(11.5, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? Theme.selected : Theme.hover))
            }
            Icon(.chevronRight, size: 14)
                .foregroundStyle(isSelected ? Theme.textSecondary : Theme.textQuaternary)
                .offset(x: isSelected ? 0 : -3)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(isSelected ? Theme.hover : .clear)
        )
        .animation(Motion.standard(0.12), value: isSelected)
    }

    /// The part the user typed in full strength, the rest dimmed (Grokipedia's dropdown).
    private func highlighted(_ title: String) -> Text {
        guard !typed.isEmpty, let range = title.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(title).foregroundStyle(Theme.textPrimary)
        }
        return Text(String(title[..<range.lowerBound])).foregroundStyle(Theme.textSecondary)
            + Text(String(title[range])).foregroundStyle(Theme.textPrimary)
            + Text(String(title[range.upperBound...])).foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private var icon: some View {
        switch suggestion.kind {
        case .history(let url, _), .open(let url), .bookmark(let url, _, _):
            if let image = FaviconStore.shared.icon(for: url.host) {
                SiteIcon(image: image, tone: FaviconStore.shared.tone(for: url.host), size: 16, cornerRadius: 4)
            } else {
                Icon(.globe, size: 17)
            }
        case .askGrok:
            Icon(.bubble, size: 17)
        case .search, .engineSuggestion:
            Icon(.search, size: 17)
        case .bang, .bangHint:
            if let bang = suggestion.bang {
                ResultIcon(host: bang.host, size: 16)
            }
        }
    }
}
