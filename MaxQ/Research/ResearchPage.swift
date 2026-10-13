//
//  ResearchPage.swift
//  Max Q
//
//  A research report, drawn natively in its tab like the results page, and set like a Grokipedia
//  article: the title in the serif, what it cost and how it was made, then the report section by
//  section with its sources linked, the contents beside it on wide windows. While Grok works, the
//  steps show above the report: each question, what Grok is searching, and its notes as they come.
//  The start sheet asks for the question and the budget.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ResearchDraft: Identifiable {
    let id = UUID()
    var question: String
}

// MARK: - Starting

struct ResearchSheet: View {
    @Bindable var browser: BrowserModel
    let draft: ResearchDraft
    @State private var question = ""
    @State private var budget = AppSettings.shared.researchBudgetUSD
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private let budgets: [Double] = [0.10, 0.25, 0.50, 1, 2]
    private var store: ResearchStore { ResearchStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Icon(.stack, size: 18)
                Text("Research with Grok")
                    .font(.heading(20))
                    .tracking(-0.3)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.bottom, 6)
            Text("Grok plans a few questions, searches the web and X for each, then writes a report with every source linked. You can watch it work, and stop it.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            TextField("What do you want to know?", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(2...5)
                .focused($focused)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.input))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                .padding(.bottom, 18)

            Text("Budget")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 8)
            HStack(spacing: 6) {
                ForEach(budgets, id: \.self) { value in
                    Button { withAnimation(Motion.glide) { budget = value } } label: {
                        Text(Money.usd(value, digits: value < 1 ? 2 : 0))
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(budget == value ? Theme.onInk : Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().fill(budget == value ? Theme.ink : Theme.hover))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)
            Text(estimateLine)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.interpolate)

            if !GrokAccount.shared.hasKey {
                Text("Research runs on your SpaceXAI API key. Add it in Settings to start.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 14)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .pill(.ghost, size: .regular)
                    .keyboardShortcut(.cancelAction)
                Button("Start research") { start() }
                    .pill(.primary, size: .regular)
                    .keyboardShortcut(.defaultAction)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !GrokAccount.shared.hasKey)
            }
            .padding(.top, 22)
        }
        .padding(24)
        .frame(width: 480)
        .background(Theme.elevated)
        .onAppear {
            question = draft.question
            focused = true
        }
    }

    private var estimateLine: String {
        let estimate = store.estimate(steps: 4)
        let steps = max(1, min(6, Int((budget - store.writingEstimate()) / max(store.stepEstimate, 0.001))))
        if estimate <= budget {
            return String(localized: "About \(GrokAccount.friendlyCost(estimate, approximate: false)) for four steps. Max Q stops before going over \(Money.usd(budget)).")
        }
        return String(localized: "This budget allows about \(steps) steps. Max Q stops before going over \(Money.usd(budget)).")
    }

    private func start() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        AppSettings.shared.researchBudgetUSD = budget
        dismiss()
        let id = store.start(text, budget: budget)
        browser.openNative(.research(id), inNewTab: true)
    }
}

// MARK: - The page

struct ResearchPage: View {
    @Bindable var browser: BrowserModel
    let id: UUID
    @State private var store = ResearchStore.shared
    @State private var showsSteps = true

    private var report: ResearchReport? { store.report(id) }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 1_060
            if let report {
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 56) {
                            VStack(alignment: .leading, spacing: 0) {
                                header(report)
                                    .padding(.bottom, 26)
                                if report.isRunning || showsSteps {
                                    StepsView(report: report)
                                        .padding(.bottom, 30)
                                        .transition(.opacity)
                                }
                                ReportBody(report: report) { open($0) }
                                if !report.sources.isEmpty {
                                    SourcesBlock(sources: report.sources) { open($0) }
                                        .padding(.top, 36)
                                        .id("sources")
                                }
                            }
                            .frame(maxWidth: 700, alignment: .leading)
                            if wide {
                                ReportRail(report: report) { section in
                                    withAnimation(Motion.page) { reader.scrollTo(section, anchor: .top) }
                                }
                                .frame(width: 240)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 40)
                        .padding(.bottom, 80)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollEdgeFade()
                }
                .onChange(of: report.phase) { _, phase in
                    if phase == .done { withAnimation(Motion.smooth) { showsSteps = false } }
                }
                .onAppear { showsSteps = report.isRunning }
            } else {
                VStack(spacing: 10) {
                    Text("This research isn't on this Mac anymore.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface)
    }

    private func header(_ report: ResearchReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Icon(.stack, size: 13)
                Text("Research by Grok")
                Text("·").foregroundStyle(Theme.textQuaternary)
                Text(report.created.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            Text(report.title.isEmpty ? report.question : report.title)
                .font(.serif(38, weight: .medium))
                .tracking(-38 * 0.02)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !report.title.isEmpty, report.title != report.question {
                Text(report.question)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Text(meta(report))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                actions(report)
            }
            .padding(.top, 4)
        }
    }

    private func meta(_ report: ResearchReport) -> String {
        let done = report.steps.filter { $0.phase == .done }.count
        var parts = [String(localized: "\(done) of \(report.steps.count) steps")]
        if !report.sources.isEmpty { parts.append(String(localized: "\(report.sources.count) sources")) }
        parts.append(String(localized: "\(GrokAccount.formatCost(report.spent)) of \(Money.usd(report.budget))"))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func actions(_ report: ResearchReport) -> some View {
        if report.isRunning {
            Button("Stop") { store.stop(report.id) }
                .pill(.secondary, size: .mini)
        } else {
            HStack(spacing: 4) {
                Button { withAnimation(Motion.smooth) { showsSteps.toggle() } } label: {
                    Text(showsSteps ? "Hide steps" : "Show steps")
                }
                .pill(.ghost, size: .mini)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.markdown(report.id), forType: .string)
                    browser.showToast(String(localized: "Report copied as Markdown."))
                } label: { Icon(.copy, size: 15) }
                .iconButton(size: 28)
                .tip("Copy as Markdown")
                .accessibilityLabel("Copy as Markdown")
                Button { export(report) } label: { Icon(.download, size: 15) }
                    .iconButton(size: 28)
                    .tip("Save as a Markdown file")
                    .accessibilityLabel("Save as a Markdown File")
                Button("Continue in Grok") {
                    browser.continueInChat(question: report.question, answer: report.report,
                                           citations: report.sources.compactMap(URL.init(string:)).map { GrokCitation(url: $0, title: nil) },
                                           model: report.model)
                }
                .pill(.secondary, size: .mini)
            }
        }
    }

    private func open(_ url: URL) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        browser.openInNewTab(url, select: !flags.contains(.command))
    }

    private func export(_ report: ResearchReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        let name = (report.title.isEmpty ? report.question : report.title)
            .replacingOccurrences(of: "/", with: "-").prefix(80)
        panel.nameFieldStringValue = "\(name).md"
        guard let window = browser.window else { return }
        let text = store.markdown(report.id)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Steps

/// How Grok is working: each question with where it's at, its notes a click away.
private struct StepsView: View {
    let report: ResearchReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(phaseLine)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if report.isRunning { LiveDot(color: Theme.textSecondary, size: 5) }
            }
            .padding(.bottom, 6)
            if report.phase == .planning {
                ShimmerText(text: String(localized: "Planning what to look into"), font: .system(size: 14, weight: .medium))
            }
            ForEach(report.steps) { step in
                StepRow(step: step)
            }
            if report.phase == .writing {
                HStack(spacing: 10) {
                    Icon(.compose, size: 15)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 20)
                    ShimmerText(text: String(localized: "Writing the report"), font: .system(size: 14, weight: .medium))
                }
                .padding(.vertical, 8)
            }
            if report.phase == .failed, let failure = report.failure {
                Text(failure)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 6)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .animation(Motion.smooth, value: report.steps.map(\.phase))
        .animation(Motion.smooth, value: report.phase)
    }

    private var phaseLine: String {
        switch report.phase {
        case .planning: String(localized: "Planning")
        case .searching: String(localized: "Researching")
        case .writing: String(localized: "Writing")
        case .done: String(localized: "How Grok worked")
        case .stopped: String(localized: "Stopped")
        case .failed: String(localized: "Research didn't finish")
        }
    }
}

private struct StepRow: View {
    let step: ResearchStep
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { if !step.notes.isEmpty { withAnimation(Motion.smooth) { open.toggle() } } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    mark
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.question)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(step.phase == .skipped ? Theme.textTertiary : Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let line = detail {
                            Text(line)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    if !step.notes.isEmpty, step.phase == .done {
                        MorphChevron(open: open, size: 11)
                            .foregroundStyle(Theme.textQuaternary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open || step.phase == .searching, !step.notes.isEmpty {
                MarkdownText(text: step.notes, fontSize: 13, streaming: step.phase == .searching) { _ in }
                    .padding(.leading, 30)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var mark: some View {
        switch step.phase {
        case .waiting: Circle().strokeBorder(Theme.border, lineWidth: 1.5).frame(width: 12, height: 12)
        case .searching: TypingDots(size: 4)
        case .done: Icon(.check, size: 14).foregroundStyle(Theme.textPrimary)
        case .skipped: Icon(.minus, size: 14).foregroundStyle(Theme.textQuaternary)
        case .failed: Icon(.warning, size: 14).foregroundStyle(Theme.textTertiary)
        }
    }

    private var detail: String? {
        switch step.phase {
        case .searching: step.status.map(GrokStatusText.display) ?? String(localized: "Taking notes")
        case .done: step.sources.isEmpty ? nil : String(localized: "\(step.sources.count) sources · \(GrokAccount.formatCost(step.cost))")
        case .skipped: String(localized: "Skipped to stay within the budget")
        case .failed: step.status ?? String(localized: "Didn't finish")
        case .waiting: nil
        }
    }
}

// MARK: - The report

/// One section of the report: its heading, and the Markdown under it.
struct ReportSection: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String

    /// Splits a report at its "## " headings. What's before the first is the introduction (no title).
    static func sections(of markdown: String) -> [ReportSection] {
        var sections: [ReportSection] = []
        var title = ""
        var lines: [String] = []
        func flush() {
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty || !title.isEmpty {
                sections.append(ReportSection(id: "s-\(sections.count)", title: title, body: body))
            }
            lines = []
        }
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("# ") { continue }
            if line.hasPrefix("## ") {
                flush()
                title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else {
                lines.append(line)
            }
        }
        flush()
        return sections
    }
}

private struct ReportBody: View {
    let report: ResearchReport
    let open: (URL) -> Void

    var body: some View {
        let sections = ReportSection.sections(of: report.report)
        VStack(alignment: .leading, spacing: 26) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.serif(25, weight: .medium))
                            .tracking(-0.4)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    MarkdownText(text: section.body, fontSize: 16, streaming: report.phase == .writing && section == sections.last,
                                 lineSpacing: 6, blockSpacing: 12, onOpenLink: open)
                        .foregroundStyle(Theme.textReading)
                }
                .id(section.id)
                .transition(.blurFade())
            }
        }
        .animation(Motion.smooth, value: sections.count)
    }
}

/// Every source, numbered, with its site.
private struct SourcesBlock: View {
    let sources: [String]
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(.serif(22, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                if let url = URL(string: source) {
                    Button { open(url) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 22, alignment: .trailing)
                            ResultIcon(host: url.host ?? "", size: 13)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(CitationLabel.label(for: url))
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(url.absoluteString)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Beside the report on wide windows: its sections, and where the money went.
private struct ReportRail: View {
    let report: ResearchReport
    let jump: (String) -> Void

    var body: some View {
        let sections = ReportSection.sections(of: report.report).filter { !$0.title.isEmpty }
        VStack(alignment: .leading, spacing: 4) {
            if !sections.isEmpty {
                Text("Contents")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 4)
                ForEach(sections) { section in
                    Button { jump(section.id) } label: {
                        Text(section.title)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !report.sources.isEmpty {
                    Button { jump("sources") } label: {
                        Text("Sources")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 140)
    }
}
