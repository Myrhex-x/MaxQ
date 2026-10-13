//
//  GrokCostViews.swift
//  Max Q
//
//  The controls for what Grok costs: the effort picker (Fast, Auto, Expert) with a thumb that
//  glides between choices, the menu that asks an answer again at another effort, and the month's
//  spending with its limit and a bar for each day.
//

import SwiftUI

/// Opens Settings on a given page.
@MainActor
@Observable
final class SettingsRouter {
    static let shared = SettingsRouter()
    /// The page Settings shows next time it opens (or now, when it's open).
    var section: SettingsSection = .general
    private init() {}
}

// MARK: - Effort picker

/// Fast, Auto and Expert as one control: a capsule track with a raised thumb that glides to the
/// choice (grok.com's selection spring, 500 / 35).
struct EffortPicker: View {
    @Binding var effort: GrokEffort
    var compact = false
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GrokEffort.allCases) { option in
                EffortSegment(title: option.title, selected: option == effort, compact: compact, thumb: thumb) {
                    withAnimation(Motion.glide) { effort = option }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.hover))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Effort")
    }
}

private struct EffortSegment: View {
    let title: String
    let selected: Bool
    let compact: Bool
    let thumb: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 12.5 : 13, weight: .medium))
                .foregroundStyle(selected || hovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: compact ? 62 : 74, height: compact ? 26 : 28)
                .background {
                    if selected {
                        Capsule()
                            .fill(Theme.raised)
                            .elevation(.raised)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Effort menu

/// grok.com's mode button, for composers: the effort and a chevron that turns up while the menu is
/// open. Each choice says what it does and what an answer usually costs.
struct EffortMenuButton: View {
    var placement: PopoverPlacement = .above(.trailing)
    @State private var settings = AppSettings.shared

    var body: some View {
        MenuButton(placement: placement) { isOpen in
            HStack(spacing: 5) {
                Text(settings.grokEffort.title)
                    .contentTransition(.interpolate)
                MorphChevron(open: isOpen, size: 13)
            }
            .animation(Motion.snappy, value: settings.grokEffort)
        } content: {
            MenuCard(width: 280) {
                MenuSectionTitle("Effort")
                ForEach(GrokEffort.allCases) { effort in
                    MenuRow(verbatim: effort.title, detail: effort.detail,
                            shortcut: GrokAccount.friendlyCost(GrokAccount.shared.typicalAnswerCost(effort, searchingX: false)),
                            checked: AppSettings.shared.grokEffort == effort) {
                        AppSettings.shared.grokEffort = effort
                    }
                }
            }
        }
        .pill(.ghost, size: .mini)
        .tip("How hard Grok works")
    }
}

// MARK: - Ask again

/// The menu behind an answer's effort and cost: ask again at another effort, with or without X,
/// and what the answer on show used.
struct AskAgainMenu: View {
    let effort: GrokEffort
    let searchedX: Bool
    let usage: GrokUsage?
    let model: String?
    let ask: (GrokEffort, Bool) -> Void

    private var account: GrokAccount { GrokAccount.shared }

    var body: some View {
        MenuCard(width: 290) {
            MenuSectionTitle("Ask again")
            ForEach(GrokEffort.allCases) { option in
                MenuRow(verbatim: option.title, detail: option.detail,
                        shortcut: GrokAccount.friendlyCost(account.typicalAnswerCost(option, searchingX: searchedX)),
                        checked: option == effort) {
                    ask(option, searchedX)
                }
            }
            MenuDivider()
            if searchedX {
                MenuRow(icon: .search, title: "Without X",
                        detail: "Web search only",
                        shortcut: GrokAccount.friendlyCost(account.typicalAnswerCost(effort, searchingX: false))) {
                    ask(effort, false)
                }
            } else {
                MenuRow(icon: .search, title: "Search X too",
                        detail: "Billed by the post read",
                        shortcut: "+" + GrokAccount.friendlyCost(GrokToolPrices.typicalXSearch)) {
                    ask(effort, true)
                }
            }
            if let line = UsageLine.text(usage: usage, model: model) {
                MenuDivider()
                Text(line)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
    }
}

/// What an answer used, in a line: "Grok 4.3 · 6,120 tokens read, 2,048 of them cached · 240
/// written · 1 web search · 19 posts read on X".
nonisolated enum UsageLine {
    static func text(usage: GrokUsage?, model: String?) -> String? {
        guard let usage else { return model.map(modelName) }
        var parts: [String] = []
        if let model { parts.append(modelName(model)) }
        let read = usage.inputTokens.formatted()
        parts.append(usage.cachedTokens > 0
                     ? String(localized: "\(read) tokens read, \(usage.cachedTokens.formatted()) of them cached")
                     : String(localized: "\(read) tokens read"))
        parts.append(String(localized: "\(usage.outputTokens.formatted()) written"))
        if usage.reasoningTokens > 0 { parts.append(String(localized: "\(usage.reasoningTokens.formatted()) thinking")) }
        if usage.webSearches > 0 { parts.append(usage.webSearches == 1 ? String(localized: "1 web search") : String(localized: "\(usage.webSearches) web searches")) }
        if usage.xPostsRead > 0 { parts.append(usage.xPostsRead == 1 ? String(localized: "1 post read on X") : String(localized: "\(usage.xPostsRead) posts read on X")) }
        if usage.xProfilesRead > 0 { parts.append(String(localized: "\(usage.xProfilesRead) profiles read on X")) }
        return parts.joined(separator: " · ")
    }

    /// "grok-4.3" → "Grok 4.3".
    static func modelName(_ id: String) -> String {
        let trimmed = id.replacingOccurrences(of: "-latest", with: "")
        guard trimmed.hasPrefix("grok-") else { return trimmed }
        let rest = trimmed.dropFirst(5).replacingOccurrences(of: "-", with: " ")
        return "Grok " + rest
    }
}

// MARK: - Spending

/// The month so far: what's been spent, the limit as a line that fills, and the last 30 days as
/// bars, the way x.ai draws its usage. Hovering a bar names the day.
struct SpendingSummary: View {
    private var account: GrokAccount { GrokAccount.shared }
    @State private var hoveredDay: Int?
    @State private var grown = false

    var body: some View {
        let days = account.recentDays(30)
        let peak = max(days.map(\.usd).max() ?? 0, 0.0001)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(days))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .contentTransition(.opacity)
                    Text(Money.usd(amount(days)))
                        .font(.hero(30))
                        .tracking(-0.6)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                }
                Spacer()
                if let limit = account.monthlyLimitUSD, hoveredDay == nil {
                    Text("of \(Money.usd(limit)) this month")
                        .font(.system(size: 12.5))
                        .foregroundStyle(account.limitReached ? Theme.warning : Theme.textTertiary)
                        .transition(.opacity)
                }
            }
            if let limit = account.monthlyLimitUSD {
                GeometryReader { proxy in
                    let share = min(1, account.monthCostUSD / limit)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hover)
                        Capsule()
                            .fill(account.limitReached ? Theme.warning : Theme.textPrimary)
                            .frame(width: max(4, proxy.size.width * share * (grown ? 1 : 0)))
                    }
                }
                .frame(height: 4)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let height = day.usd > 0 ? max(3, 46 * day.usd / peak) : 2
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(hoveredDay == index ? Theme.textPrimary : (day.usd > 0 ? Theme.textTertiary : Theme.hover))
                        .frame(maxWidth: .infinity)
                        .frame(height: grown ? height : 2)
                        .animation(Motion.spring(0.5).delay(Double(index) * 0.012), value: grown)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            withAnimation(Motion.hover) {
                                if inside { hoveredDay = index } else if hoveredDay == index { hoveredDay = nil }
                            }
                        }
                }
            }
            .frame(height: 46, alignment: .bottom)
            HStack {
                Text(days.first.map { $0.day.formatted(.dateTime.month(.abbreviated).day()) } ?? "")
                Spacer()
                Text("Today")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textQuaternary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.vertical, 12)
        .onAppear { withAnimation(Motion.spring(0.6)) { grown = true } }
    }

    private func headline(_ days: [(day: Date, usd: Double)]) -> String {
        guard let hoveredDay, days.indices.contains(hoveredDay) else { return String(localized: "Spent this month") }
        return days[hoveredDay].day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func amount(_ days: [(day: Date, usd: Double)]) -> Double {
        guard let hoveredDay, days.indices.contains(hoveredDay) else { return account.monthCostUSD }
        return days[hoveredDay].usd
    }
}

/// The month's limits on offer, in dollars (0 is none).
enum SpendingLimits {
    static let options: [(Double, String)] = [(0, String(localized: "No limit"))]
        + [1, 2, 5, 10, 20, 50].map { ($0, String(localized: "\(Money.usd($0, digits: 0)) a month")) }
}
