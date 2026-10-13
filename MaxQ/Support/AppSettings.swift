//
//  AppSettings.swift
//  Max Q
//
//  App-wide preferences, persisted to UserDefaults synchronously on every change (a deferred write
//  can be lost if the app quits right after a toggle). The Grok API key is NOT here: it lives in
//  the Keychain (see GrokKeyStore).
//

import Foundation
import Observation
import SwiftUI

enum GrokipediaMode: String, CaseIterable, Identifiable {
    /// Open the Grokipedia pane beside results automatically for queries that look like a topic.
    case automatic
    /// Show a small Grokipedia bar; the pane opens when clicked.
    case onClick
    case off
    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: String(localized: "Automatically")
        case .onClick: String(localized: "When I click")
        case .off: String(localized: "Off")
        }
    }
}


enum GrokPanelMode: String, CaseIterable, Identifiable {
    /// Native chat through the user's own API key.
    case native
    /// grok.com in a side panel, signed in with the user's own account.
    case web
    var id: String { rawValue }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: String(localized: "Match System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let searchEngine = "searchEngine"
        static let customSearchTemplate = "customSearchTemplate"
        static let searchSuggestions = "searchSuggestions"
        static let grokipediaMode = "grokipediaMode"
        static let grokPanelMode = "grokPanelMode"
        static let grokModel = "grokModel"
        static let botEmail = "botEmail"
        static let botEmailSuggestions = "botEmailSuggestions"
        static let displayName = "displayName"
        static let grokAnswerMode = "grokAnswerMode"
        static let grokAnswersSearchX = "grokAnswersSearchX"
        static let grokEffort = "grokEffort"
        static let grokXSearch = "grokXSearch"
        static let grokMonthlyLimit = "grokMonthlyLimitUSD"
        static let blockTrackers = "blockTrackers"
        static let onboardingDone = "onboardingDone"
        static let appearance = "appearance"
        static let restoreSession = "restoreSession"
        static let homeNews = "homeNews"
        static let homeNewsTopics = "homeNewsTopics"
        static let researchBudget = "researchBudgetUSD"
        static let linkPreviews = "linkPreviews"
        static let globalShortcut = "globalShortcut"
        static let onDeviceSkipsGrok = "onDeviceSkipsGrok"
        static let rememberPages = "rememberPages"
        static let agentBudget = "agentBudgetUSD"
        static let iCloudSync = "iCloudSync"
    }

    var searchEngineID: SearchEngineID {
        didSet { defaults.set(searchEngineID.rawValue, forKey: Key.searchEngine) }
    }
    var customSearchTemplate: String {
        didSet { defaults.set(customSearchTemplate, forKey: Key.customSearchTemplate) }
    }
    var searchSuggestionsEnabled: Bool {
        didSet { defaults.set(searchSuggestionsEnabled, forKey: Key.searchSuggestions) }
    }


    var grokipediaMode: GrokipediaMode {
        didSet { defaults.set(grokipediaMode.rawValue, forKey: Key.grokipediaMode) }
    }
    var grokPanelMode: GrokPanelMode {
        didSet { defaults.set(grokPanelMode.rawValue, forKey: Key.grokPanelMode) }
    }
    /// Empty = pick automatically from the models the key can use.
    var grokModel: String {
        didSet { defaults.set(grokModel, forKey: Key.grokModel) }
    }
    /// The Grok Bot's own inbox address (on mail.grokbot.com), pasted by the user.
    var botEmail: String {
        didSet { defaults.set(botEmail, forKey: Key.botEmail) }
    }
    /// Offer the Bot's address under email fields in forms.
    var botEmailSuggestions: Bool {
        didSet { defaults.set(botEmailSuggestions, forKey: Key.botEmailSuggestions) }
    }
    /// When Grok answers on its own results page (or, without a key, in the grok.com panel).
    var grokAnswerMode: GrokAnswerMode {
        didSet { defaults.set(grokAnswerMode.rawValue, forKey: Key.grokAnswerMode) }
    }
    /// How hard Grok works on an answer (model, reasoning, rounds of search): Fast, Auto, Expert.
    var grokEffort: GrokEffort {
        didSet { defaults.set(grokEffort.rawValue, forKey: Key.grokEffort) }
    }
    /// When Grok's answers may search X, which SpaceXAI bills by the post read.
    var grokXSearch: XSearchPolicy {
        didSet { defaults.set(grokXSearch.rawValue, forKey: Key.grokXSearch) }
    }
    /// Most Max Q may spend with the key in a calendar month, in US dollars. 0 means no limit.
    var grokMonthlyLimitUSD: Double {
        didSet { defaults.set(grokMonthlyLimitUSD, forKey: Key.grokMonthlyLimit) }
    }
    /// What Max Q calls the user (chosen during setup), shown at the foot of the sidebar.
    var displayName: String {
        didSet { defaults.set(displayName, forKey: Key.displayName) }
    }
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboardingDone) }
    }
    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    var restoreSession: Bool {
        didSet { defaults.set(restoreSession, forKey: Key.restoreSession) }
    }
    /// The news under the new-tab page.
    var homeNews: Bool {
        didSet { defaults.set(homeNews, forKey: Key.homeNews) }
    }
    /// The news topics on the new-tab page, in order (nil: all of them, in Max Q's order).
    var homeNewsTopics: [String]? {
        didSet { defaults.set(homeNewsTopics, forKey: Key.homeNewsTopics) }
    }
    /// Keep what pages read in normal windows say, on this Mac, so ⌘K finds them by meaning.
    var rememberPages: Bool {
        didSet {
            defaults.set(rememberPages, forKey: Key.rememberPages)
            if !rememberPages { PageMemory.shared.forgetAll() }
        }
    }
    /// The Mac's own model decides whether a search needs Grok's answer, so simple ones don't cost.
    var onDeviceSkipsGrok: Bool {
        didSet { defaults.set(onDeviceSkipsGrok, forKey: Key.onDeviceSkipsGrok) }
    }
    /// The shortcut that opens the Max Q bar from any app.
    var globalShortcut: GlobalShortcut {
        didSet {
            defaults.set(globalShortcut.rawValue, forKey: Key.globalShortcut)
            QuickAskController.shared.apply(globalShortcut)
        }
    }
    /// Cards for links: resting on one in a reader, or holding ⌥ over one on a page.
    var linkPreviews: Bool {
        didSet { defaults.set(linkPreviews, forKey: Key.linkPreviews) }
    }
    /// The budget research starts with, in US dollars.
    var researchBudgetUSD: Double {
        didSet { defaults.set(researchBudgetUSD, forKey: Key.researchBudget) }
    }
    /// Collections, followed searches and bookmarks sync through the user's iCloud (when this copy
    /// of Max Q has an iCloud container).
    var iCloudSync: Bool {
        didSet { defaults.set(iCloudSync, forKey: Key.iCloudSync) }
    }
    /// What one agent task may spend before it stops and asks, in US dollars.
    var agentBudgetUSD: Double {
        didSet { defaults.set(agentBudgetUSD, forKey: Key.agentBudget) }
    }
    /// Block the trackers on Max Q's list in every tab.
    var blockTrackers: Bool {
        didSet {
            defaults.set(blockTrackers, forKey: Key.blockTrackers)
            TrackerBlocker.shared.apply()
        }
    }

    private init() {
        searchEngineID = SearchEngineID(rawValue: defaults.string(forKey: Key.searchEngine) ?? "") ?? .maxq
        customSearchTemplate = defaults.string(forKey: Key.customSearchTemplate) ?? ""
        searchSuggestionsEnabled = defaults.object(forKey: Key.searchSuggestions) as? Bool ?? true
        grokipediaMode = GrokipediaMode(rawValue: defaults.string(forKey: Key.grokipediaMode) ?? "") ?? .automatic
        grokPanelMode = GrokPanelMode(rawValue: defaults.string(forKey: Key.grokPanelMode) ?? "") ?? .native
        grokModel = defaults.string(forKey: Key.grokModel) ?? ""
        botEmail = defaults.string(forKey: Key.botEmail) ?? ""
        botEmailSuggestions = defaults.object(forKey: Key.botEmailSuggestions) as? Bool ?? true
        displayName = defaults.string(forKey: Key.displayName) ?? ""
        grokAnswerMode = GrokAnswerMode(rawValue: defaults.string(forKey: Key.grokAnswerMode) ?? "") ?? .automatic
        grokEffort = GrokEffort(rawValue: defaults.string(forKey: Key.grokEffort) ?? "") ?? .auto
        // "Search X too", before there was a choice: on meant for news (what Grok was told to do).
        let searchedX = defaults.object(forKey: Key.grokAnswersSearchX) as? Bool ?? true
        grokXSearch = XSearchPolicy(rawValue: defaults.string(forKey: Key.grokXSearch) ?? "") ?? (searchedX ? .news : .off)
        grokMonthlyLimitUSD = max(0, defaults.double(forKey: Key.grokMonthlyLimit))
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboardingDone)
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        restoreSession = defaults.object(forKey: Key.restoreSession) as? Bool ?? true
        blockTrackers = defaults.object(forKey: Key.blockTrackers) as? Bool ?? true
        homeNews = defaults.object(forKey: Key.homeNews) as? Bool ?? true
        homeNewsTopics = defaults.stringArray(forKey: Key.homeNewsTopics)
        linkPreviews = defaults.object(forKey: Key.linkPreviews) as? Bool ?? true
        onDeviceSkipsGrok = defaults.bool(forKey: Key.onDeviceSkipsGrok)
        rememberPages = defaults.bool(forKey: Key.rememberPages)
        globalShortcut = GlobalShortcut(rawValue: defaults.string(forKey: Key.globalShortcut) ?? "") ?? .commandShiftSpace
        let budget = defaults.double(forKey: Key.researchBudget)
        researchBudgetUSD = budget > 0 ? budget : 0.50
        let agentBudget = defaults.double(forKey: Key.agentBudget)
        agentBudgetUSD = agentBudget > 0 ? agentBudget : 0.25
        iCloudSync = defaults.bool(forKey: Key.iCloudSync)
    }

    /// The engine in use. A broken custom template falls back to DuckDuckGo rather than failing.
    var searchEngine: SearchEngine {
        if searchEngineID == .custom, let custom = SearchEngine.custom(template: customSearchTemplate) {
            return custom
        }
        return SearchEngine.builtIn(searchEngineID) ?? SearchEngine.builtIn(.duckduckgo)!
    }

    var botEmailIsValid: Bool { Self.isPlausibleEmail(botEmail) }

    /// The name, tidied, or nil when the user hasn't given one.
    var name: String? {
        let trimmed = Self.cleanName(displayName)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trims and caps a name typed during setup or in Settings.
    nonisolated static func cleanName(_ raw: String) -> String {
        let single = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(single.prefix(32)).trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func isPlausibleEmail(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces)
        let parts = v.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !v.contains(" "), v.count <= 254 else { return false }
        return !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }
}
