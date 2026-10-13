//
//  SearchTabBar.swift
//  Max Q
//
//  The tabs across the top of Grok's results page, drawn the way x.com draws its tabs today
//  (measured from x.com, 2026): equal-width tabs 52 points tall, labels at 15 points and the same
//  medium weight whether chosen or not, the others at 60% until the pointer brings them up, and one
//  shared 3-point bar in the text color, as wide as the tab, sliding to the tab chosen. The band
//  is the page color at 80% over a blur of what scrolls beneath, with a half-point hairline.
//
//  All, Grokipedia and Posts on X are always there. The fourth tab is More: a classic engine's
//  Images, News and Videos, in a menu. Once one is picked, the tab takes its name ("News ⌄"), and
//  the menu stays on it to move to the others.
//
//  The bar never jumps: the edge facing the new tab sets off a beat before the other, so it
//  reaches toward where it's going and gathers itself on arrival (Benji Taylor's rule that a
//  transition shows the path from A to B).
//

import AppKit
import SwiftUI

struct SearchTabBar<Accessory: View>: View {
    @Binding var selection: GrokSearchTab
    /// Two columns: the tabs span the results column, and the side column's width holds the page's
    /// own control.
    let wide: Bool
    /// The tab behind More to name the More tab after while it's on show.
    var lastMore: GrokSearchTab = .images
    /// The pointer reached a tab: whatever it shows can start loading.
    var prepare: (GrokSearchTab) -> Void = { _ in }
    /// The page's control, beside the tabs (wide pages only).
    @ViewBuilder var accessory: () -> Accessory

    fileprivate static var space: String { "searchTabs" }

    /// Each place's frame: 0 to 2 the main tabs, 3 More.
    @State private var slotFrames: [Int: CGRect] = [:]
    @State private var leftEdge: CGFloat = 0
    @State private var rightEdge: CGFloat = 0
    @State private var placed = false

    var body: some View {
        HStack(alignment: .top, spacing: GrokSearchPage.gap) {
            HStack(spacing: 0) {
                ForEach(GrokSearchTab.main) { tab in
                    SearchTabButton(title: tab.title, selected: selection == tab) {
                        guard selection != tab else { return }
                        withAnimation(Motion.page) { selection = tab }
                    } hovered: {
                        prepare(tab)
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                        slotFrames[tab.index] = frame
                    }
                }
                MoreTab(selection: $selection, lastMore: lastMore)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                        slotFrames[3] = frame
                    }
            }
            .coordinateSpace(.named(Self.space))
            .overlay(alignment: .bottom) { indicator }
            .frame(maxWidth: GrokSearchPage.mainWidth)
            if wide {
                accessory()
                    .frame(width: GrokSearchPage.sideWidth, alignment: .trailing)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, wide ? 40 : 28)
        .frame(maxWidth: GrokSearchPage.mainWidth + (wide ? GrokSearchPage.gap + GrokSearchPage.sideWidth + 80 : 56))
        .frame(maxWidth: .infinity)
        .frame(height: searchTabBarHeight - 0.5)
        .background {
            BackdropBlur()
                .overlay(Theme.dynamic(light: Theme.hex(0xF9F8F7, 0.8), dark: Theme.hex(0x131211, 0.8)))
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.dynamic(light: Theme.hex(0x000000, 0.15), dark: Theme.hex(0xFFFFFF, 0.15)))
                .frame(height: 0.5)
                .offset(y: 0.5)
        }
        .padding(.bottom, 0.5)
        .onChange(of: selection.index) { old, new in move(to: new, from: old) }
        .onChange(of: slotFrames) { _, _ in move(to: selection.index, from: nil) }
    }

    // MARK: The bar

    private var indicator: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Theme.textPrimary)
                .padding(.leading, leftEdge)
                .padding(.trailing, max(0, proxy.size.width - rightEdge))
                .frame(width: proxy.size.width, height: 3, alignment: .leading)
        }
        .frame(height: 3)
        .opacity(placed ? 1 : 0)
        .allowsHitTesting(false)
    }

    private func move(to slot: Int, from old: Int?) {
        guard let frame = slotFrames[slot] else { return }
        guard placed, let old, old != slot else {
            // First layout, or the window changed size: just be there.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                leftEdge = frame.minX
                rightEdge = frame.maxX
                placed = true
            }
            return
        }
        // The leading edge sets off on a quick spring and the trailing one follows on a slightly
        // softer one. Two separate paddings, so each edge keeps its own spring.
        let lead = Animation.spring(duration: 0.3, bounce: 0)
        let trail = Animation.spring(duration: 0.42, bounce: 0)
        if slot > old {
            withAnimation(lead) { rightEdge = frame.maxX }
            withAnimation(trail) { leftEdge = frame.minX }
        } else {
            withAnimation(lead) { leftEdge = frame.minX }
            withAnimation(trail) { rightEdge = frame.maxX }
        }
    }
}

private struct SearchTabButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    let hovered: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selected || hovering ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { hovered() }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.15), value: hovering)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.15), value: selected)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The fourth tab: More, or the name of the tab behind it that's on show. It opens the menu of
/// Images, News and Videos.
private struct MoreTab: View {
    @Binding var selection: GrokSearchTab
    let lastMore: GrokSearchTab
    @State private var hovering = false

    private var shown: GrokSearchTab? { selection.isMore ? selection : nil }

    var body: some View {
        MenuButton(placement: .below(.center)) { isOpen in
            HStack(spacing: 5) {
                Text(shown?.title ?? String(localized: "More"))
                    .contentTransition(.interpolate)
                    .lineLimit(1)
                MorphChevron(open: isOpen, size: 12)
                    .opacity(0.7)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(shown != nil || hovering || isOpen ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        } content: {
            MenuCard(width: 230) {
                ForEach(GrokSearchTab.more) { tab in
                    MenuRow(icon: tab.icon, verbatim: tab.title, detail: tab.detail, checked: selection == tab) {
                        withAnimation(Motion.page) { selection = tab }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.15), value: hovering)
        .animation(Motion.smooth, value: shown)
        .accessibilityLabel(shown.map { String(localized: "\($0.title), more tabs") } ?? String(localized: "More tabs"))
        .accessibilityAddTraits(shown != nil ? [.isSelected, .isButton] : .isButton)
    }
}

extension GrokSearchTab {
    var icon: MQIcon {
        switch self {
        case .all: .search
        case .grokipedia: .book
        case .x: .bubble
        case .images: .image
        case .news: .doc
        case .videos: .play
        }
    }

    /// A line on what the tab shows, in More's menu.
    var detail: String? {
        switch self {
        case .images: String(localized: "From across the web")
        case .news: String(localized: "From news outlets")
        case .videos: String(localized: "With their length")
        default: nil
        }
    }
}

/// A blur of whatever lies under it in the window, like x.com's 12-pixel backdrop blur.
private struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .headerView
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The tab bar's height, as x.com's (53 points with its hairline).
let searchTabBarHeight: CGFloat = 53
