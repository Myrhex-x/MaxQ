//
//  ShareAnswer.swift
//  Max Q
//
//  An answer from Grok as a picture to share: the question, the answer, and the sites it cites,
//  set on a card in x.ai's black (or white), with where it came from at the foot. The sheet shows
//  the card in both themes and copies it, saves it, or opens a post on X with the picture copied,
//  ready to paste.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShareAnswerDraft: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
    let citations: [GrokCitation]
    let date: Date
}

struct ShareAnswerSheet: View {
    @Bindable var browser: BrowserModel
    let draft: ShareAnswerDraft
    @State private var dark = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Share as a picture")
                    .font(.heading(20))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 2) {
                    themeButton(true, title: "Dark")
                    themeButton(false, title: "Light")
                }
                .padding(3)
                .background(Capsule().fill(Theme.hover))
            }
            ScrollView(.vertical) {
                ShareCard(draft: draft, dark: dark)
                    .scaleEffect(0.82, anchor: .top)
                    .frame(width: ShareCard.width * 0.82, height: nil, alignment: .top)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 440)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.canvas))
            Text("The picture shows the question, Grok's answer and the sites it cites. It says it was made with Max Q, an independent browser.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Done") { dismiss() }
                    .pill(.ghost, size: .regular)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button { save() } label: { Text("Save…") }
                    .pill(.secondary, size: .regular)
                Button { copy() } label: { Text("Copy picture") }
                    .pill(.secondary, size: .regular)
                Button { postOnX() } label: { Text("Post on X") }
                    .pill(.primary, size: .regular)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(Theme.elevated)
    }

    private func themeButton(_ value: Bool, title: LocalizedStringKey) -> some View {
        Button { withAnimation(Motion.glide) { dark = value } } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(dark == value ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(Capsule().fill(dark == value ? Theme.raised : .clear))
        }
        .buttonStyle(.plain)
    }

    /// The card at twice its size, as PNG data.
    @MainActor
    private func render() -> (NSImage, Data)? {
        let renderer = ImageRenderer(content: ShareCard(draft: draft, dark: dark))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return (image, png)
    }

    private func copy() {
        guard let (image, _) = render() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        browser.showToast(String(localized: "Picture copied."))
    }

    private func save() {
        guard let (_, png) = render(), let window = browser.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = String(localized: "Grok's answer.png")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            try? png.write(to: url, options: .atomic)
        }
    }

    /// Copies the picture, then opens a post on X with the question as its text: paste to attach.
    private func postOnX() {
        copy()
        dismiss()
        if let intent = XLinks.intent(text: draft.question, url: nil) { browser.openInNewTab(intent) }
        browser.showToast(String(localized: "The picture is copied: paste it into your post."))
    }
}

/// The picture itself, drawn the same in the preview and in the file.
struct ShareCard: View {
    let draft: ShareAnswerDraft
    let dark: Bool

    static let width: CGFloat = 640

    private var background: Color { dark ? Color(red: 0.039, green: 0.039, blue: 0.039) : .white }
    private var primary: Color { dark ? .white : Color(red: 0.02, green: 0.02, blue: 0.02) }
    private var secondary: Color { dark ? Color.white.opacity(0.62) : Color.black.opacity(0.58) }
    private var faint: Color { dark ? Color.white.opacity(0.12) : Color.black.opacity(0.09) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                MaxQMark(size: 18, glow: false)
                Text(GrokCredit.written)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondary)
                Spacer()
                Text(draft.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12.5))
                    .foregroundStyle(secondary)
            }
            .padding(.bottom, 22)
            Text(draft.question)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            Text(Self.plain(draft.answer))
                .font(.system(size: 16))
                .lineSpacing(5)
                .foregroundStyle(primary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            if !draft.citations.isEmpty {
                Rectangle().fill(faint).frame(height: 1).padding(.vertical, 20)
                HStack(spacing: 6) {
                    Text("Sources")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(secondary)
                    Text(sources)
                        .font(.system(size: 12.5))
                        .foregroundStyle(secondary)
                        .lineLimit(2)
                }
            }
            Text("Shared from Max Q, an independent browser. Not affiliated with SpaceXAI or X.")
                .font(.system(size: 11.5))
                .foregroundStyle(secondary.opacity(0.8))
                .padding(.top, 22)
        }
        .padding(36)
        .frame(width: Self.width, alignment: .leading)
        .background(background)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var sources: String {
        var names: [String] = []
        for citation in draft.citations {
            let name = CitationLabel.label(for: citation.url)
            if !names.contains(name) { names.append(name) }
        }
        return names.prefix(6).joined(separator: " · ")
    }

    /// The answer without Markdown's marks or its citation links: just the words, with bullets.
    static func plain(_ markdown: String) -> AttributedString {
        let withoutCitations = markdown.replacingOccurrences(of: #"\s*\[\[\d{1,3}\]\]\([^)\s]+\)"#, with: "", options: .regularExpression)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var lines: [String] = []
        for line in withoutCitations.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                lines.append("•  " + trimmed.dropFirst(2))
            } else {
                lines.append(trimmed.replacingOccurrences(of: "#", with: ""))
            }
        }
        let text = lines.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n")
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        // Links read as plain words on a picture.
        for run in result.runs where run.link != nil { result[run.range].link = nil }
        return result
    }
}

/// The credit SpaceXAI's brand guidelines ask for wherever something Grok wrote or made is shared:
/// these exact words, kept in English like a name.
enum GrokCredit {
    static let written = "Written with Grok"
    static let created = "Created with Grok"
}
