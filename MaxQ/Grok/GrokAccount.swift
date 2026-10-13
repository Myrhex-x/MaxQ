//
//  GrokAccount.swift
//  Max Q
//
//  App-wide state for the user's SpaceXAI connection: whether a key is set, which models it can
//  use, which one Max Q should use, and how much Grok has cost on this Mac.
//

import Foundation
import Observation

@MainActor
@Observable
final class GrokAccount {
    static let shared = GrokAccount()

    enum KeyStatus: Equatable {
        case none
        case unchecked
        case checking
        case valid
        case invalid(String)
    }

    private(set) var hasKey = false
    private(set) var keyHint = ""
    private(set) var models: [GrokModelInfo] = []
    var availableModels: [String] { models.map(\.id) }
    private(set) var status: KeyStatus = .none
    private(set) var lifetimeCostUSD: Double
    /// What Max Q spent with the key each day ("2026-10-10": dollars), the last 400 days.
    private(set) var dailyCostUSD: [String: Double]
    /// Recent answer costs on the results page, per kind of answer ("auto", "auto+x"), newest last.
    @ObservationIgnored private var recentAnswerCosts: [String: [Double]]
    /// What each feature spent, by month ("2026-10": ["answer": 1.2, "check": 0.3]).
    private(set) var purposeCostUSD: [String: [String: Double]]

    @ObservationIgnored private var cachedKey: String?
    @ObservationIgnored private let costKey = "grokLifetimeCostUSD"
    @ObservationIgnored private let dailyKey = "grokDailyCostUSD"
    @ObservationIgnored private let recentKey = "grokRecentAnswerCosts"
    @ObservationIgnored private let purposeKey = "grokPurposeCostUSD"

    /// Default models, best first. Grok 4.3 is quick and inexpensive, which suits answers in a
    /// side panel; Grok 4.7 (more capable, slower, always reasons) is one click away in Settings.
    /// The live model list decides what's actually used, so an outdated entry is just skipped.
    nonisolated static let preferredModels = [
        "grok-4.3", "grok-4.20-0309-non-reasoning", "grok-4.7", "grok-4.6", "grok-4.5",
    ]

    /// Quick models for bulk work (page translation).
    nonisolated static let preferredFastModels = [
        "grok-4.3", "grok-4.20-0309-non-reasoning",
    ]

    /// Used before the model list has been fetched.
    nonisolated static let fallbackModel = "grok-4.3"

    private init() {
        lifetimeCostUSD = UserDefaults.standard.double(forKey: costKey)
        dailyCostUSD = UserDefaults.standard.dictionary(forKey: dailyKey) as? [String: Double] ?? [:]
        recentAnswerCosts = UserDefaults.standard.dictionary(forKey: recentKey) as? [String: [Double]] ?? [:]
        purposeCostUSD = UserDefaults.standard.dictionary(forKey: purposeKey) as? [String: [String: Double]] ?? [:]
        #if DEBUG
        if GrokClient.simulationEnabled {
            // A pretend key for checking the screens (see GrokSimulator): nothing is sent anywhere.
            cachedKey = GrokClient.simulatedKey
            hasKey = true
            keyHint = "Simulated"
            status = .valid
            models = ["grok-4.3", "grok-4.7"].map(GrokModelInfo.init(id:))
            return
        }
        #endif
        if let key = GrokKeyStore.read() {
            cachedKey = key
            hasKey = true
            keyHint = Self.hint(for: key)
            status = .unchecked
        }
        if let data = UserDefaults.standard.data(forKey: "grokModelsCache"),
           let cached = try? JSONDecoder().decode([GrokModelInfo].self, from: data) {
            models = cached
        }
    }

    nonisolated static func hint(for key: String) -> String {
        guard key.count > 8 else { return String(localized: "Saved") }
        return "\(key.prefix(4))…\(key.suffix(4))"
    }

    var client: GrokClient? {
        guard let key = cachedKey else { return nil }
        return GrokClient(apiKey: key)
    }

    /// The model Max Q uses for answers at the chosen effort.
    var model: String { model(for: AppSettings.shared.grokEffort) }

    /// The model for `effort`: the user's own pick in Settings when there is one, else the effort's
    /// first model the key can use.
    func model(for effort: GrokEffort) -> String {
        let chosen = AppSettings.shared.grokModel
        if !chosen.isEmpty, availableModels.isEmpty || availableModels.contains(chosen) { return chosen }
        return Self.pick(from: effort.preferredModels, available: availableModels)
            ?? Self.pick(from: Self.preferredModels, available: availableModels)
            ?? Self.fallbackModel
    }

    /// The reasoning effort to send with `model` at `effort`, if the model takes one.
    func reasoningEffort(_ effort: GrokEffort, model: String) -> String? {
        effort.reasoningEffort(for: model, supported: info(for: model)?.reasoningEfforts)
    }

    var fastModel: String { model(for: .fast) }

    /// Chat-capable models for the Settings picker (image, video and voice models filtered out).
    var chatModels: [String] {
        availableModels.filter { id in
            let lower = id.lowercased()
            return lower.hasPrefix("grok") && !lower.contains("image") && !lower.contains("imagine")
                && !lower.contains("video") && !lower.contains("voice") && !lower.contains("vision") && !lower.contains("embed")
        }
        .sorted()
    }

    nonisolated static func pick(from preferred: [String], available: [String]) -> String? {
        guard !available.isEmpty else { return nil }
        if let match = preferred.first(where: available.contains) { return match }
        return available.first { $0.lowercased().hasPrefix("grok") && !$0.contains("image") && !$0.contains("imagine") }
    }

    // MARK: - Key management

    /// Checks the key against SpaceXAI before saving it. Returns nil on success, or why it failed.
    func setKey(_ rawKey: String) async -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return String(localized: "Paste your API key first.") }
        status = .checking
        do {
            let models = try await GrokClient(apiKey: key).listModels()
            guard GrokKeyStore.save(key) else {
                status = .invalid(String(localized: "Couldn't save the key to your Keychain."))
                return String(localized: "Couldn't save the key to your Keychain.")
            }
            cachedKey = key
            hasKey = true
            keyHint = Self.hint(for: key)
            setModels(models)
            status = .valid
            return nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // A rejected new key leaves a previously saved key in place.
            status = hasKey ? .unchecked : .invalid(message)
            return message
        }
    }

    func removeKey() {
        GrokKeyStore.delete()
        cachedKey = nil
        hasKey = false
        keyHint = ""
        status = .none
    }

    /// Refreshes the model list (and confirms the key still works) in the background.
    func refresh() async {
        #if DEBUG
        if GrokClient.simulationEnabled { return }
        #endif
        guard let client else { return }
        status = .checking
        do {
            setModels(try await client.listModels())
            status = .valid
        } catch let error as GrokError where error == .invalidKey {
            status = .invalid(error.errorDescription ?? String(localized: "Invalid key"))
        } catch {
            // Offline or a transient error: keep the key, try again later.
            status = .unchecked
        }
    }

    private func setModels(_ list: [GrokModelInfo]) {
        models = list
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "grokModelsCache")
        }
    }

    func info(for model: String) -> GrokModelInfo? {
        models.first { $0.id == model || $0.aliases.contains(model) }
    }

    func recordCost(_ usd: Double?, purpose: GrokPurpose = .answer) {
        guard let usd, usd > 0 else { return }
        lifetimeCostUSD += usd
        UserDefaults.standard.set(lifetimeCostUSD, forKey: costKey)
        let today = Self.dayKey(Date())
        let month = String(today.prefix(7))
        purposeCostUSD[month, default: [:]][purpose.rawValue, default: 0] += usd
        // Keep about a year of months.
        if purposeCostUSD.count > 13 {
            for key in purposeCostUSD.keys.sorted().prefix(purposeCostUSD.count - 13) { purposeCostUSD[key] = nil }
        }
        UserDefaults.standard.set(purposeCostUSD, forKey: purposeKey)
        dailyCostUSD[today, default: 0] += usd
        // Keep about a year of days.
        if dailyCostUSD.count > 400 {
            for key in dailyCostUSD.keys.sorted().prefix(dailyCostUSD.count - 400) { dailyCostUSD[key] = nil }
        }
        UserDefaults.standard.set(dailyCostUSD, forKey: dailyKey)
    }

    func resetLifetimeCost() {
        lifetimeCostUSD = 0
        dailyCostUSD = [:]
        recentAnswerCosts = [:]
        purposeCostUSD = [:]
        UserDefaults.standard.removeObject(forKey: purposeKey)
        UserDefaults.standard.set(0.0, forKey: costKey)
        UserDefaults.standard.removeObject(forKey: dailyKey)
        UserDefaults.standard.removeObject(forKey: recentKey)
    }

    // MARK: - Spending

    nonisolated static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// What Max Q has spent with the key this calendar month.
    var monthCostUSD: Double {
        let month = String(Self.dayKey(Date()).prefix(7))
        return dailyCostUSD.filter { $0.key.hasPrefix(month) }.values.reduce(0, +)
    }

    /// This month's spending per feature, largest first.
    var monthByPurpose: [(purpose: GrokPurpose, usd: Double)] {
        let month = String(Self.dayKey(Date()).prefix(7))
        return (purposeCostUSD[month] ?? [:]).compactMap { key, usd in GrokPurpose(rawValue: key).map { ($0, usd) } }
            .filter { $0.usd > 0 }
            .sorted { $0.usd > $1.usd }
    }

    /// The monthly limit, if one is set.
    var monthlyLimitUSD: Double? {
        let limit = AppSettings.shared.grokMonthlyLimitUSD
        return limit > 0 ? limit : nil
    }

    /// This month's spending has reached the limit: Max Q asks before spending more.
    var limitReached: Bool {
        guard let limit = monthlyLimitUSD else { return false }
        return monthCostUSD >= limit
    }

    /// Spending per day for the last `days` days, oldest first.
    func recentDays(_ days: Int) -> [(day: Date, usd: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, dailyCostUSD[Self.dayKey(day)] ?? 0)
        }
    }

    /// Remembers what an answer on the results page cost, so estimates follow this Mac's real ones.
    func recordAnswer(effort: GrokEffort, searchedX: Bool, cost: Double) {
        let key = effort.rawValue + (searchedX ? "+x" : "")
        var costs = recentAnswerCosts[key, default: []]
        costs.append(cost)
        recentAnswerCosts[key] = Array(costs.suffix(20))
        UserDefaults.standard.set(recentAnswerCosts, forKey: recentKey)
    }

    /// What an answer usually costs at `effort`: the median of this Mac's recent ones once there are
    /// a few, else SpaceXAI's prices applied to a typical answer.
    func typicalAnswerCost(_ effort: GrokEffort, searchingX: Bool) -> Double {
        let key = effort.rawValue + (searchingX ? "+x" : "")
        if let costs = recentAnswerCosts[key], costs.count >= 3 {
            return costs.sorted()[costs.count / 2]
        }
        return effort.typicalCostUSD + (searchingX ? GrokToolPrices.typicalXSearch : 0)
    }

    nonisolated static func formatCost(_ usd: Double?) -> String {
        guard let usd else { return "" }
        if usd == 0 { return Money.usd(0) }
        if usd < 0.01 { return Money.usd(usd, digits: 4) }
        if usd < 1 { return Money.usd(usd, digits: 3) }
        return Money.usd(usd)
    }
}
