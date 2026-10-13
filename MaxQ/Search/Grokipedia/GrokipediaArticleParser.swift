//
//  GrokipediaArticleParser.swift
//  Max Q
//
//  Reads a whole Grokipedia article out of the page Max Q already downloads for the pad, so the
//  Grokipedia tab can set the article natively: its headings, paragraphs (with the links to other
//  articles and the numbered citations), figures with their captions, tables and lists, the
//  infobox, and the numbered sources at the end. Grokipedia pre-renders the article as plain HTML
//  ("zero client JS"), so this is reading markup, nothing more. Pure and unit-tested.
//

import Foundation

/// A whole article, as the Grokipedia tab sets it.
nonisolated struct GrokipediaArticle: Sendable, Equatable {
    var blocks: [GrokipediaBlock]
    var references: [GrokipediaReference]
    var infobox: GrokipediaInfobox?
    /// Words in the article's text, for the reading time.
    var wordCount: Int

    /// Minutes to read it, at 230 words a minute.
    var readingMinutes: Int { max(1, Int((Double(wordCount) / 230).rounded())) }

    /// The sections and subsections, in order, for the contents.
    var outline: [GrokipediaHeading] {
        blocks.compactMap { if case .heading(let heading) = $0 { heading } else { nil } }
    }
}

nonisolated struct GrokipediaHeading: Sendable, Equatable, Identifiable, Hashable {
    let id: String
    /// 2 for a section, 3 or 4 for a subsection.
    let level: Int
    let text: String
}

/// One run of a paragraph: plain, bold or italic text, a link, or a citation number.
nonisolated struct GrokipediaRun: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case text
        /// Another Grokipedia article, by its page name ("SpaceX", "Raptor_(rocket_engine)").
        case article(String)
        case link(URL)
        case citation(Int)
    }

    var text: String
    var kind: Kind = .text
    var bold = false
    var italic = false
}

nonisolated enum GrokipediaBlock: Sendable, Equatable, Identifiable {
    case heading(GrokipediaHeading)
    case paragraph(id: Int, runs: [GrokipediaRun])
    case figure(id: Int, image: URL, caption: String, aspect: Double?)
    case table(id: Int, header: [String], rows: [[String]])
    case list(id: Int, ordered: Bool, items: [[GrokipediaRun]])
    case quote(id: Int, runs: [GrokipediaRun])

    var id: String {
        switch self {
        case .heading(let heading): "h-" + heading.id
        case .paragraph(let id, _), .figure(let id, _, _, _), .table(let id, _, _), .list(let id, _, _), .quote(let id, _):
            "b-\(id)"
        }
    }
}

nonisolated struct GrokipediaReference: Sendable, Equatable, Identifiable {
    let number: Int
    let title: String
    let url: URL?
    /// The source's site, as Grokipedia prints it ("spacex.com").
    let site: String?
    var id: Int { number }
}

nonisolated struct GrokipediaInfobox: Sendable, Equatable {
    let title: String
    let image: URL?
    let caption: String?
    let facts: [KnowledgeFact]
}

nonisolated enum GrokipediaArticleParser {

    static func parse(_ html: String) -> GrokipediaArticle? {
        guard let body = articleBody(html) else { return nil }
        var parser = BlockReader(html: body)
        let blocks = parser.read()
        guard blocks.contains(where: { if case .paragraph = $0 { true } else { false } }) else { return nil }
        let words = blocks.reduce(0) { total, block in
            switch block {
            case .paragraph(_, let runs), .quote(_, let runs):
                total + runs.filter { if case .citation = $0.kind { false } else { true } }
                    .reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            case .list(_, _, let items):
                total + items.flatMap { $0 }.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            default:
                total
            }
        }
        return GrokipediaArticle(blocks: blocks, references: references(html), infobox: infobox(html), wordCount: words)
    }

    /// The article's own markup: from the article body to the citations.
    static func articleBody(_ html: String) -> String? {
        guard let marker = html.range(of: "<!-- Article body") ?? html.range(of: "class=\"article-body\"") else { return nil }
        let rest = html[marker.lowerBound...]
        let end = rest.range(of: "<!-- Citations")?.lowerBound
            ?? rest.range(of: "<section id=\"references\"")?.lowerBound
            ?? rest.index(rest.startIndex, offsetBy: min(rest.count, 600_000))
        return String(rest[..<end])
    }

    // MARK: - Blocks

    private struct BlockReader {
        let text: NSString
        var cursor = 0
        var nextID = 0

        init(html: String) { text = html as NSString }

        /// The block elements Grokipedia's article is made of, at any depth.
        private static let start = try! NSRegularExpression(
            pattern: #"<(span)\b[^>]*data-tts-block="true"[^>]*>|<(h[234])\b([^>]*)>|<(figure)\b[^>]*>|<(table)\b[^>]*>|<(ul|ol)\b[^>]*>|<(blockquote)\b[^>]*>"#,
            options: [.caseInsensitive])

        mutating func read() -> [GrokipediaBlock] {
            var blocks: [GrokipediaBlock] = []
            while cursor < text.length,
                  let match = Self.start.firstMatch(in: text as String, range: NSRange(location: cursor, length: text.length - cursor)) {
                // The element's name, from whichever alternative matched (group 3 is a heading's
                // attributes, not a name).
                let source = text
                let name = [1, 2, 4, 5, 6, 7].lazy.compactMap { index -> String? in
                    let range = match.range(at: index)
                    return range.location == NSNotFound ? nil : source.substring(with: range).lowercased()
                }.first ?? ""
                guard let end = Markup.closing(of: name, in: text, after: match.range.location + match.range.length) else {
                    cursor = match.range.location + match.range.length
                    continue
                }
                let inner = text.substring(with: NSRange(location: match.range.location + match.range.length,
                                                         length: end.location - match.range.location - match.range.length))
                let openTag = text.substring(with: match.range)
                cursor = end.location + end.length
                if let block = makeBlock(name, openTag: openTag, inner: inner) {
                    blocks.append(block)
                }
            }
            return blocks
        }

        private mutating func newID() -> Int {
            nextID += 1
            return nextID
        }

        private mutating func makeBlock(_ name: String, openTag: String, inner: String) -> GrokipediaBlock? {
            switch name {
            case "span":
                let runs = Inline.runs(inner)
                return Inline.isEmpty(runs) ? nil : .paragraph(id: newID(), runs: runs)
            case "h2", "h3", "h4":
                let title = Markup.plain(inner)
                guard !title.isEmpty else { return nil }
                let id = Markup.attribute("id", in: openTag) ?? Markup.slug(title)
                // Grokipedia's own furniture, never the article's.
                guard !["references-title", "contribute-title"].contains(id) else { return nil }
                return .heading(GrokipediaHeading(id: id, level: Int(name.dropFirst()) ?? 2, text: title))
            case "figure":
                guard let imgTag = Markup.firstTag("img", in: inner),
                      let source = Markup.attribute("src", in: imgTag),
                      let url = GrokipediaArticleClient.normalizeImageURL(source) else { return nil }
                let caption = Markup.firstElement("figcaption", in: inner).map(Markup.plain)
                    ?? Markup.attribute("alt", in: imgTag).map(Markup.decode) ?? ""
                var aspect: Double?
                if let width = Markup.attribute("width", in: imgTag).flatMap(Double.init),
                   let height = Markup.attribute("height", in: imgTag).flatMap(Double.init), height > 0 {
                    aspect = width / height
                }
                return .figure(id: newID(), image: url, caption: caption, aspect: aspect)
            case "table":
                let rows = Markup.elements("tr", in: inner).map { row in
                    Markup.elements("t[hd]", in: row).map(Markup.plain)
                }.filter { !$0.isEmpty }
                guard !rows.isEmpty else { return nil }
                let hasHeader = inner.range(of: "<th", options: .caseInsensitive) != nil
                return .table(id: newID(), header: hasHeader ? rows[0] : [], rows: hasHeader ? Array(rows.dropFirst()) : rows)
            case "ul", "ol":
                let items = Markup.elements("li", in: inner).map(Inline.runs).filter { !Inline.isEmpty($0) }
                guard !items.isEmpty else { return nil }
                return .list(id: newID(), ordered: name == "ol", items: items)
            case "blockquote":
                let runs = Inline.runs(inner)
                return Inline.isEmpty(runs) ? nil : .quote(id: newID(), runs: runs)
            default:
                return nil
            }
        }
    }

    // MARK: - Inline text

    enum Inline {
        private static let tag = try! NSRegularExpression(pattern: #"<(/?)([a-zA-Z0-9]+)\b([^>]*)>"#)

        /// A paragraph's runs: text with its bold and italic, links to other articles and to the
        /// web, and citation numbers (Grokipedia nests each one twice; it counts once).
        static func runs(_ html: String) -> [GrokipediaRun] {
            let text = html as NSString
            var runs: [GrokipediaRun] = []
            var bold = 0, italic = 0
            var link: GrokipediaRun.Kind?
            var cursor = 0

            func append(_ raw: String) {
                let decoded = Markup.decode(raw)
                guard !decoded.isEmpty else { return }
                let kind = link ?? .text
                if let last = runs.last, last.kind == kind, last.bold == (bold > 0), last.italic == (italic > 0) {
                    runs[runs.count - 1].text += decoded
                } else {
                    runs.append(GrokipediaRun(text: decoded, kind: kind, bold: bold > 0, italic: italic > 0))
                }
            }

            while cursor < text.length,
                  let match = tag.firstMatch(in: text as String, range: NSRange(location: cursor, length: text.length - cursor)) {
                append(text.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
                cursor = match.range.location + match.range.length
                let closing = match.range(at: 1).length > 0
                let name = text.substring(with: match.range(at: 2)).lowercased()
                let attributes = text.substring(with: match.range(at: 3))
                switch name {
                case "sup" where !closing:
                    // The whole citation group, balanced, read for its numbers.
                    let end = Markup.closing(of: "sup", in: text, after: cursor)
                    let group = end.map { text.substring(with: NSRange(location: cursor, length: $0.location - cursor)) } ?? ""
                    var seen = Set<Int>()
                    for number in Markup.citationNumbers(group) where seen.insert(number).inserted {
                        runs.append(GrokipediaRun(text: "\(number)", kind: .citation(number)))
                    }
                    if let end { cursor = end.location + end.length }
                case "strong", "b":
                    bold += closing ? -1 : 1
                case "em", "i":
                    italic += closing ? -1 : 1
                case "a":
                    if closing {
                        link = nil
                    } else if let href = Markup.attribute("href", in: attributes).map(Markup.decode) {
                        link = linkKind(href)
                    }
                case "br":
                    append("\n")
                default:
                    break
                }
                bold = max(0, bold)
                italic = max(0, italic)
            }
            if cursor < text.length { append(text.substring(from: cursor)) }
            return tidy(runs)
        }

        static func linkKind(_ href: String) -> GrokipediaRun.Kind? {
            if href.hasPrefix("/page/") {
                let page = String(href.dropFirst("/page/".count)).components(separatedBy: "#")[0]
                let decoded = page.removingPercentEncoding ?? page
                return decoded.isEmpty ? nil : .article(decoded)
            }
            if href.hasPrefix("#") { return nil }
            guard let url = URL(string: href), url.scheme == "https" || url.scheme == "http" else { return nil }
            if let host = url.host?.lowercased(), host == "grokipedia.com" || host == "www.grokipedia.com",
               url.path.hasPrefix("/page/") {
                return linkKind(url.path)
            }
            return .link(url)
        }

        /// Collapses whitespace across runs and trims the paragraph's ends.
        static func tidy(_ runs: [GrokipediaRun]) -> [GrokipediaRun] {
            var result: [GrokipediaRun] = []
            var lastWasSpace = true
            for var run in runs {
                if case .citation = run.kind {
                    result.append(run)
                    lastWasSpace = false
                    continue
                }
                var collapsed = ""
                for character in run.text {
                    if character == "\n" {
                        collapsed.append("\n")
                        lastWasSpace = true
                    } else if character.isWhitespace {
                        if !lastWasSpace { collapsed.append(" ") }
                        lastWasSpace = true
                    } else {
                        collapsed.append(character)
                        lastWasSpace = false
                    }
                }
                run.text = collapsed
                if !run.text.isEmpty { result.append(run) }
            }
            // No space just before a citation, and none at the end.
            for index in result.indices.reversed() {
                guard case .citation = result[index].kind, index > 0 else { continue }
                if case .citation = result[index - 1].kind { continue }
                while result[index - 1].text.hasSuffix(" ") { result[index - 1].text.removeLast() }
            }
            while let last = result.last, last.kind == .text || isLinkKind(last.kind), last.text.hasSuffix(" ") || last.text.hasSuffix("\n") {
                result[result.count - 1].text.removeLast()
                if result[result.count - 1].text.isEmpty { result.removeLast() }
            }
            return result.filter { !$0.text.isEmpty }
        }

        private static func isLinkKind(_ kind: GrokipediaRun.Kind) -> Bool {
            switch kind {
            case .article, .link: true
            default: false
            }
        }

        static func isEmpty(_ runs: [GrokipediaRun]) -> Bool {
            !runs.contains { run in
                if case .citation = run.kind { return false }
                return !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    // MARK: - Sources and infobox

    /// The numbered sources: `<li id="ref-N">` with the source's link and its site.
    static func references(_ html: String) -> [GrokipediaReference] {
        guard let start = html.range(of: "<section id=\"references\"") else { return [] }
        let section = String(html[start.lowerBound...].prefix(1_500_000))
        let text = section as NSString
        guard let item = try? NSRegularExpression(pattern: #"<li\b[^>]*id="ref-(\d+)"[^>]*>"#) else { return [] }
        var references: [GrokipediaReference] = []
        for match in item.matches(in: section, range: NSRange(location: 0, length: text.length)) {
            guard let number = Int(text.substring(with: match.range(at: 1))),
                  let end = Markup.closing(of: "li", in: text, after: match.range.location + match.range.length) else { continue }
            let inner = text.substring(with: NSRange(location: match.range.location + match.range.length,
                                                     length: end.location - match.range.location - match.range.length))
            var title = "", url: URL?
            if let anchor = Markup.firstTag("a", withClass: "ref-link", in: inner) {
                url = Markup.attribute("href", in: anchor.open).map(Markup.decode).flatMap(URL.init(string:))
                title = Markup.plain(anchor.inner)
            }
            if title.isEmpty {
                // A source without a link: its text, minus the number.
                title = Markup.plain(inner).replacingOccurrences(of: #"^\d+\s*↑?\s*"#, with: "", options: .regularExpression)
            }
            let site = Markup.firstElement("span", withClass: "type-hint", in: inner).map(Markup.plain)
            guard !title.isEmpty else { continue }
            if let url, !(url.scheme == "https" || url.scheme == "http") { continue }
            references.append(GrokipediaReference(number: number, title: title, url: url, site: site?.isEmpty == false ? site : url?.host))
        }
        return references
    }

    /// Grokipedia's infobox: the title band, the picture and its caption, the rows.
    static func infobox(_ html: String) -> GrokipediaInfobox? {
        guard let start = html.range(of: "<aside class=\"infobox") else { return nil }
        let rest = html[start.lowerBound...]
        guard let end = rest.range(of: "</aside>") else { return nil }
        let aside = String(rest[..<end.upperBound])
        let title = Markup.firstElement("span", in: aside).map(Markup.plain) ?? ""
        var image: URL?
        if let img = Markup.firstTag("img", in: aside), let source = Markup.attribute("src", in: img) {
            image = GrokipediaArticleClient.normalizeImageURL(source)
        }
        let caption = Markup.firstElement("figcaption", in: aside).map(Markup.plain)
        var facts: [KnowledgeFact] = []
        var seen = Set<String>()
        for row in Markup.elements("div", withClass: "ib-row", in: aside) {
            guard let label = Markup.firstElement("dt", in: row).map(Markup.plain), !label.isEmpty,
                  let valueHTML = Markup.firstElement("dd", in: row) else { continue }
            let lines = Markup.elements("li", in: valueHTML).map(Markup.plain).filter { !$0.isEmpty }
            let value = lines.isEmpty ? Markup.plain(valueHTML) : lines.joined(separator: "\n")
            guard !value.isEmpty, seen.insert(label.lowercased()).inserted else { continue }
            facts.append(KnowledgeFact(label: label, value: value))
        }
        guard !title.isEmpty || !facts.isEmpty else { return nil }
        return GrokipediaInfobox(title: title, image: image, caption: caption?.isEmpty == false ? caption : nil, facts: facts)
    }
}

// MARK: - Markup helpers

/// Small, forgiving tools for reading Grokipedia's well-formed HTML.
nonisolated enum Markup {
    /// Where the element opened just before `offset` closes: the matching `</name>`, counting the
    /// same elements opened inside it.
    static func closing(of name: String, in text: NSString, after offset: Int) -> NSRange? {
        guard let tag = tagPattern(name) else { return nil }
        var depth = 1
        var cursor = offset
        while cursor < text.length,
              let match = tag.firstMatch(in: text as String, range: NSRange(location: cursor, length: text.length - cursor)) {
            let opening = match.range(at: 1).length == 0
            let selfClosing = text.substring(with: match.range).hasSuffix("/>")
            if opening {
                if !selfClosing { depth += 1 }
            } else {
                depth -= 1
                if depth == 0 { return match.range }
            }
            cursor = match.range.location + match.range.length
        }
        return nil
    }

    nonisolated(unsafe) private static var patterns: [String: NSRegularExpression] = [:]
    private static let patternsLock = NSLock()

    /// `<name …>` and `</name>`, compiled once per name.
    private static func tagPattern(_ name: String) -> NSRegularExpression? {
        patternsLock.withLock {
            if let cached = patterns[name] { return cached }
            let compiled = try? NSRegularExpression(pattern: "<(/?)\(name)\\b[^>]*>", options: [.caseInsensitive])
            patterns[name] = compiled
            return compiled
        }
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for index in [2, 3] {
            if let range = Range(match.range(at: index), in: tag) { return String(tag[range]) }
        }
        return nil
    }

    static func firstTag(_ name: String, in html: String) -> String? {
        guard let range = html.range(of: "<\(name)\\b[^>]*>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(html[range])
    }

    /// The first `<name …class="…class…">` element: its opening tag and its inner markup.
    static func firstTag(_ name: String, withClass className: String, in html: String) -> (open: String, inner: String)? {
        elementsWithTags(name, withClass: className, in: html).first
    }

    static func firstElement(_ name: String, in html: String) -> String? {
        elementsWithTags(name, withClass: nil, in: html).first?.inner
    }

    static func firstElement(_ name: String, withClass className: String, in html: String) -> String? {
        elementsWithTags(name, withClass: className, in: html).first?.inner
    }

    /// Every `<name>` element's inner markup, outermost ones only. `name` may be a pattern ("t[hd]").
    static func elements(_ name: String, in html: String) -> [String] {
        elementsWithTags(name, withClass: nil, in: html).map(\.inner)
    }

    static func elements(_ name: String, withClass className: String, in html: String) -> [String] {
        elementsWithTags(name, withClass: className, in: html).map(\.inner)
    }

    private static func elementsWithTags(_ name: String, withClass className: String?, in html: String) -> [(open: String, inner: String)] {
        let text = html as NSString
        guard let open = try? NSRegularExpression(pattern: "<(\(name))\\b([^>]*)>", options: [.caseInsensitive]) else { return [] }
        var results: [(String, String)] = []
        var cursor = 0
        while cursor < text.length,
              let match = open.firstMatch(in: text as String, range: NSRange(location: cursor, length: text.length - cursor)) {
            let tagName = text.substring(with: match.range(at: 1))
            let attributes = text.substring(with: match.range(at: 2))
            let contentStart = match.range.location + match.range.length
            if let className, !(attribute("class", in: attributes)?.split(separator: " ").contains { $0 == className } ?? false) {
                cursor = contentStart
                continue
            }
            guard let end = closing(of: NSRegularExpression.escapedPattern(for: tagName), in: text, after: contentStart) else {
                cursor = contentStart
                continue
            }
            results.append((text.substring(with: match.range),
                            text.substring(with: NSRange(location: contentStart, length: end.location - contentStart))))
            cursor = end.location + end.length
        }
        return results
    }

    /// Every citation number in a `<sup>` group ("#ref-12" → 12).
    static func citationNumbers(_ html: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"#ref-(\d+)"#) else { return [] }
        let text = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: text.length)).compactMap {
            Int(text.substring(with: $0.range(at: 1)))
        }
    }

    /// The text of some markup: tags gone, entities decoded, whitespace collapsed.
    static func plain(_ html: String) -> String {
        let stripped = html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decode(stripped)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:!?%)])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "( ", with: "(")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode(_ text: String) -> String {
        WebSearchClient.decodeEntities(text)
    }

    /// An id for a heading that has none: its words, lowercased and joined by hyphens.
    static func slug(_ title: String) -> String {
        title.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
    }
}
