//
//  SettingsView.swift
//  Max Q
//
//  Settings, laid out like grok.com's: a column of sections with a gliding highlight, and pages of
//  plain rows on hairlines.
//

import AppKit
import SwiftUI
import WebKit

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, grok, grokipedia, bot, privacy, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .grok: "Grok"
        case .grokipedia: "Grokipedia"
        case .bot: "Grok Bot"
        case .privacy: String(localized: "Privacy")
        case .about: String(localized: "About")
        }
    }

    var icon: MQIcon {
        switch self {
        case .general: .gear
        case .grok: .bubble
        case .grokipedia: .book
        case .bot: .envelope
        case .privacy: .shield
        case .about: .info
        }
    }
}

struct SettingsView: View {
    @State private var router = SettingsRouter.shared
    @Namespace private var selection

    private var section: SettingsSection { router.section }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(Theme.canvas)

            Group {
                switch section {
                case .general: GeneralSettings()
                case .grok: GrokSettings()
                case .grokipedia: GrokipediaSettings()
                case .bot: BotSettings()
                case .privacy: PrivacySettings()
                case .about: AboutSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, style: .continuous))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
            .id(section)
            .transition(.blurFade(radius: 3))
        }
        .frame(width: 800, height: 600)
        .background(Theme.canvas)
        .animation(Motion.standard(0.2), value: section)
        .toggleStyle(GrokToggleStyle())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Settings")
                .font(.heading(17))
                .tracking(-0.3)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 14)

            ForEach(SettingsSection.allCases) { item in
                SettingsNavRow(item: item, isSelected: item == section, namespace: selection) {
                    withAnimation(Motion.glide) { router.section = item }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
    }
}

private struct SettingsNavRow: View {
    let item: SettingsSection
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(item.icon, size: 18)
                    .foregroundStyle(isSelected || hovering ? Theme.textPrimary : Theme.textSecondary)
                Text(item.title)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected || hovering ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.selected)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.hover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @State private var settings = AppSettings.shared
    /// The Settings window, put away when setup opens.
    @State private var hostWindow = WeakWindow()
    @State private var name = AppSettings.shared.displayName
    @State private var customTemplate = AppSettings.shared.customSearchTemplate
    @State private var isDefaultBrowser = DefaultBrowser.isDefault
    @State private var showingImport = false

    private func saveName() {
        settings.displayName = AppSettings.cleanName(name)
    }

    /// Brings setup back over the last browser window used, and puts Settings away.
    private func openSetup() {
        guard let browser = BrowserRegistry.lastNormal else { return }
        browser.showSetup()
        if let settingsWindow = hostWindow.window, settingsWindow !== browser.window { settingsWindow.close() }
        browser.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    var body: some View {
        SettingsPage(title: "General", subtitle: "You, search, browsing, spaces, iCloud, setup, appearance and startup.") {
            SettingsGroup(title: "You") {
                SettingsRow(title: "Your name", detail: "Shown at the foot of the sidebar. It stays on this Mac.") {
                    HStack(spacing: 10) {
                        ProfileAvatar(name: settings.name, size: 26)
                            .animation(Motion.spring(0.35), value: settings.name)
                        PillField(placeholder: "Your name", text: $name) { saveName() }
                            .frame(width: 180)
                            .onChange(of: name) { _, _ in saveName() }
                    }
                }
            }

            SettingsGroup(title: "Search") {
                SettingsRow(title: "Search engine") {
                    PillMenu(options: SearchEngineID.allCases.map { ($0, SearchEngine.builtIn($0)?.name ?? String(localized: "Custom")) },
                             selection: $settings.searchEngineID)
                }
                if settings.searchEngineID == .maxq {
                    SearchKeyRows()
                }
                if settings.searchEngineID == .custom {
                    SettingsRow(title: "Results address",
                                detail: SearchEngine.isValidTemplate(customTemplate)
                                    ? "Example: https://search.example.org/search?q=%s"
                                    : "Enter an https address that contains %s exactly once.") {
                        PillField(placeholder: "https://…?q=%s", text: $customTemplate, monospaced: true) {
                            if SearchEngine.isValidTemplate(customTemplate) { settings.customSearchTemplate = customTemplate }
                        }
                        .frame(width: 220)
                        .onChange(of: customTemplate) { _, value in
                            if SearchEngine.isValidTemplate(value) { settings.customSearchTemplate = value }
                        }
                    }
                }
                SettingsRow(title: "Search suggestions",
                            detail: "Sends what you type to \(settings.searchEngine.suggestionProvider), like any browser's search box.") {
                    Toggle("", isOn: $settings.searchSuggestionsEnabled).labelsHidden()
                }
            }

            BrowsingSettingsGroups()

            SettingsGroup(title: "From another browser") {
                SettingsRow(title: "Import bookmarks and history",
                            detail: BookmarkStore.shared.count == 0
                                ? "From Chrome, Arc, Safari, Brave, Edge or Firefox, read on this Mac."
                                : "\(BookmarkStore.shared.count.formatted()) bookmarks here. They come up as you type.") {
                    HStack(spacing: 8) {
                        if BookmarkStore.shared.count > 0 {
                            Button("Remove All") { BookmarkStore.shared.removeAll() }
                                .pill(.ghost, size: .small)
                        }
                        Button("Import…") { showingImport = true }
                            .pill(.secondary, size: .small)
                    }
                }
            }

            SettingsGroup(title: "Setup") {
                SettingsRow(title: "Set up Max Q again",
                            detail: "The welcome steps: your name, connecting Grok, and how you search. Your tabs stay as they are.") {
                    Button("Open Setup") { openSetup() }
                        .pill(.secondary, size: .small)
                }
            }

            SettingsGroup(title: "Appearance") {
                SettingsRow(title: "Theme") {
                    PillMenu(options: AppearancePreference.allCases.map { ($0, $0.label) }, selection: $settings.appearance)
                }
            }

            SettingsGroup(title: "Startup") {
                SettingsRow(title: "Reopen tabs from last time") {
                    Toggle("", isOn: $settings.restoreSession).labelsHidden()
                }
                SettingsRow(title: isDefaultBrowser ? "Max Q is your default browser" : "Default browser",
                            detail: isDefaultBrowser ? nil : "Open links from other apps in Max Q.") {
                    if isDefaultBrowser {
                        Icon(.check, size: 18).foregroundStyle(Theme.success)
                    } else {
                        Button("Make Default") {
                            DefaultBrowser.makeDefault { isDefaultBrowser = DefaultBrowser.isDefault }
                        }
                        .pill(.primary, size: .small)
                    }
                }
            }

            SpacesSettingsGroup()

            ICloudSettingsGroup()
        }
        .background(WindowAccessor { window in hostWindow.window = window })
        .sheet(isPresented: $showingImport) { ImportView() }
    }
}

/// Holds a window without keeping it alive.
final class WeakWindow {
    weak var window: NSWindow?
}

enum DefaultBrowser {
    static var isDefault: Bool {
        guard let probe = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    static func makeDefault(completion: @escaping @MainActor () -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http") { _ in
            DispatchQueue.main.async { completion() }
        }
    }
}

// MARK: - Grok

private struct GrokSettings: View {
    @State private var settings = AppSettings.shared
    private var account: GrokAccount { GrokAccount.shared }
    private var webAccount: GrokWebAccount { GrokWebAccount.shared }
    @State private var newKey = ""
    @State private var message: String?
    @State private var checking = false

    var body: some View {
        SettingsPage(title: "Grok", subtitle: "Sign in to grok.com with your Grok account, or add your own SpaceXAI API key for Grok built into Max Q. Requests go straight from this Mac to SpaceXAI. Max Q has no server.") {
            SettingsGroup(title: "grok.com", footer: "The sign-in is SpaceXAI's own page and stays in Max Q like any site's, shared by your tabs and the Grok panel.") {
                SettingsRow(title: webAccount.isSignedIn ? "Signed in to grok.com" : "Not signed in to grok.com",
                            detail: webAccount.isSignedIn ? "Grok answers in the side panel with your Grok account." : "Free with a Grok account. No API key needed.") {
                    if webAccount.isSignedIn {
                        Button("Sign out") { Task { await webAccount.signOut() } }
                            .pill(.ghost, size: .small)
                    } else {
                        Button("Sign in") { signInToGrok() }
                            .pill(.primary, size: .small)
                    }
                }
            }

            SettingsGroup(title: "API key", verbatimFooter: message) {
                if account.hasKey {
                    SettingsRow(title: "Connected key", verbatimDetail: statusDetail) {
                        HStack(spacing: 8) {
                            Text(account.keyHint).font(.mono(12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                            if account.status == .valid { LiveDot(color: Theme.success, size: 6) }
                        }
                    }
                }
                SettingsRow(title: account.hasKey ? "Replace key" : "Add your key",
                            detail: "Create one at console.x.ai.") {
                    HStack(spacing: 8) {
                        PillField(placeholder: "xai-…", text: $newKey, secure: true, monospaced: true, onSubmit: save)
                            .frame(minWidth: 120, idealWidth: 180, maxWidth: 180)
                        // Its own width in every language ("Enregistrer" in French).
                        Button(checking ? "Checking" : "Save", action: save)
                            .pill(.primary, size: .small)
                            .fixedSize()
                            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                    }
                }
                HStack {
                    Link(destination: URL(string: "https://console.x.ai")!) {
                        HStack(spacing: 4) { Text("Open console.x.ai"); Icon(.arrowUpRight, size: 12) }
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.link)
                    Spacer()
                    if account.hasKey {
                        Button("Remove key") {
                            account.removeKey()
                            message = String(localized: "Key removed from your Keychain.")
                        }
                        .pill(.ghost, size: .small)
                    }
                }
                .padding(.vertical, 12)
            }

            SettingsGroup(title: "How hard Grok works",
                          footer: "Every answer is billed to your SpaceXAI account. Fast skips thinking and searches once; Expert uses Grok 4.7 and searches more. You can ask any answer again at another effort.") {
                SettingsRow(title: "Effort", verbatimDetail: effortDetail) {
                    EffortPicker(effort: $settings.grokEffort)
                }
                SettingsRow(title: "Search X",
                            detail: "Billed by the post read, about 10¢ a search. For news: only searches about news, live events and reactions.") {
                    PillMenu(options: XSearchPolicy.allCases.map { ($0, $0.label) }, selection: $settings.grokXSearch)
                }
                SettingsRow(title: "Model", verbatimDetail: settings.grokModel.isEmpty ? String(localized: "Chosen by the effort.") : priceDetail) {
                    PillMenu(options: [("", String(localized: "Matches the effort"))] + account.chatModels.map { ($0, UsageLine.modelName($0)) },
                             selection: $settings.grokModel)
                        .disabled(!account.hasKey)
                }
            }

            SettingsGroup(title: "Grok in Max Q search",
                          footer: account.hasKey
                            ? "Grok answers at the top of Max Q's results page, with its sources and the posts on X it cites. The same search within the hour shows the answer again for free."
                            : "Without an API key, grok.com answers in the side panel with your Grok account.") {
                SettingsRow(title: "Grok's answer") {
                    PillMenu(options: GrokAnswerMode.allCases.map { ($0, $0.label) }, selection: $settings.grokAnswerMode)
                }
            }

            SettingsGroup(title: "Side panel") {
                SettingsRow(title: "Open the panel in") {
                    PillMenu(options: [(GrokPanelMode.native, String(localized: "Chat (API key)")), (GrokPanelMode.web, "grok.com")],
                             selection: $settings.grokPanelMode)
                }
            }

            GrokFeatureSettingsGroups()

            SettingsGroup(title: "Spending",
                          footer: "From SpaceXAI's own cost for each request, kept on this Mac. Past the limit, Max Q asks before spending more, until the month ends. Your SpaceXAI console shows your full bill.") {
                SpendingSummary()
                SpendingByFeature()
                SettingsRow(title: "Monthly limit") {
                    PillMenu(options: SpendingLimits.options, selection: $settings.grokMonthlyLimitUSD)
                }
                SettingsRow(title: "Spent with Max Q in all") {
                    HStack(spacing: 10) {
                        Text(GrokAccount.formatCost(account.lifetimeCostUSD))
                            .font(.mono(13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Button("Reset") { account.resetLifetimeCost() }
                            .pill(.ghost, size: .small)
                    }
                }
            }

            SettingsGroup {
                SettingsRow(title: "Refresh the model list", detail: "Prices and models, from your key.") {
                    Button("Refresh") { Task { await account.refresh() } }
                        .pill(.secondary, size: .small)
                        .disabled(!account.hasKey)
                }
            }
        }
    }

    /// What the chosen effort does and usually costs here.
    private var effortDetail: String {
        let effort = settings.grokEffort
        let cost = GrokAccount.friendlyCost(account.typicalAnswerCost(effort, searchingX: false))
        return String(localized: "\(effort.detail). Usually \(cost) an answer.")
    }

    /// Opens SpaceXAI's sign-in page in a browser tab.
    private func signInToGrok() {
        guard let browser = BrowserRegistry.lastNormal else { return }
        browser.openInNewTab(GrokWebAccount.signInURL)
        browser.window?.makeKeyAndOrderFront(nil)
    }

    private var statusDetail: String {
        switch account.status {
        case .valid: String(localized: "Working · \(account.availableModels.count) models")
        case .checking: String(localized: "Checking…")
        case .invalid(let reason): reason
        case .unchecked, .none: String(localized: "Saved in your Keychain")
        }
    }

    private var priceDetail: String? {
        account.info(for: account.model)?.priceLabel
    }

    private func save() {
        let candidate = newKey
        checking = true
        message = nil
        Task {
            let failure = await account.setKey(candidate)
            checking = false
            if let failure {
                message = failure
            } else {
                newKey = ""
                message = String(localized: "Key saved. \(account.availableModels.count) models available.")
            }
        }
    }
}

// MARK: - Grokipedia

private struct GrokipediaSettings: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsPage(title: "Grokipedia", subtitle: "A card beside your search results with Grokipedia's article on the topic: its opening, key facts and a link to the full article.") {
            SettingsGroup(title: "Beside search results",
                          footer: "Max Q reads one article page per topic search, never Grokipedia's API, and links back to the full article. Private windows only look things up when you ask.") {
                SettingsRow(title: "Show the card") {
                    PillMenu(options: GrokipediaMode.allCases.map { ($0, $0.label) }, selection: $settings.grokipediaMode)
                }
            }
        }
    }
}

// MARK: - Grok Bot

private struct BotSettings: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsPage(title: "Grok Bot", subtitle: "SpaceXAI's agent app. Max Q can open it and send it pages by email. It can't control it: Grok Bot has no public API.") {
            SettingsGroup(title: "App") {
                SettingsRow(title: GrokBot.isInstalled ? "Grok Bot is installed" : "Grok Bot isn't installed") {
                    if GrokBot.isInstalled {
                        Button("Open") { GrokBot.open() }.pill(.secondary, size: .small)
                    } else {
                        Link("Get Grok Bot", destination: GrokBot.downloadPage)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            SettingsGroup(title: "Bot email",
                          footer: "Ask your Bot to claim its inbox, then paste the address. Click into an email field and Max Q offers it under the field, so sign-up codes and receipts go to your Bot; it's also in the menu when you right-click a field. Pages you send to your Bot go through your mail app. Stored on this Mac only.") {
                SettingsRow(title: "Your Bot's address",
                            detail: !settings.botEmail.isEmpty && !settings.botEmailIsValid ? "That doesn't look like an email address." : nil) {
                    PillField(placeholder: "…@mail.grokbot.com", text: $settings.botEmail)
                        .frame(width: 230)
                }
                SettingsRow(title: "Suggest it in email fields", detail: "Under the field, never filled without you.") {
                    Toggle("", isOn: $settings.botEmailSuggestions).labelsHidden()
                }
            }
        }
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @State private var cleared: String?
    @State private var settings = AppSettings.shared
    private var blocker: TrackerBlocker { TrackerBlocker.shared }

    var body: some View {
        SettingsPage(title: "Privacy", subtitle: "What leaves your Mac, and when.") {
            SettingsGroup(title: "What goes where") {
                bullet(.globe, String(localized: "Pages load straight from the sites you visit. Max Q has no server, no analytics and no telemetry."))
                bullet(.search, String(localized: "Searching with Max Q sends your search to Brave for web results, pictures, videos and news (with your own search key), to DuckDuckGo for suggestions as you type, to Grokipedia's own search for its article (and, when that finds nothing, to Wikipedia's public search for the usual spelling), and to SpaceXAI for Grok's answer: with your API key, or on grok.com in the side panel when you're signed in there."))
                bullet(.book, String(localized: "Grokipedia's articles and its search load in WebKit like any page you visit, one at a time, never through Grokipedia's API. Listen reads them aloud with your Mac's own voice."))
                bullet(.link, String(localized: "Posts on X is x.com's own search page, in your X account, shown as X serves it. Max Q reads nothing from it."))
                bullet(.cloudSun, String(localized: "A weather search asks Open-Meteo for that place's forecast, and a currency search asks Frankfurter for the European Central Bank's rate. Sums, units and times are worked out on this Mac."))
                bullet(.bubble, String(localized: "A page's text goes to SpaceXAI only when you ask Grok about it, and only with your own key."))
                bullet(.pointer, String(localized: "The agent sends the page it works on to SpaceXAI at each step, with your key, and asks you before anything that buys, sends, posts or deletes."))
                bullet(.image, String(localized: "Pictures, video stills and site icons on the results page are Brave's own copies; a picture you open full size loads from its site. News from the outlets' feeds shows the outlets' own pictures. A launch search asks The Space Devs' Launch Library."))
                bullet(.bell, String(localized: "Followed searches are looked for in the outlets' own news feeds about every twenty minutes while Max Q is open."))
                bullet(.eye, String(localized: "A link preview reads the start of the linked page from its site, without cookies, when you ask for one."))
                bullet(.cloud, String(localized: "With iCloud sync on, Collections, followed searches and bookmarks go to your own iCloud account, in encrypted fields."))
                bullet(.house, String(localized: "The grok.com panel is the real grok.com, signed in with your own account."))
                bullet(.envelope, String(localized: "Your Grok Bot's address stays on this Mac and goes only into the fields you pick."))
                bullet(.play, String(localized: "A question about a YouTube video reads the transcript panel you opened under it, and sends it to SpaceXAI with the question."))
                bullet(.key, String(localized: "Your API keys stay in your Keychain. History, tabs and settings stay on this Mac."))
            }

            SettingsGroup(title: "Trackers",
                          footer: "Analytics, ad and data-broker services that follow you from site to site: about 100 on Max Q's own list, blocked before the request leaves, only when a page loads them from another site. The shield in the toolbar shows what a page tried.") {
                SettingsRow(title: "Block trackers") {
                    Toggle("", isOn: $settings.blockTrackers).labelsHidden()
                }
                if !blocker.allowedSites.isEmpty {
                    SettingsRow(title: "Sites you let through", verbatimDetail: blocker.allowedSites.sorted().joined(separator: ", ")) {
                        Button("Clear") { blocker.clearAllowed() }
                            .pill(.secondary, size: .small)
                    }
                }
            }

            PageMemorySettingsGroup()

            SettingsGroup(title: "Clear data", verbatimFooter: cleared) {
                SettingsRow(title: "Browsing history") {
                    Button("Clear") {
                        HistoryStore.shared.clear()
                        PageMemory.shared.forgetAll()
                        cleared = String(localized: "History cleared.")
                    }
                    .pill(.secondary, size: .small)
                }
                SettingsRow(title: "Cookies and website data", detail: "Signs you out of websites.") {
                    Button("Clear") {
                        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                                modifiedSince: .distantPast) {
                            cleared = String(localized: "Cookies and website data cleared.")
                        }
                        // Every space's too.
                        Task { await SpaceStore.shared.clearAllWebsiteData() }
                    }
                    .pill(.secondary, size: .small)
                }
                SettingsRow(title: "Saved tabs and site icons") {
                    Button("Clear") {
                        SessionStore.clear()
                        FaviconStore.shared.clearCache()
                        cleared = String(localized: "Saved tabs and icons cleared.")
                    }
                    .pill(.secondary, size: .small)
                }
            }
        }
    }

    private func bullet(_ icon: MQIcon, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(icon, size: 18)
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - About

private struct AboutSettings: View {
    @State private var revealed = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        ZStack {
            TwinkleField(count: 34, seed: 3).opacity(0.7)
            VStack(spacing: 0) {
                Spacer()
                MaxQMark(size: 64, animated: true)
                    .padding(.bottom, 20)
                FlipText(text: "Max Q", font: .hero(44), size: 44, delay: 0.45)
                    .tracking(-0.6)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 10)
                Text(version)
                    .font(.mono(12, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .reveal(revealed, delay: 0.6)
                    .padding(.bottom, 14)
                Text("A free, open-source browser for macOS that works with Grok.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .reveal(revealed, delay: 0.66)
                if Updater.isConfigured {
                    Button("Check for updates") { Updater.shared.checkForUpdates() }
                        .pill(.secondary, size: .small)
                        .padding(.top, 18)
                        .reveal(revealed, delay: 0.72)
                }
                Spacer()
                Text(Legal.disclaimer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textQuaternary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Apache License 2.0")
                    .font(.mono(11, weight: .regular))
                    .foregroundStyle(Theme.textQuaternary)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 30)
        }
        .onAppear { revealed = true }
    }
}

enum Legal {
    static var disclaimer: String {
        String(localized: """
        Max Q is an independent open-source project. It is not affiliated with, endorsed by, or sponsored by \
        SpaceXAI, xAI, X Corp., SpaceX, Brave or DuckDuckGo. Grok, Grokipedia, Grok Bot, X, Brave and DuckDuckGo are \
        trademarks of their respective owners and are used here only to name the services Max Q works with.
        """)
    }
}
