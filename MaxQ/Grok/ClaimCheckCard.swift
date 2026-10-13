//
//  ClaimCheckCard.swift
//  Max Q
//
//  The card a check opens in, growing out of the words that were selected (or the post): the claim
//  in quotes, then Grok's verdict once it has one, the reasons for and against with their sources,
//  and what the check cost. While Grok searches, its steps shimmer where the verdict will be.
//

import AppKit
import SwiftUI

/// Starts a check and opens its card.
@MainActor
enum ClaimChecks {
    /// Checks `claim`, with the card under `anchor` (a rect on screen) or near the top of the window.
    static func check(_ claim: String, source: ClaimSource, anchor: NSRect?, browser: BrowserModel) {
        let text = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            browser.showToast(String(localized: "Select the words to check first."))
            return
        }
        guard GrokAccount.shared.hasKey else {
            // Without a key, grok.com does the check in the user's own account.
            browser.askGrokOnWeb(String(localized: "Fact-check this claim with sources, and say what supports it and what doesn't: \"\(GrokSession.preview(text, limit: 600))\""))
            return
        }
        guard !GrokAccount.shared.limitReached else {
            browser.showToast(String(localized: "This month's Grok limit is reached."), actionTitle: String(localized: "Check anyway")) {
                present(text, source: source, anchor: anchor, browser: browser)
            }
            return
        }
        present(text, source: source, anchor: anchor, browser: browser)
    }

    private static func present(_ claim: String, source: ClaimSource, anchor: NSRect?, browser: BrowserModel) {
        guard let window = browser.window else { return }
        let check = ClaimCheck(claim: claim, source: source)
        check.start()
        let rect = anchor ?? {
            let frame = window.frame
            return NSRect(x: frame.midX - 210, y: frame.maxY - 140, width: 420, height: 1)
        }()
        PopoverController.show(at: rect, in: window, placement: .below(.leading)) {
            ClaimCheckCard(check: check, browser: browser)
        }
    }
}

struct ClaimCheckCard: View {
    let check: ClaimCheck
    @Bindable var browser: BrowserModel
    @Environment(\.dismissPopover) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            quote
                .padding(.bottom, 16)
            verdict
            if !check.points.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(check.points) { point in
                        PointRow(point: point) { open($0) }
                            .transition(.blurFade())
                    }
                }
                .padding(.top, 14)
            }
            if !check.citations.isEmpty, check.phase == .done {
                sources
                    .padding(.top, 16)
                    .transition(.opacity)
            }
            footer
                .padding(.top, 16)
        }
        .padding(18)
        .frame(width: 440, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
        .animation(Motion.smooth, value: check.points.count)
        .animation(Motion.smooth, value: check.phase)
        .animation(Motion.smooth, value: check.verdict)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Icon(.sealCheck, size: 15)
            Text("Check with Grok")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Button { check.stop(); dismiss() } label: { Icon(.close, size: 13) }
                .iconButton(size: 24)
                .accessibilityLabel("Close")
        }
        .foregroundStyle(Theme.textSecondary)
    }

    /// The claim, quoted, and where it was read.
    private var quote: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(Theme.border).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("“\(check.claim)”")
                    .font(.serif(16, weight: .regular))
                    .foregroundStyle(Theme.textReading)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                Text(check.source.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var verdict: some View {
        switch check.phase {
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { check.start() }
                    .pill(.secondary, size: .small)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                if let verdict = check.verdict {
                    VerdictBadge(verdict: verdict)
                        .transition(.pop(anchor: .leading, scale: 0.9))
                } else {
                    ShimmerText(text: GrokStatusText.display(check.status ?? String(localized: "Searching")),
                                font: .system(size: 14, weight: .medium))
                        .contentTransition(.interpolate)
                }
                if !check.summary.isEmpty {
                    Text(check.summary)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.blurFade())
                }
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            FlowRow(spacing: 6) {
                ForEach(check.citations.prefix(8)) { citation in
                    Button { open(citation.url) } label: {
                        HStack(spacing: 5) {
                            ResultIcon(host: citation.url.host ?? "", size: 12)
                            Text(CitationLabel.label(for: citation.url))
                                .lineLimit(1)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Capsule().fill(Theme.hover))
                    }
                    .buttonStyle(.plain)
                    .help(citation.url.absoluteString)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footnote)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if check.phase == .checking {
                Button("Stop") { check.stop() }
                    .pill(.ghost, size: .mini)
            } else if check.phase == .done {
                Button { copy() } label: { Icon(.copy, size: 14) }
                    .iconButton(size: 26)
                    .tip("Copy the check")
                    .accessibilityLabel("Copy the Check")
                Button("Continue in Grok") {
                    dismiss()
                    browser.continueInChat(question: String(localized: "Check this: \"\(check.claim)\""),
                                           answer: check.transcript, citations: check.citations, model: check.model)
                }
                .pill(.secondary, size: .mini)
            }
        }
    }

    /// "Grok's reading of 6 sources · $0.012".
    private var footnote: String {
        var parts: [String] = []
        if check.phase == .done {
            parts.append(check.citations.isEmpty ? String(localized: "Grok's reading of what it found")
                         : String(localized: "Grok's reading of \(check.citations.count) sources"))
        } else if !check.steps.isEmpty {
            parts.append(GrokStatusText.display(check.steps.last ?? ""))
        }
        if let cost = check.cost { parts.append(GrokAccount.formatCost(cost)) }
        return parts.joined(separator: " · ")
    }

    private func open(_ url: URL) {
        dismiss()
        browser.openInNewTab(url)
    }

    private func copy() {
        var lines = ["“\(check.claim)”", ""]
        lines.append(check.transcript)
        if !check.citations.isEmpty {
            lines.append("")
            lines += check.citations.map(\.url.absoluteString)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        browser.showToast(String(localized: "Check copied."))
    }
}

/// The verdict: a dot in its tone (agreeing, between, disagreeing, unknown) and its name.
private struct VerdictBadge: View {
    let verdict: ClaimVerdict

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(verdict.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(Theme.hover))
        .overlay(Capsule().strokeBorder(Theme.chipBorder, lineWidth: 1))
    }

    private var color: Color {
        switch verdict.tone {
        case .agrees: Theme.success
        case .between: Theme.warning
        case .disagrees: Theme.danger
        case .unknown: Theme.textTertiary
        }
    }
}

/// One reason: a mark for which way it points, then the sentence with its sources.
private struct PointRow: View {
    let point: ClaimPoint
    let open: (URL) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(mark)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 12)
                .accessibilityLabel(label)
            MarkdownText(text: point.text, fontSize: 13.5, onOpenLink: open)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mark: String {
        switch point.stance {
        case .supports: "+"
        case .contradicts: "−"
        case .context: "·"
        }
    }

    private var label: String {
        switch point.stance {
        case .supports: String(localized: "Supports")
        case .contradicts: String(localized: "Against")
        case .context: String(localized: "Context")
        }
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension ClaimCheck {
    /// The check as text: verdict, summary, points.
    var transcript: String {
        var lines: [String] = []
        if let verdict { lines.append(String(localized: "Verdict: \(verdict.title)")) }
        if !summary.isEmpty { lines.append(summary) }
        for point in points {
            let mark = switch point.stance { case .supports: "+"; case .contradicts: "-"; case .context: "~" }
            lines.append("\(mark) \(point.text)")
        }
        lines.append(GrokCredit.written)
        return lines.joined(separator: "\n")
    }
}
