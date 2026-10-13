//
//  CommandBarView.swift
//  Max Q
//
//  The ⌘K bar: a tray that drops in under the toolbar over a dimmed window, and changes height
//  with what it lists (each step its own height, the way Family's trays do). One field, then the
//  groups; the row picked carries a veil that glides from row to row on grok.com's selection
//  spring. Commands with choices open them in place, with the command's name as a chip in the
//  field and Escape to go back.
//

import SwiftUI

struct CommandBarView: View {
    @Bindable var bar: CommandBar
    @FocusState private var focused: Bool
    @Namespace private var veil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let items = bar.items
        ZStack(alignment: .top) {
            Color.black.opacity(scheme == .dark ? 0.34 : 0.14)
                .ignoresSafeArea()
                .onTapGesture { bar.close() }
                .transition(.opacity)

            VStack(spacing: 0) {
                field
                if !items.isEmpty {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    list(items)
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                footer
            }
            .frame(width: 640)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).fill(Theme.elevated))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .elevation(.menu)
            .padding(.top, 64)
            .transition(.asymmetric(
                insertion: .modifier(active: BarEntrance(shown: false), identity: BarEntrance(shown: true)),
                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
            .animation(Motion.smooth, value: items.map(\.id))
        }
        .onAppear {
            BrowserCommandRouter.openWindow = { id in openWindow(id: id) }
            BrowserCommandRouter.openSettings = { openSettings() }
            DispatchQueue.main.async { focused = true }
        }
    }

    // MARK: - The field

    private var field: some View {
        HStack(spacing: 12) {
            Icon(.search, size: 18)
                .foregroundStyle(Theme.textTertiary)
            if let chip = pageTitle {
                Text(chip)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Theme.selected))
                    .transition(.pop(anchor: .leading, scale: 0.9))
            }
            TextField(placeholder, text: $bar.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focused)
                .onSubmit { bar.runSelected() }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    withAnimation(Motion.smooth) { bar.back() }
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard bar.query.isEmpty, bar.page != .root else { return .ignored }
                    withAnimation(Motion.smooth) { bar.back() }
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    bar.askGrok()
                    return .handled
                }
            if bar.readingTabs {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
            KeyHint("esc")
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .animation(Motion.snappy, value: bar.page)
    }

    private var placeholder: String {
        switch bar.page {
        case .root: String(localized: "Search your tabs and commands, or ask Grok")
        case .effort: String(localized: "How hard Grok works")
        case .theme: String(localized: "Theme")
        case .splitWith: String(localized: "The tab to put beside this one")
        }
    }

    private var pageTitle: String? {
        switch bar.page {
        case .root: nil
        case .effort: String(localized: "Grok Effort")
        case .theme: String(localized: "Theme")
        case .splitWith: String(localized: "Split View")
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        withAnimation(Motion.glide) { bar.moveSelection(by: delta) }
        return .handled
    }

    // MARK: - The list

    private func list(_ items: [CommandBar.Item]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index == 0 || items[index - 1].section != item.section {
                            if let title = item.section.title {
                                Text(title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(.horizontal, 14)
                                    .padding(.top, index == 0 ? 6 : 12)
                                    .padding(.bottom, 4)
                            } else if index > 0 {
                                Spacer().frame(height: 6)
                            }
                        }
                        CommandRow(item: item, selected: index == bar.selection, veil: veil, query: bar.query)
                            .id(item.id)
                            // Results change at once, as cmdk's do; only the tray's height moves.
                            .transition(.identity)
                            .onTapGesture {
                                bar.selection = index
                                item.run()
                            }
                            .onHover { inside in
                                if inside, bar.selection != index { withAnimation(Motion.glide) { bar.selection = index } }
                            }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 440)
            .fixedSize(horizontal: false, vertical: true)
            .scrollEdgeFade(12)
            .onChange(of: bar.selection) { _, index in
                guard items.indices.contains(index) else { return }
                withAnimation(Motion.smooth) { proxy.scrollTo(items[index].id) }
            }
        }
    }

    // MARK: - The foot

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", String(localized: "to move"))
            hint("↩", String(localized: "to open"))
            hint("⌘↩", String(localized: "to ask Grok"))
            Spacer()
            if bar.page != .root {
                hint("⌫", String(localized: "to go back"))
            } else {
                hint("⌘K", String(localized: "to close"))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 36)
    }

    private func hint(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(keys).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
        }
    }
}

/// The bar arriving: down a few points from under the toolbar, out of a slight blur, from 97%.
private struct BarEntrance: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.97, anchor: .top)
            .offset(y: shown ? 0 : -8)
            .blur(radius: shown ? 0 : 4)
    }
}

private struct CommandRow: View {
    let item: CommandBar.Item
    let selected: Bool
    let veil: Namespace.ID
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            glyph
                .frame(width: 22, height: 22)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }
                if let snippet = item.snippet {
                    Text(snippet)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textQuaternary)
            }
            if item.checked {
                Icon(.check, size: 15)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, item.snippet == nil ? 0 : 8)
        .frame(minHeight: 40)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.hover)
                    .matchedGeometryEffect(id: "veil", in: veil)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var glyph: some View {
        switch item.glyph {
        case .icon(let icon):
            Icon(icon, size: 18)
        case .site(let host):
            ResultIcon(host: host, size: 16)
        }
    }
}
