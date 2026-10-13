//
//  CrossTabModules.swift
//  Max Q
//
//  What ties the results page's tabs together: each shows a little of the others, with a way over.
//  News carries Grok's answer in short beside the reports, and the Grokipedia article ends with
//  the way to what X is saying about it. All already holds everything.
//

import SwiftUI

/// Grok's answer in a few lines, for another tab. "Read it" goes to All, where the whole answer is.
struct AnswerDigest: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    private var shown: Bool {
        search.answer == .done || search.answer == .streaming
    }

    var body: some View {
        if shown, let text = Self.digest(search.answerText) {
            VStack(alignment: .leading, spacing: 10) {
                ModuleHeader(title: "Grok's answer", live: search.answer == .streaming, more: "Read it") { search.show(.all) }
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .transition(.rise)
        }
    }

    /// The answer's opening as plain words: no Markdown marks, no citations, about 420 letters.
    nonisolated static func digest(_ markdown: String) -> String? {
        var text = markdown.components(separatedBy: "---follow-ups---").first ?? markdown
        let replacements: [(String, String)] = [
            (#"\s*\[\[\d+\]\]\([^)]*\)"#, ""),       // [[1]](https://…), and the space before it
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),       // [words](https://…)
            (#"(?m)^#{1,6}[ \t]*"#, ""),             // headings
            (#"(?m)^[ \t]*[-*+][ \t]+"#, "• "),      // list items
            (#"\*\*|__|`"#, ""),                     // bold, code
            (#"(?<![\w*])\*(?!\s)([^*]+)\*"#, "$1"), // italics
            (#"[ \t]+"#, " "),
        ]
        for (pattern, template) in replacements {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "---" }
        guard !paragraphs.isEmpty else { return nil }
        var digest = ""
        for paragraph in paragraphs {
            if !digest.isEmpty, digest.count + paragraph.count > 420 { break }
            digest += (digest.isEmpty ? "" : "\n") + paragraph
        }
        if digest.count > 480 {
            let cut = digest.prefix(470)
            digest = (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
        }
        return digest
    }
}
