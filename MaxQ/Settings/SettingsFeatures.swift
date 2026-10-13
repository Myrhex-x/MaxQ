//
//  SettingsFeatures.swift
//  Max Q
//
//  Settings for the newer parts of Max Q, as groups the pages place: the new-tab page's news,
//  link previews and the Max Q bar, Spaces and iCloud (General); budgets, the Mac's own model and
//  spending by feature (Grok); remembering what pages say (Privacy).
//

import SwiftUI

// MARK: - General

struct BrowsingSettingsGroups: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsGroup(title: "New tab page") {
            SettingsRow(title: "Today's news",
                        detail: "Stories under the search, by topic, from the outlets' own news feeds. Choose the topics on the page.") {
                Toggle("", isOn: $settings.homeNews).labelsHidden()
            }
        }

        SettingsGroup(title: "Browsing") {
            SettingsRow(title: "Link previews",
                        detail: "Hold ⌥ over a link to see where it goes before opening it. In Reader, rest on a link.") {
                Toggle("", isOn: $settings.linkPreviews).labelsHidden()
            }
            SettingsRow(title: "Max Q bar from any app",
                        detail: "Ask Grok or search without leaving what you're doing. Max Q is in the Services menu too.") {
                PillMenu(options: GlobalShortcut.allCases.map { ($0, $0.label) }, selection: $settings.globalShortcut)
            }
        }
    }
}

/// The Brave Search API key that fills Max Q's results page.
struct SearchKeyRows: View {
    private var account: SearchAPIAccount { SearchAPIAccount.shared }
    @State private var newKey = ""
    @State private var message: String?

    var body: some View {
        SettingsRow(title: account.hasKey ? "Search key" : "Add a search key",
                    verbatimDetail: message ?? (account.hasKey
                        ? String(localized: "Web results, pictures, videos and news on Max Q's results page come from the Brave Search API with this key.")
                        : String(localized: "For web results, pictures and videos on Max Q's results page: a Brave Search API key, from a free Brave account. Until then, those searches open on DuckDuckGo."))) {
            HStack(spacing: 8) {
                if account.hasKey {
                    Text(account.keyHint).font(.mono(12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Button("Remove") {
                        account.removeKey()
                        message = String(localized: "Key removed from your Keychain.")
                    }
                    .pill(.ghost, size: .small)
                } else {
                    PillField(placeholder: "Brave Search API key", text: $newKey, secure: true, monospaced: true, onSubmit: save)
                        .frame(width: 180)
                    if account.checking {
                        ShimmerText(text: String(localized: "Checking"), font: .system(size: 13, weight: .medium))
                            .transition(.opacity)
                    }
                    Button("Save", action: save)
                        .pill(.primary, size: .small)
                        .fixedSize()
                        .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || account.checking)
                }
            }
        }
        if !account.hasKey {
            HStack {
                Link(destination: URL(string: "https://brave.com/search/api/")!) {
                    HStack(spacing: 4) { Text("Get a key at brave.com/search/api"); Icon(.arrowUpRight, size: 12) }
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.link)
                Spacer()
            }
            .padding(.bottom, 12)
        }
    }

    private func save() {
        guard !account.checking else { return }
        Task {
            if let failure = await account.setKey(newKey) {
                message = failure
            } else {
                newKey = ""
                message = String(localized: "Key saved in your Keychain.")
            }
        }
    }
}

struct SpacesSettingsGroup: View {
    private var store: SpaceStore { SpaceStore.shared }
    @State private var names: [UUID: String] = [:]

    /// Spaces a window is showing can't be deleted from here.
    private var inUse: Set<UUID> { Set(BrowserRegistry.all.compactMap(\.spaceID)) }

    var body: some View {
        SettingsGroup(title: "Spaces",
                      footer: "Each space has its own sign-ins, cookies, site data and tabs. History, bookmarks and settings are shared. Switch spaces from the menu at the foot of the sidebar.") {
            SettingsRow(title: "Personal", detail: "The first space. It can't be deleted.") {
                EmptyView()
            }
            ForEach(store.spaces) { space in
                SettingsRow(title: LocalizedStringKey(space.name),
                            detail: inUse.contains(space.id) ? "Open in a window." : nil) {
                    HStack(spacing: 8) {
                        PillField(placeholder: "Name", text: binding(for: space)) {
                            store.rename(space.id, to: names[space.id] ?? space.name)
                        }
                        .frame(width: 150)
                        Button("Delete") { Task { await store.delete(space.id) } }
                            .pill(.ghost, size: .small)
                            .disabled(inUse.contains(space.id))
                    }
                }
            }
        }
    }

    private func binding(for space: BrowserSpace) -> Binding<String> {
        Binding {
            names[space.id] ?? space.name
        } set: { value in
            names[space.id] = value
            store.rename(space.id, to: value)
        }
    }
}

struct ICloudSettingsGroup: View {
    private var sync: CloudSync { CloudSync.shared }
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsGroup(title: "iCloud",
                      footer: "Collections, followed searches and bookmarks, between your Macs, in your own iCloud account and in encrypted fields. Tabs, history, website data and your API key stay on each Mac.") {
            SettingsRow(title: "Sync with iCloud", verbatimDetail: status) {
                Toggle("", isOn: Binding(get: { settings.iCloudSync && sync.isAvailable }, set: { sync.setEnabled($0) }))
                    .labelsHidden()
                    .disabled(!sync.isAvailable)
            }
            if sync.isAvailable, settings.iCloudSync {
                SettingsRow(title: "Sync now") {
                    Button("Sync") { sync.syncAll() }
                        .pill(.secondary, size: .small)
                        .disabled(sync.status == .syncing)
                }
            }
        }
    }

    private var status: String {
        switch sync.status {
        case .unavailable: String(localized: "This copy of Max Q isn't set up for iCloud yet.")
        case .off: String(localized: "Off")
        case .noAccount: String(localized: "Sign in to iCloud in System Settings to sync.")
        case .syncing: String(localized: "Syncing…")
        case .synced(let date): String(localized: "Up to date, \(date.formatted(.relative(presentation: .named))).")
        case .failed(let message): message
        }
    }
}

// MARK: - Grok

struct GrokFeatureSettingsGroups: View {
    @State private var settings = AppSettings.shared

    private static let researchBudgets: [Double] = [0.10, 0.25, 0.50, 1, 2]

    var body: some View {
        SettingsGroup(title: "Budgets",
                      footer: "Research and the agent stop before going over their budget, and ask before going on.") {
            SettingsRow(title: "Research starts with", detail: "Changed for each question on its start sheet.") {
                PillMenu(options: Self.researchBudgets.map { ($0, Money.usd($0)) }, selection: $settings.researchBudgetUSD)
            }
            SettingsRow(title: "An agent task may spend", detail: "Also in the agent's composer.") {
                PillMenu(options: AgentSession.budgets.map { ($0, Money.usd($0)) }, selection: $settings.agentBudgetUSD)
            }
        }

        SettingsGroup(title: "On this Mac",
                      footer: "Apple's on-device model is free and private: nothing leaves your Mac. It also sorts tabs into groups and writes the free summary.") {
            SettingsRow(title: "Skip Grok for simple searches",
                        verbatimDetail: OnDevice.isAvailable
                            ? String(localized: "The Mac's own model decides whether a search needs a written answer, so “gmail” or “weather” cost nothing.")
                            : OnDevice.unavailableReason) {
                Toggle("", isOn: $settings.onDeviceSkipsGrok)
                    .labelsHidden()
                    .disabled(!OnDevice.isAvailable)
            }
        }
    }
}

/// This month's spending by feature, as rows with a bar each.
struct SpendingByFeature: View {
    private var account: GrokAccount { GrokAccount.shared }

    var body: some View {
        let rows = account.monthByPurpose
        if !rows.isEmpty {
            let peak = max(rows.map(\.usd).max() ?? 0, 0.0001)
            VStack(alignment: .leading, spacing: 8) {
                Text("This month, by feature")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                ForEach(rows, id: \.purpose) { row in
                    HStack(spacing: 10) {
                        Text(row.purpose.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 170, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Theme.textTertiary.opacity(0.35))
                                .frame(width: max(3, proxy.size.width * row.usd / peak), height: 5)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 12)
                        Text(GrokAccount.formatCost(row.usd))
                            .font(.mono(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Privacy

struct PageMemorySettingsGroup: View {
    @State private var settings = AppSettings.shared
    private var memory: PageMemory { PageMemory.shared }

    var body: some View {
        SettingsGroup(title: "Ask your history",
                      footer: "Kept in Max Q's folder on this Mac and never sent anywhere. Never kept: private windows, pages with a password field, mail, banking, sign-in and checkout pages, and Max Q's own pages.") {
            SettingsRow(title: "Remember what pages say",
                        detail: "So ⌘K finds a page you read by what it said, not only its title. Off until you turn it on.") {
                Toggle("", isOn: $settings.rememberPages).labelsHidden()
            }
            if settings.rememberPages || memory.count > 0 {
                SettingsRow(title: "Pages remembered", verbatimDetail: memory.count.formatted()) {
                    Button("Forget All") { memory.forgetAll() }
                        .pill(.ghost, size: .small)
                        .disabled(memory.count == 0)
                }
            }
        }
        .onAppear { memory.prepare() }
    }
}
