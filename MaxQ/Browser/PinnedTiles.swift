//
//  PinnedTiles.swift
//  Max Q
//
//  SpaceXAI's sites pinned across the top of the sidebar: Grok, Grokipedia and X, plus the Grok
//  Bot app. Each site is a tab of its own that stays put, so a tile switches to it rather than
//  opening another tab, and clicking the tile on screen goes back to the site's front page.
//
//  The tile on screen is lifted onto the page's own surface, as if it were a piece of the page
//  card, and the lift glides from tile to tile on grok.com's segmented-control spring. An open
//  site keeps the Dock's small dot; one that's loading runs grok.com's spectrum line along its foot.
//

import AppKit
import SwiftUI

struct PinnedTiles: View {
    @Bindable var browser: BrowserModel
    /// The compact rail stacks the tiles as round-cornered icons.
    var vertical = false
    @Namespace private var lift

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 6))
        layout {
            ForEach(Launcher.allCases) { launcher in
                PinnedTile(browser: browser, launcher: launcher, compact: vertical, namespace: lift)
            }
        }
        .animation(Motion.glide, value: browser.selectedPinned)
    }
}

private struct PinnedTile: View {
    @Bindable var browser: BrowserModel
    let launcher: Launcher
    let compact: Bool
    let namespace: Namespace.ID

    @State private var hovering = false

    private var tab: BrowserTab? { browser.pinnedTabs[launcher] }
    private var selected: Bool { browser.selectedPinned == launcher }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? Theme.Radius.row : 14, style: .continuous)
        Button {
            browser.openPinned(launcher)
        } label: {
            LauncherIcon(launcher: launcher, size: compact ? 18 : 20)
                .scaleEffect(hovering && !selected ? 1.08 : 1)
                .frame(maxWidth: compact ? nil : .infinity)
                .frame(width: compact ? 36 : nil, height: compact ? 36 : 44)
                .background {
                    if selected {
                        shape.fill(Theme.raised)
                            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
                            .elevation(.raised)
                            .matchedGeometryEffect(id: "lift", in: namespace)
                    } else if !compact || hovering {
                        shape.fill(hovering ? Theme.selected : Theme.hover)
                    }
                }
                .overlay(alignment: .bottom) { foot }
                .overlay(alignment: .topTrailing) {
                    if let count = unread {
                        UnreadBadge(count: count)
                            .offset(x: compact ? 5 : 4, y: compact ? -5 : -4)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if launcher == .grokBot, hovering, !compact {
                        // Grok Bot is an app: this tile leaves the browser.
                        Icon(.arrowUpRight, size: 10, weight: 2)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(5)
                            .transition(.opacity)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(TilePress())
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.outQuint(0.3), value: tab?.isLoading == true)
        .animation(Motion.snappy, value: tab == nil)
        .animation(Motion.pop, value: unread == nil)
        .tip(verbatim: tipText, placement: compact ? .trailing : .below(.center))
        .contextMenu { menu }
        .accessibilityLabel(selected ? String(localized: "\(launcher.title), current") : launcher.title)
    }

    @ViewBuilder
    private var foot: some View {
        if let tab, tab.isLoading {
            SpectrumLine(height: 2, growDelay: 0, sweepDelay: 0, looping: true, restingOpacity: 0.5)
                .padding(.horizontal, compact ? 8 : 12)
                .padding(.bottom, 2)
                .transition(.opacity)
        } else if tab != nil, !selected {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: 4, height: 4)
                .padding(.bottom, compact ? 2 : 4)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
        }
    }

    /// What's new on the site, from the count it puts in its title, while it isn't on screen.
    private var unread: String? {
        guard !selected else { return nil }
        return tab?.unreadCount
    }

    private var tipText: String {
        if let unread {
            return unread == "1" ? String(localized: "\(launcher.title) · 1 new") : String(localized: "\(launcher.title) · \(unread) new")
        }
        return switch launcher {
        case .grokBot: GrokBot.isInstalled ? String(localized: "Open the Grok Bot app") : String(localized: "Get the Grok Bot app")
        default: launcher.title
        }
    }

    @ViewBuilder
    private var menu: some View {
        if launcher == .grokBot {
            Button(GrokBot.isInstalled ? "Open Grok Bot" : "Get Grok Bot") { browser.openPinned(launcher) }
        } else {
            Button(tab == nil ? "Open \(launcher.title)" : "Go to the Front Page") {
                if let home = launcher.destination, let tab {
                    browser.select(tab)
                    tab.load(home)
                } else {
                    browser.openPinned(launcher)
                }
            }
            if let tab {
                Button("Reload") { tab.reload() }
                Button("Copy Link") {
                    if let url = tab.url {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                }
                Divider()
                Button("Close \(launcher.title)") { browser.putAway(launcher) }
            }
        }
    }
}

/// Tiles sink a little under the finger, on grok.com's snappy spring.
private struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// A site's count of what's new, in Grok's blue, the way the Dock badges an app: it pops in, and
/// its figures roll when the count changes.
private struct UnreadBadge: View {
    let count: String

    var body: some View {
        Text(count)
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.onAccent)
            .contentTransition(.numericText())
            .padding(.horizontal, 4.5)
            .frame(minWidth: 17, minHeight: 17)
            .background(Capsule().fill(Theme.accent))
            .overlay(Capsule().strokeBorder(Theme.canvas, lineWidth: 2).padding(-1.5))
            .animation(Motion.snappy, value: count)
            .accessibilityLabel(count == "1" ? String(localized: "1 new") : String(localized: "\(count) new"))
    }
}
