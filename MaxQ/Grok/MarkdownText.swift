//
//  MarkdownText.swift
//  Max Q
//
//  Renders Grok's Markdown answers: headings, lists, quotes, code blocks and inline styling.
//  SwiftUI's Text only understands inline Markdown, so blocks are split here first. Links open
//  in a new Max Q tab. Model output is only ever displayed, never executed.
//

import AppKit
import SwiftUI

nonisolated enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(indent: Int, text: String)
    case numbered(number: String, indent: Int, text: String)
    case quote(String)
    case code(language: String, text: String)
    case rule
    case table([String])
}

enum MarkdownParser {
    nonisolated static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String]? = nil
        var codeLanguage = ""
        var tableLines: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        func flushTable() {
            if !tableLines.isEmpty {
                blocks.append(.table(tableLines))
                tableLines = []
            }
        }

        for rawLine in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if codeLines != nil {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, text: codeLines!.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    codeLines!.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                flushParagraph(); flushTable()
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLines = []
                continue
            }
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1 {
                flushParagraph()
                tableLines.append(trimmed)
                continue
            } else {
                flushTable()
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                continue
            }
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                if hashes <= 6, trimmed.dropFirst(hashes).first == " " {
                    flushParagraph()
                    blocks.append(.heading(level: hashes, text: String(trimmed.dropFirst(hashes + 1))))
                    continue
                }
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            let indent = (line.prefix(while: { $0 == " " }).count) / 2
            if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first == " " {
                flushParagraph()
                blocks.append(.bullet(indent: indent, text: String(trimmed.dropFirst(2))))
                continue
            }
            if let dot = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }),
               trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty, trimmed[..<dot].count <= 3,
               trimmed[trimmed.index(after: dot)...].first == " " {
                flushParagraph()
                let number = String(trimmed[..<dot])
                let text = String(trimmed[trimmed.index(dot, offsetBy: 2)...])
                blocks.append(.numbered(number: number, indent: indent, text: text))
                continue
            }
            paragraph.append(trimmed)
        }
        if let codeLines { blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n"))) }
        flushParagraph()
        flushTable()
        return blocks
    }

    nonisolated static func inline(_ text: String) -> AttributedString {
        answerInline(text, chipSize: nil).text
    }

    /// Inline Markdown with Grok's citations set as chips, the way grok.com sets them: the source's
    /// name in a small pill at the end of the sentence ("Techcrunch", "@spacex"), one pill for a run
    /// of citations ("Spacex +2"). Returns the text and the chips' character ranges, for drawing.
    nonisolated static func answerInline(_ text: String, chipSize: CGFloat?, chipColor: Color? = nil,
                                         handles: [String: String] = [:],
                                         allowsTabLinks: Bool = false) -> (text: AttributedString, chips: [Range<Int>]) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        let source = chipMarkers(text, handles: handles)
        var result = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        // Only web links may be clickable in model output (and, in an answer about the user's
        // tabs, links that switch to one of them).
        for run in result.runs {
            guard let link = run.link else { continue }
            let allowed = link.scheme == "https" || link.scheme == "http" || (allowsTabLinks && Self.appLinkSchemes.contains(link.scheme ?? ""))
            if !allowed { result[run.range].link = nil }
        }
        // The chips: marked by an invisible separator in front of their label.
        let chipRuns = result.runs.filter { run in
            run.link != nil && result[run.range].characters.first == Self.chipMark
        }.map { ($0.range, $0.link) }
        for (range, link) in chipRuns.reversed() {
            let label = String(result[range].characters.dropFirst())
            var chip = AttributedString("\u{00A0}\u{00A0}" + label + "\u{00A0}\u{00A0}")
            chip.link = link
            if let chipSize {
                chip.font = .system(size: chipSize, weight: .medium)
                chip.foregroundColor = chipColor
            }
            chip[CitationChipKey.self] = true
            result.replaceSubrange(range, with: chip)
        }
        var chips: [Range<Int>] = []
        if chipSize != nil {
            for run in result.runs where run.attributes[CitationChipKey.self] == true {
                let lower = result.characters.distance(from: result.startIndex, to: run.range.lowerBound)
                let upper = result.characters.distance(from: result.startIndex, to: run.range.upperBound)
                chips.append(lower..<upper)
            }
        }
        return (result, chips)
    }

    /// Links in an answer about the user's tabs: "maxq-tab://2" switches to the second tab sent.
    nonisolated static let tabLinkScheme = "maxq-tab"
    /// A moment in a video: "maxq-seek://190" plays the video from 3:10.
    nonisolated static let seekLinkScheme = "maxq-seek"
    /// A section of the article being read: "maxq-section://h-early-life".
    nonisolated static let sectionLinkScheme = "maxq-section"
    /// Max Q's own links an answer may carry, when it was asked with what they point to.
    nonisolated static let appLinkSchemes: Set<String> = [tabLinkScheme, seekLinkScheme, sectionLinkScheme]

    /// U+2063 INVISIBLE SEPARATOR, put in front of a chip's label while the Markdown is parsed.
    nonisolated static let chipMark: Character = "\u{2063}"

    /// Grok writes its citations inline as `[[1]](url)`. A run of them becomes one Markdown link
    /// whose text is the first source's name, marked as a chip: "rocket [⁣Spacex +1](https://…)".
    nonisolated static func chipMarkers(_ text: String, handles: [String: String] = [:]) -> String {
        guard text.contains("[[") else { return text }
        guard let group = try? NSRegularExpression(pattern: #"(?:[ \t]*\[\[\d{1,3}\]\]\((https?://[^)\s]+)\))+"#),
              let single = try? NSRegularExpression(pattern: #"\[\[\d{1,3}\]\]\((https?://[^)\s]+)\)"#) else { return text }
        let ns = text as NSString
        var output = ""
        var cursor = 0
        for match in group.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
            var urls: [String] = []
            for marker in single.matches(in: text, range: match.range) {
                let url = ns.substring(with: marker.range(at: 1))
                if !urls.contains(url) { urls.append(url) }
            }
            guard let first = urls.first, let url = URL(string: first) else { continue }
            var label = CitationLabel.label(for: url, handles: handles)
            if urls.count > 1 { label += "\u{00A0}+\(urls.count - 1)" }
            output += " [\(chipMark)\(escaped(label))](\(first))"
        }
        output += ns.substring(from: cursor)
        return output
    }

    private nonisolated static func escaped(_ label: String) -> String {
        var result = ""
        for character in label {
            if "\\[]*_`".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// While Grok is writing, a citation marker can arrive in pieces ("[[1]](htt"); hold back the
    /// unfinished end so the reader never sees half a marker.
    nonisolated static func withoutPartialCitation(_ text: String) -> String {
        guard let range = text.range(of: #"\[\[\d{0,3}(\]\]?(\([^)\s]*)?)?$"#, options: .regularExpression) else { return text }
        return String(text[..<range.lowerBound])
    }
}

struct MarkdownText: View {
    let text: String
    var fontSize: CGFloat = 13.5
    /// While Grok is still writing, the newest words clear out of a slight blur as they arrive.
    var streaming = false
    /// Extra space between lines, and between paragraphs.
    var lineSpacing: CGFloat = 3
    var blockSpacing: CGFloat = 8
    /// Names for citations Max Q already knows ("@handle" for a post read from X), by link.
    var handles: [String: String] = [:]
    /// The answer may link to the user's tabs (maxq-tab://N).
    var allowsTabLinks = false
    var onOpenLink: (URL) -> Void

    var body: some View {
        let blocks = MarkdownParser.parse(streaming ? MarkdownParser.withoutPartialCitation(text) : text)
        VStack(alignment: .leading, spacing: blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block, live: streaming && index == blocks.count - 1)
                    // Each new block of a streaming answer clears out of a slight blur, as text
                    // arrives on grok.com and x.ai.
                    .transition(.blurFade())
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .animation(Motion.expo(0.3), value: blocks.count)
        .environment(\.openURL, OpenURLAction { url in
            onOpenLink(url)
            return .handled
        })
    }

    /// Inline text with its citation chips; the block Grok is writing into animates its newest words.
    @ViewBuilder
    private func inline(_ text: String, live: Bool) -> some View {
        let parsed = MarkdownParser.answerInline(text, chipSize: fontSize - 2, chipColor: Theme.textSecondary, handles: handles,
                                                 allowsTabLinks: allowsTabLinks)
        if live {
            StreamingText(text: parsed.text, font: .system(size: fontSize), chips: parsed.chips)
        } else {
            ChipText.text(parsed.text, chips: parsed.chips)
                .font(.system(size: fontSize))
                .textRenderer(ChipRenderer())
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock, live: Bool) -> some View {
        switch block {
        case let .heading(level, text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: level <= 1 ? fontSize + 4 : (level == 2 ? fontSize + 2 : fontSize + 0.5), weight: .semibold))
                .padding(.top, 3)
        case .paragraph(let text):
            inline(text, live: live)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        case let .bullet(indent, text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(indent > 0 ? "◦" : "•").font(.system(size: fontSize)).foregroundStyle(Theme.textTertiary)
                inline(text, live: live)
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case let .numbered(number, indent, text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").font(.system(size: fontSize).monospacedDigit()).foregroundStyle(Theme.textTertiary)
                inline(text, live: live)
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle().fill(Theme.borderStrong).frame(width: 2)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: fontSize))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .code(_, text):
            CodeBlockView(code: text, fontSize: fontSize - 1.5)
        case .rule:
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 4)
        case .table(let lines):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(lines.filter { !$0.replacingOccurrences(of: "|", with: "").allSatisfy { "-: ".contains($0) } }
                    .joined(separator: "\n"))
                    .font(.mono(fontSize - 1.5, weight: .regular))
                    .fixedSize()
            }
        }
    }
}

private struct CodeBlockView: View {
    let code: String
    let fontSize: CGFloat
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.mono(fontSize, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()
                    .padding(12)
                    .padding(.trailing, 30)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                ZStack {
                    if copied {
                        Icon(.check, size: 14).transition(.glyphSwap)
                    } else {
                        Icon(.copy, size: 14).transition(.glyphSwap)
                    }
                }
            }
            .iconButton(size: 26)
            .padding(6)
            .tip("Copy code")
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.hover))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// Marks a citation chip's run in an attributed string, so its range can be found after parsing.
nonisolated enum CitationChipKey: AttributedStringKey {
    typealias Value = Bool
    static let name = "MaxQCitationChip"
}

/// The name a citation goes by, as grok.com names its sources: "@handle" for a post on X, and
/// for a site its own name taken from the address ("Techcrunch", "Wikipedia"), with the usual
/// spelling for well-known ones.
nonisolated enum CitationLabel {
    static func label(for url: URL, handles: [String: String] = [:]) -> String {
        if let known = handles[url.absoluteString] { return known }
        let host = (url.host ?? "").lowercased()
        if ["x.com", "twitter.com", "www.x.com", "mobile.x.com", "www.twitter.com", "mobile.twitter.com"].contains(host) {
            let parts = url.path.split(separator: "/").map(String.init)
            if let handle = parts.first, !["i", "search", "hashtag", "home", "explore"].contains(handle.lowercased()) {
                return "@" + handle
            }
            return "X"
        }
        return siteName(host)
    }

    static func siteName(_ host: String) -> String {
        let bare = host.lowercased().hasPrefix("www.") ? String(host.lowercased().dropFirst(4)) : host.lowercased()
        if let name = knownHosts[bare] { return name }
        var labels = host.lowercased().split(separator: ".").map(String.init)
        while labels.count > 2, let first = labels.first, ["www", "m", "mobile", "amp"].contains(first) || first.count == 2 {
            labels.removeFirst()
        }
        guard labels.count >= 2 else { return capitalized(labels.first ?? host) }
        let tail = labels.suffix(2).joined(separator: ".")
        let paired = ["co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "co.jp", "co.in", "com.br", "co.nz",
                      "co.za", "com.mx", "com.cn", "com.tr", "co.kr", "com.sg", "com.hk"]
        let name = paired.contains(tail) && labels.count >= 3 ? labels[labels.count - 3] : labels[labels.count - 2]
        return known[name] ?? capitalized(name)
    }

    private static func capitalized(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    private static let knownHosts: [String: String] = [
        "x.ai": "SpaceXAI", "grok.com": "Grok", "grokipedia.com": "Grokipedia", "news.ycombinator.com": "Hacker News",
    ]

    private static let known: [String: String] = [
        "techcrunch": "TechCrunch", "youtube": "YouTube", "spacex": "SpaceX", "nasa": "NASA", "bbc": "BBC",
        "cnn": "CNN", "cnbc": "CNBC", "nytimes": "NYTimes", "wsj": "WSJ", "github": "GitHub", "linkedin": "LinkedIn",
        "tiktok": "TikTok", "theverge": "The Verge", "arstechnica": "Ars Technica", "imdb": "IMDb", "espn": "ESPN",
        "npr": "NPR", "apnews": "AP News", "ft": "FT", "theguardian": "The Guardian", "washingtonpost": "Washington Post",
        "businessinsider": "Business Insider", "foxnews": "Fox News", "nbcnews": "NBC News", "cbsnews": "CBS News",
        "abcnews": "ABC News", "usatoday": "USA Today", "x": "X", "openai": "OpenAI", "ycombinator": "Y Combinator",
        "stackoverflow": "Stack Overflow", "macrumors": "MacRumors", "9to5mac": "9to5Mac", "lemonde": "Le Monde",
        "lefigaro": "Le Figaro", "spiegel": "Der Spiegel", "aljazeera": "Al Jazeera", "skynews": "Sky News",
        "teslarati": "Teslarati", "space": "Space.com", "wired": "WIRED", "pcmag": "PCMag", "zdnet": "ZDNET",
        "cnet": "CNET", "ign": "IGN", "nasaspaceflight": "NASASpaceflight", "politico": "POLITICO",
    ]
}
