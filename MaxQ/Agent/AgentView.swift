//
//  AgentView.swift
//  Max Q
//
//  The Agent page of the Grok panel: the task, then each step as Grok takes it (a line with a
//  glyph, shimmering while it happens), the questions it needs a yes to, its summary at the end,
//  and the composer for the task or what to do next. Stop is always one click away.
//

import SwiftUI

struct AgentView: View {
    @Bindable var browser: BrowserModel
    @Bindable var agent: AgentSession
    @FocusState private var composerFocused: Bool
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !agent.hasRun {
                            AgentEmptyState(browser: browser, agent: agent)
                                .padding(.top, 28)
                        } else {
                            if let tab = agent.tab, agent.isActive, browser.selectedTab !== tab {
                                workingElsewhere(tab)
                            }
                            ForEach(Array(agent.tasks.enumerated()), id: \.offset) { index, task in
                                taskBubble(task)
                                ForEach(steps(forTask: index)) { step in
                                    AgentStepRow(step: step)
                                        .transition(.blurFade())
                                }
                            }
                            phaseCard
                                .transition(.blurFade())
                        }
                        Color.clear.frame(height: 2).id("end")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .animation(Motion.smooth, value: agent.steps)
                    .animation(Motion.smooth, value: agent.phase)
                }
                .scrollIndicators(.never)
                .scrollEdgeFade()
                .onChange(of: agent.scrollTrigger) { _, _ in
                    withAnimation(Motion.smooth) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            AgentComposer(browser: browser, agent: agent, focused: $composerFocused)
        }
        .onAppear {
            if !agent.isActive { DispatchQueue.main.async { composerFocused = true } }
        }
        .onChange(of: browser.composerFocusRequest) { _, _ in
            guard !agent.isActive else { return }
            browser.window?.makeFirstResponder(nil)
            DispatchQueue.main.async { composerFocused = true }
        }
        .onChange(of: agent.phase) { _, phase in
            if case .asking = phase { DispatchQueue.main.async { replyFocused = true } }
        }
    }

    /// The steps taken for the task at `index` (each "next" task starts after the steps before it).
    private func steps(forTask index: Int) -> [AgentStep] {
        let bounds = agent.taskStarts
        guard bounds.indices.contains(index) else { return [] }
        let start = bounds[index]
        let end = index + 1 < bounds.count ? bounds[index + 1] : agent.steps.count
        guard start <= end, end <= agent.steps.count else { return [] }
        return Array(agent.steps[start..<end])
    }

    private func taskBubble(_ task: String) -> some View {
        Text(task)
            .font(.system(size: 14))
            .foregroundStyle(Theme.textPrimary)
            .lineSpacing(2)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.selected))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
            .padding(.bottom, 4)
    }

    private func workingElsewhere(_ tab: BrowserTab) -> some View {
        Button { browser.select(tab) } label: {
            HStack(spacing: 8) {
                Icon(.pointer, size: 14)
                Text("Working in “\(tab.displayTitle)”")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("Show")
                    .foregroundStyle(Theme.textPrimary)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.hover))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var phaseCard: some View {
        switch agent.phase {
        case .idle, .working:
            EmptyView()
        case .approving(let approval):
            ApprovalCard(approval: approval) { agent.decide($0) }
        case .asking(let question):
            QuestionCard(question: question, reply: $agent.reply, focused: $replyFocused,
                         send: { agent.sendReply() }, stop: { agent.stop() })
        case .done(let summary):
            VStack(alignment: .leading, spacing: 10) {
                MarkdownText(text: summary, fontSize: 14) { url in browser.openInNewTab(url) }
                    .textSelection(.enabled)
                footerLine(String(localized: "Done"))
            }
            .padding(.top, 4)
        case .outOfBudget:
            NoticeCard(title: String(localized: "Grok reached this task's budget."),
                       detail: String(localized: "\(GrokAccount.formatCost(agent.costUSD)) spent. It can go on with \(Money.usd(AppSettings.shared.agentBudgetUSD)) more."),
                       action: String(localized: "Go on")) { agent.extendBudget() }
        case .failed(let message):
            NoticeCard(title: message, detail: nil,
                       action: agent.canGoOn ? String(localized: "Go on") : nil) { agent.extendBudget() }
        case .stopped:
            footerLine(String(localized: "Stopped"))
        }
    }

    private func footerLine(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text("·")
            Text(agent.actionCount == 1 ? String(localized: "1 step") : String(localized: "\(agent.actionCount) steps"))
            if agent.costUSD > 0 {
                Text("·")
                Text(GrokAccount.formatCost(agent.costUSD))
                    .font(.mono(11.5, weight: .regular))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Empty state

private struct AgentEmptyState: View {
    @Bindable var browser: BrowserModel
    @Bindable var agent: AgentSession
    @State private var revealed = false

    private var onPage: Bool {
        guard let tab = browser.selectedTab else { return false }
        return !tab.isHome && tab.nativeSearch == nil && tab.nativePage == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("What should Grok ")
                    Text("do?")
                        .overlay(alignment: .bottom) {
                            SpectrumLine(height: 2).offset(y: 4)
                        }
                }
                .font(.heading(22))
                .tracking(-0.44)
                .foregroundStyle(Theme.textPrimary)
                .reveal(revealed)
                Text("Grok works in this tab the way you would: it reads the page, clicks, types and scrolls while you watch. It asks before buying, sending, posting or deleting anything, and never types passwords or card numbers.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(revealed, delay: 0.06)
            }

            VStack(alignment: .leading, spacing: 8) {
                if onPage {
                    suggestion(String(localized: "Find the best value on this page"), icon: .search, delay: 0.12)
                    suggestion(String(localized: "Fill in this form, then stop before sending"), icon: .compose, delay: 0.15)
                    suggestion(String(localized: "Go through the comments and sum up what people think"), icon: .bubble, delay: 0.18)
                } else {
                    suggestion(String(localized: "Open the top story on Hacker News and sum it up"), icon: .lines, delay: 0.12)
                    suggestion(String(localized: "Find the next SpaceX launch on an official page"), icon: .calendar, delay: 0.15)
                }
            }

            Text("Each task runs on your SpaceXAI key, up to its budget. Banking, payment and password sites are off limits, and so are sites whose terms don't allow automated use, like X, YouTube or Amazon.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(revealed, delay: 0.24)
        }
        .onAppear { revealed = true }
    }

    private func suggestion(_ title: String, icon: MQIcon, delay: Double) -> some View {
        AgentSuggestion(title: title, icon: icon) {
            agent.draft = title
            agent.send()
        }
        .reveal(revealed, delay: delay, distance: 6)
    }
}

/// grok.com's suggestion chip, as in Chat.
private struct AgentSuggestion: View {
    let title: String
    let icon: MQIcon
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Icon(icon, size: 16)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 12)
            .padding(.trailing, 15)
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .background(Capsule().fill(hovering ? Theme.hover : .clear))
            .overlay(Capsule().strokeBorder(hovering ? Theme.borderStrong : Theme.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

// MARK: - Steps

private struct AgentStepRow: View {
    let step: AgentStep

    var body: some View {
        if step.kind == .note {
            Text(step.title)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Icon(step.kind.icon, size: 14)
                    .foregroundStyle(step.state == .running ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
                VStack(alignment: .leading, spacing: 2) {
                    if step.state == .running {
                        ShimmerText(text: step.title, font: .system(size: 13.5), base: Theme.textSecondary, peak: Theme.textPrimary)
                    } else {
                        Text(step.title)
                            .font(.system(size: 13.5))
                            .foregroundStyle(step.state == .done ? Theme.textPrimary : Theme.textTertiary)
                            .strikethrough(step.state == .refused, color: Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let detail = step.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                stateMark
            }
        }
    }

    @ViewBuilder
    private var stateMark: some View {
        switch step.state {
        case .running:
            EmptyView()
        case .done:
            Icon(.check, size: 13)
                .foregroundStyle(Theme.textTertiary)
        case .refused:
            Text("Not allowed")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        case .failed:
            Icon(.minus, size: 13)
                .foregroundStyle(Theme.textQuaternary)
        }
    }
}

extension AgentStep.Kind {
    var icon: MQIcon {
        switch self {
        case .read: .eye
        case .click: .pointer
        case .type: .compose
        case .select: .chevronUpDown
        case .scroll: .chevronDown
        case .navigate: .globe
        case .search: .search
        case .back: .arrowLeft
        case .find: .zoomIn
        case .wait: .clock
        case .ask: .bubble
        case .note: .lines
        }
    }
}

// MARK: - Cards

/// An action waiting for the user: what it is, and Allow or Don't Allow.
private struct ApprovalCard: View {
    let approval: AgentApproval
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Icon(.shield, size: 15)
                    .foregroundStyle(Theme.textSecondary)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                VStack(alignment: .leading, spacing: 4) {
                    Text(approval.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = approval.detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                    Text("Grok needs your yes for this.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 8) {
                Button("Allow") { decide(true) }
                    .pill(.primary, size: .small)
                    .keyboardShortcut(.defaultAction)
                Button("Don't Allow") { decide(false) }
                    .pill(.secondary, size: .small)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Grok's question, with a field for the answer.
private struct QuestionCard: View {
    let question: String
    @Binding var reply: String
    var focused: FocusState<Bool>.Binding
    let send: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            TextField("Your answer", text: $reply, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...5)
                .focused(focused)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.input))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            HStack(spacing: 8) {
                Button("Reply", action: send)
                    .pill(.primary, size: .small)
                    .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Stop the Task", action: stop)
                    .pill(.secondary, size: .small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

private struct NoticeCard: View {
    let title: String
    let detail: String?
    let action: String?
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Button(action, action: perform)
                    .pill(.secondary, size: .small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.hover))
    }
}

// MARK: - Composer

private struct AgentComposer: View {
    @Bindable var browser: BrowserModel
    @Bindable var agent: AgentSession
    var focused: FocusState<Bool>.Binding

    private var placeholder: String {
        if agent.isActive { return String(localized: "Grok is working…") }
        return agent.hasRun ? String(localized: "What should Grok do next?") : String(localized: "Tell Grok what to do on this page")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $agent.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...6)
                .focused(focused)
                .disabled(agent.isActive)
                .onSubmit { agent.send() }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 10)

            HStack(spacing: 4) {
                budgetMenu
                if agent.costUSD > 0 {
                    Text(GrokAccount.formatCost(agent.costUSD))
                        .font(.mono(11.5, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                        .contentTransition(.numericText())
                        .padding(.leading, 4)
                        .tip("What this task has cost so far")
                }
                Spacer(minLength: 4)
                actionButton
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous).fill(Theme.input))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous)
                .strokeBorder(focused.wrappedValue ? Theme.border : Theme.composerBorder, lineWidth: 1)
        )
        .elevation(.composer)
        .padding(12)
        .animation(Motion.standard(0.18), value: focused.wrappedValue)
    }

    private var budgetMenu: some View {
        MenuButton(placement: .above(.leading)) { _ in
            HStack(spacing: 5) {
                Text("Up to \(Money.usd(AppSettings.shared.agentBudgetUSD))")
                Icon(.chevronUpDown, size: 12)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(Theme.hover))
            .contentShape(Capsule())
        } content: {
            MenuCard(width: 230) {
                ForEach(AgentSession.budgets, id: \.self) { budget in
                    MenuRow(verbatim: Money.usd(budget), checked: AppSettings.shared.agentBudgetUSD == budget) {
                        AppSettings.shared.agentBudgetUSD = budget
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .tip("What one task may spend before Grok stops and asks")
    }

    @ViewBuilder
    private var actionButton: some View {
        ZStack {
            if agent.isActive {
                Button { agent.stop() } label: { Icon(.stop, size: 16) }
                    .stopButton(size: 34)
                    .tip("Stop")
                    .accessibilityLabel("Stop the Task")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Button { agent.send() } label: { Icon(.arrowUp, size: 18, weight: 2.2) }
                    .sendButton(size: 34)
                    .disabled(agent.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .tip("Start", shortcut: "↩")
                    .accessibilityLabel("Start the Task")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(Motion.pop, value: agent.isActive)
    }
}

// MARK: - On the page

/// What shows on the tab Grok is working in: a glow around the page and a pill with Stop.
struct AgentWorkingOverlay: View {
    @Bindable var agent: AgentSession
    let tab: BrowserTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var working: Bool { agent.isActive && agent.tabID == tab.id }

    var body: some View {
        ZStack(alignment: .bottom) {
            if working {
                glow
                    .allowsHitTesting(false)
                    .transition(.opacity)
                pill
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.smooth, value: working)
    }

    private var glow: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0.5 : (sin(timeline.date.timeIntervalSinceReferenceDate * 2) + 1) / 2
            Rectangle()
                .strokeBorder(Theme.accent.opacity(0.35 + 0.35 * phase), lineWidth: 2)
                .blur(radius: 1.5)
                .overlay(Rectangle().strokeBorder(Theme.accent.opacity(0.12 + 0.1 * phase), lineWidth: 10).blur(radius: 8))
        }
    }

    private var pill: some View {
        HStack(spacing: 10) {
            Icon(.pointer, size: 14)
            Text(agent.phase.isWaitingForUser ? String(localized: "Grok is waiting for you") : String(localized: "Grok is working in this tab"))
                .font(.system(size: 13, weight: .medium))
            Button { agent.stop() } label: {
                Text("Stop")
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Theme.onTooltip.opacity(0.16)))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.onTooltip)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(Capsule().fill(Theme.tooltip))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

extension AgentSession.Phase {
    var isWaitingForUser: Bool {
        switch self {
        case .approving, .asking: true
        default: false
        }
    }
}
