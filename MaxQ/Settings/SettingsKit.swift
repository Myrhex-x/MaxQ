//
//  SettingsKit.swift
//  Max Q
//
//  Building blocks for Settings, laid out like grok.com's settings: a page title, then plain rows
//  on hairlines (a label and a line of detail on the left, the control on the right), grok.com's
//  switch, and menus that open as SpaceXAI-style dropdowns.
//

import SwiftUI

struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder var content: Content
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.heading(24))
                        .tracking(-0.48)
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .reveal(revealed)
                content
                    .reveal(revealed, delay: 0.06)
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 36)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .scrollEdgeFade()
        .onAppear { revealed = true }
    }
}

struct SettingsGroup<Content: View>: View {
    var title: LocalizedStringKey? = nil
    var footer: Text? = nil
    /// What the footer says, to animate when it changes.
    private var footerKey: String = ""
    @ViewBuilder var content: Content

    init(title: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer.map { Text($0) }
        footerKey = footer.map { "\($0)" } ?? ""
        self.content = content()
    }

    /// A footer whose words are already what to show (a message from the last action).
    init(title: LocalizedStringKey? = nil, verbatimFooter: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        footer = verbatimFooter.map { Text(verbatim: $0) }
        footerKey = verbatimFooter ?? ""
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 6)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        row
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                }
            }
            if let footer {
                footer
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .transition(.blurFade())
            }
        }
        .animation(Motion.standard(0.2), value: footerKey)
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: LocalizedStringKey
    var detail: Text? = nil
    @ViewBuilder var accessory: Accessory

    init(title: LocalizedStringKey, detail: LocalizedStringKey? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail.map { Text($0) }
        self.accessory = accessory()
    }

    /// A row whose detail is already what to show (a status, a list of sites).
    init(title: LocalizedStringKey, verbatimDetail: String?, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        detail = verbatimDetail.map { Text(verbatim: $0) }
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    detail
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.vertical, 13)
    }
}

/// grok.com's switch: a small track that turns white (black in light mode) with a dark knob.
struct GrokToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(Motion.spring(0.32)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 0)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Theme.ink : Theme.selected)
                        .frame(width: 36, height: 20)
                    Circle()
                        .fill(configuration.isOn ? Theme.onInk : Theme.textPrimary.opacity(0.9))
                        .frame(width: 16, height: 16)
                        .padding(2)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// A choice shown as its current value with a chevron, opening a SpaceXAI-style dropdown.
struct PillMenu<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        MenuButton(placement: .below(.trailing)) { _ in
            HStack(spacing: 6) {
                Text(options.first { $0.0 == selection }?.1 ?? "")
                    .lineLimit(1)
                Icon(.chevronUpDown, size: 13)
                    .foregroundStyle(Theme.textTertiary)
            }
        } content: {
            MenuCard(width: max(200, CGFloat(options.map(\.1.count).max() ?? 10) * 8 + 80)) {
                ForEach(options, id: \.0) { option in
                    MenuRow(verbatim: option.1, checked: option.0 == selection) { selection = option.0 }
                }
            }
        }
        .pill(.outline, size: .mini)
    }
}

/// A text field shaped like grok.com's inputs.
struct PillField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var secure = false
    var monospaced = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(monospaced ? .mono(13, weight: .regular) : .system(size: 13.5))
        .focused($focused)
        .onSubmit(onSubmit)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule().fill(Theme.input))
        .overlay(Capsule().strokeBorder(focused ? Theme.border : Theme.composerBorder, lineWidth: 1))
        .animation(Motion.standard(0.18), value: focused)
    }
}
