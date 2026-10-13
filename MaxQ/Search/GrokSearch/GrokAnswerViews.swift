//
//  GrokAnswerViews.swift
//  Max Q
//
//  Grok's side of the results page: the answer the way grok.com sets one, the follow-up questions
//  asked under it (a search turning into a conversation without leaving the page), the questions
//  Grok suggests asking next, and the composer for the next one.
//

import AppKit
import SwiftUI

// MARK: Grok's answer

struct GrokAnswerSection: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        Group {
            switch search.answer {
            case .needsKey where search.quick != nil, .waiting where search.quick != nil:
                // Max Q answered this one itself (a sum, a conversion, the time, the weather).
                EmptyView()
            case .needsKey:
                KeylessGrokPrompt(browser: browser, query: search.query)
            case .waiting:
                GrokComposerPrompt(query: search.query, cost: waitingCost) { search.ask() }
            case .overLimit:
                OverLimitNotice(search: search)
            case .streaming, .done, .failed:
                GrokConversation(browser: browser, search: search)
            }
        }
        .transition(.blurFade(radius: 4))
        .animation(Motion.spring(0.4), value: search.answer)
    }

    /// The effort and what an answer usually costs at it, beside the send button.
    private var waitingCost: String {
        let effort = AppSettings.shared.grokEffort
        let x = AppSettings.shared.grokXSearch.allows(search.query)
        return "\(effort.title) · " + GrokAccount.friendlyCost(GrokAccount.shared.typicalAnswerCost(effort, searchingX: x), approximate: true)
    }
}

/// This month's limit is reached: one sentence on where things stand and one way forward, the
/// way a Family tray holds a single decision.
private struct OverLimitNotice: View {
    let search: GrokSearch
    @Environment(\.openSettings) private var openSettings
    private var account: GrokAccount { GrokAccount.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This month's limit is reached")
                    .font(.heading(17))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    search.ask(pastLimit: true)
                } label: {
                    Text(String(localized: "Answer this once · ") + GrokAccount.friendlyCost(
                        account.typicalAnswerCost(AppSettings.shared.grokEffort, searchingX: AppSettings.shared.grokXSearch.allows(search.query)),
                        approximate: true))
                }
                .pill(.primary, size: .small)
                Button("Change the limit") {
                    SettingsRouter.shared.section = .grok
                    openSettings()
                }
                .pill(.ghost, size: .small)
            }
        }
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var detail: String {
        let spent = Money.usd(account.monthCostUSD)
        let limit = Money.usd(account.monthlyLimitUSD ?? 0)
        let month = Date().formatted(.dateTime.month(.wide))
        return String(localized: "Max Q has spent \(spent) of the \(limit) you set for \(month). Grok's answers wait for you until the month ends.")
    }
}

// MARK: The conversation

/// Grok's answer, then each follow-up asked under it, the questions Grok suggests asking next, and
/// the field for the next one: a search turning into a conversation on the same page.
private struct GrokConversation: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TurnView(browser: browser, search: search, turn: mainTurn, isLatest: search.followUps.isEmpty,
                     retry: { search.ask(fresh: true) },
                     askAgain: { effort, withX in search.ask(effort: effort, searchX: withX, fresh: true) })

            ForEach(search.followUps) { turn in
                let isLatest = turn.id == search.followUps.last?.id
                TurnView(browser: browser, search: search, turn: display(turn), isLatest: isLatest,
                         retry: { search.askAgain(turn, effort: turn.effort, searchX: turn.searchedX) },
                         askAgain: isLatest ? { effort, withX in search.askAgain(turn, effort: effort, searchX: withX) } : nil)
                    .id(turn.id)
                    .padding(.top, 30)
                    // The suggestions make way first, then the question rises into their place.
                    .transition(.asymmetric(
                        insertion: AnyTransition.modifier(active: TurnEntrance(shown: false), identity: TurnEntrance(shown: true))
                            .animation(Motion.spring(0.45).delay(0.08)),
                        removal: .opacity))
            }

            if search.conversationIsIdle, !search.suggestions.isEmpty {
                SuggestedQuestions(questions: search.suggestions) { search.followUp($0) }
                    .padding(.top, 22)
                    .id(search.suggestions)
                    .transition(.asymmetric(insertion: .opacity, removal: AnyTransition.opacity.animation(.linear(duration: 0.08))))
            }

            if canFollowUp {
                FollowUpComposer(search: search)
                    .padding(.top, search.suggestions.isEmpty || !search.conversationIsIdle ? 22 : 16)
                    .transition(.blurFade(radius: 3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 26)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .animation(Motion.spring(0.45), value: search.followUps.count)
        .animation(Motion.outQuint(0.35), value: search.suggestions)
        .animation(Motion.outQuint(0.35), value: canFollowUp)
    }

    /// Follow-ups need the key and an answer to follow.
    private var canFollowUp: Bool {
        GrokAccount.shared.hasKey && (search.answer == .done || !search.followUps.isEmpty)
    }

    private var mainTurn: TurnDisplay {
        TurnDisplay(question: nil, streaming: search.answer == .streaming, done: search.answer == .done,
                    failure: { if case .failed(let message) = search.answer { message } else { nil } }(),
                    text: search.answerText, status: search.answerStatus, citations: search.citations,
                    steps: search.steps, duration: search.answerDuration, savedAt: search.answerSavedAt,
                    effort: search.answerEffort, searchedX: search.answerSearchedX, cost: search.answerCost,
                    usage: search.answerUsage, model: search.answerModel)
    }

    private func display(_ turn: AnswerTurn) -> TurnDisplay {
        TurnDisplay(question: turn.question, streaming: turn.phase == .streaming, done: turn.phase == .done,
                    failure: { if case .failed(let message) = turn.phase { message } else { nil } }(),
                    text: turn.text, status: turn.status, citations: turn.citations, steps: turn.steps,
                    duration: turn.duration, savedAt: nil, effort: turn.effort, searchedX: turn.searchedX,
                    cost: turn.cost, usage: turn.usage, model: turn.model)
    }
}

/// A follow-up arriving: it rises a little into place while it fades in.
private struct TurnEntrance: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
    }
}

/// What one answer on the page shows, whether it's the answer to the search or to a follow-up.
struct TurnDisplay {
    /// The follow-up question, set above its answer (the search's own answer has none).
    let question: String?
    let streaming: Bool
    let done: Bool
    let failure: String?
    let text: String
    let status: String?
    let citations: [GrokCitation]
    let steps: [String]
    let duration: TimeInterval?
    /// Shown again for free, from an answer given within the hour.
    let savedAt: Date?
    let effort: GrokEffort
    let searchedX: Bool
    let cost: Double?
    let usage: GrokUsage?
    let model: String?

    /// grok.com's line once the answer is in: "Worked for 6s".
    var workedFor: String {
        if let savedAt {
            let minutes = Int(Date().timeIntervalSince(savedAt) / 60)
            return minutes < 1 ? String(localized: "Answered a moment ago") : String(localized: "Answered \(minutes) min ago")
        }
        guard let duration else { return String(localized: "Answered") }
        return String(localized: "Worked for \(max(1, Int(duration.rounded())))s")
    }

    /// "Auto · 2¢", or "Auto · free" for an answer shown again.
    var costLabel: String {
        if savedAt != nil { return String(localized: "\(effort.title) · free") }
        guard let cost else { return effort.title }
        return effort.title + " · " + GrokAccount.friendlyCost(cost)
    }
}

/// One answer the way grok.com sets it: no avatar and no card, a quiet status line above
/// ("Searching X for “…”" shimmering while Grok works, then "Worked for 6s", which opens the
/// searches it ran), the text with each source's name in a chip, the sources pill, Copy, and the
/// effort and cost, which ask it again at another effort. A follow-up has its question above.
private struct TurnView: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let turn: TurnDisplay
    /// The newest answer on the page: only it offers "Follow up".
    let isLatest: Bool
    let retry: () -> Void
    /// Nil leaves the effort and cost as a plain label (an earlier follow-up).
    let askAgain: ((GrokEffort, Bool) -> Void)?

    @State private var copied = false
    @State private var showSources = false

    /// Posts on X among the citations say whose they are, from their address.
    private var handles: [String: String] {
        var names: [String: String] = [:]
        for citation in turn.citations {
            if let handle = XLinks.handle(ofPost: citation.url) {
                names[citation.url.absoluteString] = "@" + handle
            }
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let question = turn.question {
                Text(question)
                    .font(.heading(20))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.bottom, 10)
            }

            AnswerStatusLine(turn: turn)

            Group {
                if let failure = turn.failure, turn.text.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(failure)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Try again", action: retry)
                            .pill(.secondary, size: .small)
                    }
                    .transition(.blurFade())
                } else if turn.text.isEmpty {
                    AnswerSkeleton()
                        .transition(.opacity)
                } else {
                    MarkdownText(text: turn.text, fontSize: 15, streaming: turn.streaming,
                                 lineSpacing: 4.5, blockSpacing: 14, handles: handles) { url in
                        openFromResults(url, browser: browser)
                    }
                    .transition(.opacity)
                    .contextMenu {
                        Button("Copy Answer", action: copy)
                        if turn.question == nil {
                            Button("Continue in the Grok Panel") {
                                browser.continueInChat(question: search.query, answer: search.answerText,
                                                       citations: search.citations, model: search.answerModel)
                            }
                        }
                    }
                }
            }
            .padding(.top, 10)

            if !turn.citations.isEmpty {
                SourcesPill(citations: turn.citations, expanded: showSources) {
                    withAnimation(Motion.smooth) { showSources.toggle() }
                }
                .padding(.top, 18)
                .transition(.blurFade())
            }
            if showSources {
                SourcesList(search: search, citations: turn.citations) { openFromResults($0, browser: browser) }
                    .padding(.top, 10)
                    .transition(.asymmetric(insertion: .blurFade(radius: 3).combined(with: .offset(y: -6)), removal: .opacity))
            }
            if turn.done {
                actions
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.expo(0.35), value: turn.text.isEmpty)
        .animation(Motion.expo(0.35), value: turn.citations.isEmpty)
        .animation(Motion.outQuint(0.4), value: turn.done)
    }

    /// grok.com's 32-point Copy, Follow up, and the effort and cost.
    private var actions: some View {
        HStack(spacing: 4) {
            Button(action: copy) {
                ZStack {
                    if copied { Icon(.check, size: 16).transition(.glyphSwap) } else { Icon(.copy, size: 16).transition(.glyphSwap) }
                }
                .animation(Motion.spring(0.2), value: copied)
            }
            .iconButton(size: 32)
            .tip(copied ? "Copied" : "Copy answer")
            .accessibilityLabel("Copy Answer")

            Button {
                browser.shareAnswer = ShareAnswerDraft(question: turn.question ?? search.query, answer: turn.text,
                                                       citations: turn.citations, date: Date())
            } label: { Icon(.share, size: 16) }
            .iconButton(size: 32)
            .tip("Share as a picture")
            .accessibilityLabel("Share as a Picture")

            if isLatest {
                Button {
                    search.focusComposer()
                } label: {
                    HStack(spacing: 6) {
                        Icon(.bubble, size: 15)
                        Text("Follow up")
                    }
                }
                .pill(.ghost, size: .mini)
                .tip("Ask a follow-up question here")
                Button {
                    browser.startResearch(turn.question ?? search.query)
                } label: {
                    HStack(spacing: 6) {
                        Icon(.stack, size: 15)
                        Text("Research")
                    }
                }
                .pill(.ghost, size: .mini)
                .tip("Go deeper: Grok researches in steps and writes a report, within a budget")
            }

            Spacer(minLength: 8)

            if let askAgain {
                MenuButton(placement: .below(.trailing)) { isOpen in
                    HStack(spacing: 5) {
                        Text(turn.costLabel)
                            .contentTransition(.numericText())
                        MorphChevron(open: isOpen, size: 13)
                    }
                } content: {
                    AskAgainMenu(effort: turn.effort, searchedX: turn.searchedX, usage: turn.usage, model: turn.model) { effort, withX in
                        askAgain(effort, withX)
                    }
                }
                .pill(.ghost, size: .mini)
                .tip("Ask again at another effort")
            } else {
                Text(turn.costLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 11)
            }
        }
        .padding(.leading, -6)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(turn.text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }
}

/// grok.com's line above an answer: what Grok is doing, shimmering, while it works; afterwards
/// "Worked for 6s" with a chevron that turns down to show the searches it ran.
private struct AnswerStatusLine: View {
    let turn: TurnDisplay
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                if turn.streaming {
                    ShimmerText(text: GrokStatusText.display(turn.status ?? (turn.text.isEmpty ? "Thinking" : "Writing")),
                                font: .system(size: 14), base: Theme.textSecondary.opacity(0.6))
                        .id(turn.status ?? "")
                        .transition(.statusSwap)
                } else if turn.done {
                    Button {
                        withAnimation(Motion.smooth) { open.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(turn.workedFor)
                            Icon(.chevronDown, size: 14)
                                .rotationEffect(.degrees(open ? 0 : -90))
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(turn.steps.isEmpty)
                    .transition(.statusSwap)
                } else {
                    Text("Grok")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 24)
            .animation(Motion.outQuint(0.15), value: turn.status)
            .animation(Motion.outQuint(0.15), value: turn.streaming)

            if open, turn.done, !turn.steps.isEmpty {
                StepsList(steps: turn.steps)
                    .transition(.opacity.animation(Motion.expo(0.12)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Grok")
    }
}

/// The questions Grok suggests asking next: each a row that asks it here, rising into place one
/// after another.
private struct SuggestedQuestions: View {
    let questions: [String]
    let ask: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ask next")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 6)
            ForEach(Array(questions.enumerated()), id: \.element) { index, question in
                SuggestedQuestionRow(question: question, order: index) { ask(question) }
            }
        }
    }
}

private struct SuggestedQuestionRow: View {
    let question: String
    let order: Int
    let action: () -> Void
    @State private var hovering = false
    @State private var shown = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(.cornerDownRight, size: 16)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
                Text(question)
                    .font(.system(size: 15))
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Icon(.arrowRight, size: 14)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textQuaternary)
                    .offset(x: hovering ? 2 : 0)
            }
            .padding(.vertical, 11)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.standard(0.17), value: hovering)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 6)
        .onAppear {
            withAnimation(Motion.spring(0.4).delay(Double(order) * 0.06)) { shown = true }
        }
        .accessibilityLabel("Ask: \(question)")
    }
}

/// grok.com's composer, under the conversation: the next question, the effort it's asked at, and
/// Grok's blue send button, which turns into a stop button while Grok answers.
private struct FollowUpComposer: View {
    let search: GrokSearch
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var hovering = false

    private var answering: Bool { !search.conversationIsIdle }
    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !answering }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a follow-up", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(send)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
            EffortMenuButton(placement: .above(.trailing))
                .padding(.bottom, 4)
            ZStack {
                if answering {
                    Button { search.stopFollowUp() } label: { Icon(.stop, size: 16) }
                        .stopButton(size: 34)
                        .tip("Stop")
                        .accessibilityLabel("Stop Answer")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Button(action: send) { Icon(.arrowUp, size: 18, weight: 2.2) }
                        .sendButton(size: 34)
                        .disabled(!canSend)
                        .tip("Ask", shortcut: "↩")
                        .accessibilityLabel("Ask")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(Motion.pop, value: answering)
            .padding(.bottom, 1)
        }
        .padding(.leading, 20)
        .padding(.trailing, 9)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.input))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(focused ? Theme.border : (hovering ? Theme.hairline : Theme.composerBorder), lineWidth: 1))
        .elevation(.composer)
        .onHover { hovering = $0 }
        .animation(Motion.standard(0.18), value: focused)
        .onChange(of: search.composerFocusRequest) { _, _ in focused = true }
    }

    private func send() {
        guard canSend else { return }
        let question = text
        text = ""
        search.followUp(question)
    }
}

/// The searches Grok ran, as grok.com lists its steps: an icon on a thread, the verb, and what it
/// looked for in mono.
private struct StepsList: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let (verb, detail) = Self.split(step)
                HStack(spacing: 10) {
                    Icon(.search, size: 14)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 16, height: 32)
                        .overlay(alignment: .top) {
                            if index > 0 { thread.offset(y: -6) }
                        }
                    Text(GrokStatusText.verb(verb))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    if let detail {
                        Text(detail)
                            .font(.mono(13, weight: .regular))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(height: 32)
            }
        }
    }

    private var thread: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 10)
    }

    /// "Searched X for “starship”" → ("Searched X", "starship").
    static func split(_ step: String) -> (String, String?) {
        guard let range = step.range(of: " for ") else { return (step, nil) }
        let detail = step[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "“”\" "))
        return (String(step[..<range.lowerBound]), detail.isEmpty ? nil : detail)
    }
}

/// While Grok hasn't written anything yet: three quiet lines breathing.
private struct AnswerSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SkeletonBar(width: 0.94, delay: 0)
            SkeletonBar(width: 0.82, delay: 0.12)
            SkeletonBar(width: 0.58, delay: 0.24)
        }
        .padding(.vertical, 6)
    }
}

/// A rounded bar that slowly breathes, for content on its way.
struct SkeletonBar: View {
    /// Fraction of the available width.
    var width: CGFloat
    var height: CGFloat = 10
    var delay: Double = 0
    @State private var bright = false

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(Theme.selected)
                .frame(width: proxy.size.width * width)
                .opacity(bright ? 1 : 0.45)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(delay)) { bright = true }
        }
    }
}

/// grok.com's composer as a prompt: the search already typed in, and Grok's blue send button.
private struct GrokComposerPrompt: View {
    let query: String
    /// The effort and what an answer costs at it ("Auto · about 2¢"), beside the send button.
    var cost: String? = nil
    /// Grok is answering elsewhere (the side panel): the line says so and the button shows it.
    var answering = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if answering {
                        Text("Grok is answering beside your results")
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Text("Ask Grok about ").foregroundStyle(Theme.textSecondary)
                            + Text(query).foregroundStyle(Theme.textPrimary)
                    }
                }
                .font(.system(size: 15))
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 8)
                if let cost, !answering {
                    Text(cost)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if answering {
                    LiveDot(color: Theme.accent, size: 6)
                        .transition(.scale.combined(with: .opacity))
                }
                Icon(answering ? .arrowRight : .arrowUp, size: 18, weight: 2.2)
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.accent))
                    .scaleEffect(hovering ? 1.05 : 1)
            }
            .padding(.leading, 20)
            .padding(.trailing, 9)
            .frame(height: 52)
            .background(Capsule().fill(Theme.input))
            .overlay(Capsule().strokeBorder(hovering ? Theme.border : Theme.composerBorder, lineWidth: 1))
            .elevation(.composer)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.4), value: hovering)
        .animation(Motion.smooth, value: answering)
        .accessibilityLabel(answering ? "Show Grok's answer" : "Ask Grok about \(query)")
    }
}

/// No API key: grok.com answers instead, in the side panel, with the user's own Grok account.
private struct KeylessGrokPrompt: View {
    @Bindable var browser: BrowserModel
    let query: String
    private var web: GrokWebAccount { GrokWebAccount.shared }

    private var signedIn: Bool { web.isSignedIn && !browser.isPrivate }

    private var answeringBeside: Bool {
        signedIn && AppSettings.shared.grokAnswerMode == .automatic && browser.grokPanelVisible && browser.grokPanelMode == .web
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GrokComposerPrompt(query: query, answering: answeringBeside) {
                if signedIn || browser.isPrivate {
                    browser.askGrokOnWeb(query)
                } else {
                    browser.grokPanelVisible = true
                    browser.grokPanelMode = .web
                    browser.grokWebPanel.goToSignIn()
                }
            }
            HStack(spacing: 6) {
                Text(caption)
                    .foregroundStyle(Theme.textTertiary)
                Text("·")
                    .foregroundStyle(Theme.textQuaternary)
                Button("Add an API key") { browser.requestGrokKey() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .fontWeight(.medium)
                    .tip("Answers right here, with web and X search")
            }
            .font(.system(size: 12.5))
            .lineLimit(1)
            .padding(.leading, 20)
        }
        .padding(.bottom, 6)
    }

    private var caption: String {
        if browser.isPrivate { return String(localized: "In private windows, Grok answers only when you ask.") }
        if answeringBeside { return String(localized: "In the side panel, with your grok.com account.") }
        if signedIn { return String(localized: "Grok answers in the side panel, with your grok.com account.") }
        return String(localized: "Free with a grok.com account, in the side panel.")
    }
}

/// grok.com's sources pill: up to three site icons in circles, each later one cut away where it
/// tucks under the one before, and the count.
private struct SourcesPill: View {
    let citations: [GrokCitation]
    let expanded: Bool
    let action: () -> Void
    @State private var hovering = false

    private var hosts: [String] {
        var seen = Set<String>()
        return citations.compactMap { citation in
            guard let host = citation.url.host.map(FaviconStore.key(for:)), seen.insert(host).inserted else { return nil }
            return host
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                HStack(spacing: -12) {
                    ForEach(Array(hosts.prefix(3).enumerated()), id: \.element) { index, host in
                        ResultIcon(host: host, size: 16)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white))
                            .clipShape(Circle())
                            .mask {
                                if index > 0 {
                                    CrescentCut().fill(style: FillStyle(eoFill: true))
                                } else {
                                    Rectangle()
                                }
                            }
                            // Each later circle lies over the one before, with a bite out of it.
                            .zIndex(Double(index))
                    }
                }
                Text(citations.count == 1 ? "1 source" : "\(citations.count) sources")
                    .font(.system(size: 14))
                    .foregroundStyle(hovering || expanded ? Theme.textPrimary : Theme.textSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.leading, 4)
            .padding(.trailing, 9)
            .frame(height: 31)
            .background(Capsule().fill(hovering || expanded ? Theme.hover : Theme.chip))
            .overlay(Capsule().strokeBorder(Theme.chipBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.smooth, value: citations.count)
        .accessibilityLabel(citations.count == 1 ? "1 source" : "\(citations.count) sources")
    }
}

/// A circle's crescent cut: the 20-point icon circle minus a 12-point circle centered 3 points
/// past its left edge, as grok.com masks its stacked favicons.
private struct CrescentCut: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: -3 - 12, y: rect.midY - 12, width: 24, height: 24))
        return path
    }
}

/// The sources Grok read, as grok.com's sources panel lists them: the page's title, a few words
/// from it, and the site with its icon. Titles come from the results on this page when the same
/// page is among them.
private struct SourcesList: View {
    let search: GrokSearch
    let citations: [GrokCitation]
    let open: (URL) -> Void
    @State private var showAll = false

    var body: some View {
        let shown = showAll ? citations : Array(citations.prefix(6))
        VStack(alignment: .leading, spacing: 2) {
            ForEach(shown) { citation in
                SourceRow(entry: entry(for: citation)) { open(citation.url) }
            }
            if citations.count > 6 {
                Button(showAll ? "Fewer sources" : "All \(citations.count) sources") {
                    withAnimation(Motion.smooth) { showAll.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)
                .padding(.leading, 12)
            }
        }
        .padding(.leading, -12)
    }

    private func entry(for citation: GrokCitation) -> SourceRow.Entry {
        let url = citation.url
        if let handle = XLinks.handle(ofPost: url) {
            return .init(title: String(localized: "Post by @\(handle)"), detail: nil, site: "@" + handle, host: "x.com", url: url)
        }
        let key = Self.normalized(url)
        if let result = (search.results + search.articleResults).first(where: { Self.normalized($0.url) == key }) {
            return .init(title: result.title, detail: result.plainSnippet, site: CitationLabel.label(for: url), host: url.host ?? "", url: url)
        }
        return .init(title: citation.title ?? Self.title(from: url), detail: nil, site: CitationLabel.label(for: url),
                     host: url.host ?? "", url: url)
    }

    static func normalized(_ url: URL) -> String {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return host + path.lowercased()
    }

    /// A readable title out of an address: "starship-flight-14" → "Starship flight 14".
    static func title(from url: URL) -> String {
        let last = url.pathComponents.last { $0 != "/" && !$0.allSatisfy(\.isNumber) } ?? ""
        let words = (last.removingPercentEncoding ?? last)
            .replacingOccurrences(of: #"\.(html?|php|aspx?)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard words.count > 2 else { return CitationLabel.label(for: url) }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

private struct SourceRow: View {
    struct Entry {
        let title: String
        let detail: String?
        let site: String
        let host: String
        let url: URL
    }

    let entry: Entry
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 7) {
                    ResultIcon(host: entry.host, size: 15)
                        .clipShape(Circle())
                    Text(entry.site)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .tip(verbatim: entry.url.absoluteString)
    }
}

