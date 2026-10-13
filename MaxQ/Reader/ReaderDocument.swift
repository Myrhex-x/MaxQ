//
//  ReaderDocument.swift
//  Max Q
//
//  Reader for any page: the article read out of the page (headings, paragraphs with their links,
//  lists, quotes, pictures with captions, code, small tables) and set the way Max Q sets a
//  Grokipedia article, so every article on the web reads the same: the serif, the measure, the
//  contents beside it, Listen, translation on this Mac, and questions to Grok.
//
//  The reading is done by a script in Max Q's isolated world (the page can't see it or interfere),
//  when the user asks for Reader, and a cheaper one after each page loads that only says whether
//  there's an article to read.
//

import Foundation

/// A page's article, as Reader sets it.
nonisolated struct ReaderDocument: Equatable, Sendable {
    let url: URL
    var title: String
    var byline: String?
    var site: String
    var published: Date?
    /// The page's language ("en", "fr").
    var language: String?
    var leadImage: URL?
    var article: GrokipediaArticle

    /// Reads what the extraction script returned.
    static func make(_ json: [String: Any], url: URL) -> ReaderDocument? {
        var blocks: [GrokipediaBlock] = []
        var number = 0
        var headingIDs = Set<String>()
        func next() -> Int { number += 1; return number }
        func runs(_ raw: Any?) -> [GrokipediaRun] {
            (raw as? [[String: Any]] ?? []).compactMap { item in
                guard let text = item["t"] as? String, !text.isEmpty else { return nil }
                var run = GrokipediaRun(text: text)
                if let href = item["href"] as? String, let link = URL(string: href), link.scheme == "https" || link.scheme == "http" {
                    run.kind = .link(link)
                }
                run.bold = item["b"] as? Bool ?? false
                run.italic = item["i"] as? Bool ?? false
                return run
            }
        }
        for block in json["blocks"] as? [[String: Any]] ?? [] {
            switch block["k"] as? String {
            case "h":
                guard let text = (block["t"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
                var id = slug(text)
                while headingIDs.contains(id) { id += "-\(next())" }
                headingIDs.insert(id)
                let level = min(max(block["l"] as? Int ?? 2, 2), 4)
                blocks.append(.heading(GrokipediaHeading(id: id, level: level, text: text)))
            case "p":
                let parts = runs(block["r"])
                if !parts.isEmpty { blocks.append(.paragraph(id: next(), runs: parts)) }
            case "q":
                let parts = runs(block["r"])
                if !parts.isEmpty { blocks.append(.quote(id: next(), runs: parts)) }
            case "ul", "ol":
                let items = (block["items"] as? [Any] ?? []).map(runs).filter { !$0.isEmpty }
                if !items.isEmpty { blocks.append(.list(id: next(), ordered: block["k"] as? String == "ol", items: items)) }
            case "img":
                guard let src = (block["src"] as? String).flatMap(URL.init(string:)), src.scheme == "https" || src.scheme == "http" else { continue }
                let width = (block["w"] as? NSNumber)?.doubleValue ?? 0, height = (block["h"] as? NSNumber)?.doubleValue ?? 0
                blocks.append(.figure(id: next(), image: src, caption: block["cap"] as? String ?? "",
                                      aspect: width > 0 && height > 0 ? width / height : nil))
            case "pre":
                if let text = block["t"] as? String, !text.isEmpty {
                    blocks.append(.quote(id: next(), runs: [GrokipediaRun(text: text)]))
                }
            case "table":
                let header = block["head"] as? [String] ?? []
                let rows = block["rows"] as? [[String]] ?? []
                if !rows.isEmpty { blocks.append(.table(id: next(), header: header, rows: rows)) }
            default:
                continue
            }
        }
        let words = blocks.reduce(0) { total, block in
            switch block {
            case .paragraph(_, let runs), .quote(_, let runs): total + runs.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            case .list(_, _, let items): total + items.flatMap { $0 }.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            default: total
            }
        }
        guard words >= 80 else { return nil }
        let host = url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        let published = (json["published"] as? String).flatMap { text -> Date? in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withFullDate]
            return formatter.date(from: String(text.prefix(10)))
        }
        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReaderDocument(url: url, title: title?.isEmpty == false ? title! : host,
                              byline: (json["byline"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(120)) },
                              site: (json["site"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? host,
                              published: published,
                              language: (json["lang"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(2)).lowercased() },
                              leadImage: (json["image"] as? String).flatMap(URL.init(string:)),
                              article: GrokipediaArticle(blocks: blocks, references: [], infobox: nil, wordCount: words))
    }

    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(8)
        let slug = words.joined(separator: "-")
        return slug.isEmpty ? "section" : String(slug.prefix(60))
    }
}

enum ReaderScripts {
    /// After a page loads: is there an article here worth Reader? Cheap: counts long paragraphs.
    nonisolated static let readerable = """
    try {
      if (!document.body || location.protocol.indexOf('http') !== 0) return false;
      var host = location.hostname;
      if (/(^|\\.)(google|bing|duckduckgo|x|twitter|facebook|instagram|youtube|reddit)\\./.test(host)) return false;
      var total = 0, count = 0, ps = document.querySelectorAll('article p, main p, [itemprop=articleBody] p, .post p, .entry-content p, .article p, p');
      for (var i = 0; i < ps.length && i < 400; i++) {
        var t = (ps[i].textContent || '').trim();
        if (t.length > 120) { total += t.length; count += 1; }
      }
      return count >= 3 && total >= 1400;
    } catch (e) { return false; }
    """

    /// Reads the page's article. Returns { title, byline, site, published, lang, image, blocks }.
    nonisolated static let extract = """
    var skipTags = { SCRIPT:1, STYLE:1, NOSCRIPT:1, NAV:1, ASIDE:1, FOOTER:1, FORM:1, BUTTON:1, SVG:1, IFRAME:1, HEADER:1, SELECT:1, INPUT:1, TEXTAREA:1 };
    var junk = /(comment|share|social|related|promo|advert|sponsor|newsletter|subscribe|cookie|banner|breadcrumb|footer|sidebar|widget|menu|popup|modal|recirc|outbrain|taboola|paywall|signup|nav)/i;
    function meta(names) {
      for (var i = 0; i < names.length; i++) {
        var el = document.querySelector('meta[property="' + names[i] + '"], meta[name="' + names[i] + '"]');
        if (el && el.content) return el.content.trim();
      }
      return '';
    }
    function hidden(el) {
      if (el.getAttribute && el.getAttribute('aria-hidden') === 'true') return true;
      var cs = window.getComputedStyle(el);
      return !cs || cs.display === 'none' || cs.visibility === 'hidden';
    }
    function isJunk(el) {
      var label = (el.className && el.className.baseVal === undefined ? el.className : '') + ' ' + (el.id || '') + ' ' + (el.getAttribute('role') || '');
      return junk.test(label) && !/(article|content|post|story|entry|body)/i.test(el.id || '');
    }
    function label(el) { return (typeof el.className === 'string' ? el.className : '') + ' ' + (el.id || ''); }
    function textLen(el) {
      var n = 0, ps = el.getElementsByTagName('p');
      for (var i = 0; i < ps.length; i++) { var t = (ps[i].textContent || '').trim().length; if (t > 40) n += t; }
      return n;
    }
    // Each paragraph counts for its parent, half for the grandparent, a third further up; the
    // best-scoring container is the article, grown to its parent while the parent holds much more
    // of the text (an article split into sections).
    function pickRoot() {
      var scores = new Map(), ps = document.getElementsByTagName('p');
      for (var i = 0; i < ps.length; i++) {
        var len = (ps[i].textContent || '').trim().length;
        if (len < 40) continue;
        var node = ps[i].parentElement, share = 1;
        for (var d = 0; d < 3 && node && node !== document.body; d++) {
          scores.set(node, (scores.get(node) || 0) + len * share);
          share = d === 0 ? 0.5 : 0.33;
          node = node.parentElement;
        }
      }
      var best = null, bestScore = 0;
      scores.forEach(function (s, el) {
        var l = label(el);
        if (/(article|content|entry|post|story|body|main|text)/i.test(l)) s *= 1.25;
        if (junk.test(l)) s *= 0.2;
        if (s > bestScore) { bestScore = s; best = el; }
      });
      if (!best) {
        // No paragraphs: the container with the most text of its own (pages set with line breaks).
        var all = document.querySelectorAll('div, td, section, article, main'), most = 0;
        for (var k = 0; k < all.length && k < 4000; k++) {
          var own = 0;
          for (var c = 0; c < all[k].childNodes.length; c++) if (all[k].childNodes[c].nodeType === 3) own += all[k].childNodes[c].nodeValue.trim().length;
          if (own > most) { most = own; best = all[k]; }
        }
        return most > 400 ? best : null;
      }
      while (best.parentElement && best.parentElement !== document.body && best.parentElement !== document.documentElement) {
        var mine = textLen(best), theirs = textLen(best.parentElement);
        if (theirs >= mine * 1.5 && !junk.test(label(best.parentElement))) best = best.parentElement; else break;
      }
      return best;
    }
    var root = document.querySelector('[itemprop="articleBody"]');
    var picked = pickRoot();
    if (!root || (picked && textLen(picked) > textLen(root) * 1.5)) root = picked;
    if (!root) return null;
    var blocks = [], seenText = 0;
    // Words only: the text of an element without its styles, scripts or citation marks.
    function cleanText(el) {
      var out = '';
      (function walk(node) {
        if (node.nodeType === 3) { out += node.nodeValue; return; }
        if (node.nodeType !== 1 || node.tagName === 'STYLE' || node.tagName === 'SCRIPT' || node.tagName === 'NOSCRIPT') return;
        if (node.tagName === 'SUP' && /^\\[?\\w{0,3}\\]?$/.test((node.textContent || '').trim())) return;
        if (/(^| )(mw-editsection|reference)( |$)/.test(typeof node.className === 'string' ? node.className : '')) return;
        for (var c = 0; c < node.childNodes.length; c++) walk(node.childNodes[c]);
      })(el);
      return out.replace(/\\s+/g, ' ').trim();
    }
    // The page's own heading when the shared title is that plus the site's name ("Starship - Wikipedia").
    var shared = meta(['og:title', 'twitter:title']) || document.title || '';
    var h1 = document.querySelector('h1');
    var heading = h1 ? cleanText(h1) : '';
    var title = (heading && (!shared || shared.indexOf(heading) === 0)) ? heading : (shared || heading);
    title = title.trim();
    function runsOf(el) {
      var out = [];
      function walk(node, b, i, href) {
        if (node.nodeType === 3) {
          var t = node.nodeValue.replace(/\\s+/g, ' ');
          if (t) out.push({ t: t, b: b, i: i, href: href || undefined });
          return;
        }
        if (node.nodeType !== 1 || skipTags[node.tagName]) return;
        if (node.tagName === 'BR') { out.push({ t: ' ' }); return; }
        if (node.tagName === 'SUP' && /^\\[?\\w{0,3}\\]?$/.test((node.textContent || '').trim())) return;
        if (/(^| )(mw-editsection|reference)( |$)/.test(typeof node.className === 'string' ? node.className : '')) return;
        var nb = b || node.tagName === 'STRONG' || node.tagName === 'B';
        var ni = i || node.tagName === 'EM' || node.tagName === 'I';
        var nh = href;
        if (node.tagName === 'A' && node.href && /^https?:/.test(node.href)) nh = node.href;
        for (var k = 0; k < node.childNodes.length; k++) walk(node.childNodes[k], nb, ni, nh);
      }
      walk(el, false, false, null);
      // Trim the edges.
      while (out.length && !out[0].t.trim()) out.shift();
      while (out.length && !out[out.length - 1].t.trim()) out.pop();
      if (out.length) { out[0].t = out[0].t.replace(/^\\s+/, ''); out[out.length - 1].t = out[out.length - 1].t.replace(/\\s+$/, ''); }
      return out;
    }
    function imageOf(img) {
      var src = img.currentSrc || img.src || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || '';
      if (!/^https?:/.test(src)) return null;
      var w = img.naturalWidth || parseInt(img.getAttribute('width') || '0', 10);
      var h = img.naturalHeight || parseInt(img.getAttribute('height') || '0', 10);
      if (w && w < 200) return null;
      return { src: src, w: w, h: h };
    }
    function visit(el) {
      if (blocks.length > 600) return;
      if (el.nodeType !== 1 || skipTags[el.tagName]) return;
      if (el !== root && (isJunk(el) || hidden(el))) return;
      var tag = el.tagName;
      if (/^H[1-4]$/.test(tag)) {
        var text = cleanText(el);
        if (text && text !== title && text.length < 200) blocks.push({ k: 'h', l: tag === 'H1' ? 2 : parseInt(tag[1], 10), t: text });
        return;
      }
      if (tag === 'P') {
        var r = runsOf(el), len = r.reduce(function (n, x) { return n + x.t.length; }, 0);
        if (len >= 20) { blocks.push({ k: 'p', r: r }); seenText += len; }
        var inner = el.querySelector('img');
        if (inner) { var im = imageOf(inner); if (im) blocks.push({ k: 'img', src: im.src, w: im.w, h: im.h, cap: inner.alt || '' }); }
        return;
      }
      if (tag === 'UL' || tag === 'OL') {
        var items = [];
        for (var i = 0; i < el.children.length; i++) {
          if (el.children[i].tagName === 'LI') { var ri = runsOf(el.children[i]); if (ri.length) items.push(ri); }
        }
        if (items.length && items.length <= 60) blocks.push({ k: tag === 'OL' ? 'ol' : 'ul', items: items });
        return;
      }
      if (tag === 'BLOCKQUOTE') {
        var rq = runsOf(el);
        if (rq.length) blocks.push({ k: 'q', r: rq });
        return;
      }
      if (tag === 'PRE') {
        var code = (el.textContent || '').trim();
        if (code) blocks.push({ k: 'pre', t: code.slice(0, 4000) });
        return;
      }
      if (tag === 'FIGURE' || tag === 'PICTURE' || tag === 'IMG') {
        var img = tag === 'IMG' ? el : el.querySelector('img');
        if (img) {
          var image = imageOf(img);
          var cap = el.querySelector && el.querySelector('figcaption');
          if (image) blocks.push({ k: 'img', src: image.src, w: image.w, h: image.h, cap: (cap ? cleanText(cap) : (img.alt || '')).trim() });
        }
        return;
      }
      if (tag === 'TABLE') {
        var rows = [], head = [];
        var trs = el.querySelectorAll('tr');
        for (var t = 0; t < trs.length && rows.length < 30; t++) {
          var cells = Array.prototype.map.call(trs[t].children, function (c) { return cleanText(c); });
          if (!cells.length) continue;
          if (!head.length && trs[t].querySelector('th')) head = cells; else rows.push(cells);
        }
        if (rows.length && rows.length <= 30) blocks.push({ k: 'table', head: head, rows: rows });
        return;
      }
      if (!el.querySelector('p, div, ul, ol, table, h1, h2, h3, h4, figure, blockquote, pre, section, article')) {
        // A block of text set with line breaks rather than paragraphs: split at blank lines.
        var parts = [], current = [], lastBreak = false;
        (function walkLeaf(node, b, i, href) {
          for (var c = 0; c < node.childNodes.length; c++) {
            var child = node.childNodes[c];
            if (child.nodeType === 3) {
              var t = child.nodeValue.replace(/\\s+/g, ' ');
              if (t.trim()) { current.push({ t: t, b: b, i: i, href: href || undefined }); lastBreak = false; }
            } else if (child.nodeType === 1 && !skipTags[child.tagName]) {
              if (child.tagName === 'BR') {
                if (lastBreak && current.length) { parts.push(current); current = []; }
                lastBreak = true;
              } else {
                walkLeaf(child, b || child.tagName === 'B' || child.tagName === 'STRONG', i || child.tagName === 'I' || child.tagName === 'EM',
                         child.tagName === 'A' && /^https?:/.test(child.href) ? child.href : href);
              }
            }
          }
        })(el, false, false, null);
        if (current.length) parts.push(current);
        for (var q = 0; q < parts.length; q++) {
          var len = parts[q].reduce(function (n, x) { return n + x.t.length; }, 0);
          if (len >= 20) { parts[q][0].t = parts[q][0].t.replace(/^\\s+/, ''); blocks.push({ k: 'p', r: parts[q] }); }
        }
        return;
      }
      for (var j = 0; j < el.children.length; j++) visit(el.children[j]);
    }
    visit(root);
    var byline = meta(['author', 'article:author', 'parsely-author', 'sailthru.author']);
    if (!byline) { var by = document.querySelector('[rel="author"], [itemprop="author"], .byline, .author-name, .author'); if (by) byline = (by.textContent || '').replace(/\\s+/g, ' ').trim(); }
    var published = meta(['article:published_time', 'og:article:published_time', 'datePublished', 'pubdate', 'date']);
    if (!published) { var time = document.querySelector('time[datetime]'); if (time) published = time.getAttribute('datetime'); }
    return {
      title: title,
      byline: byline.slice(0, 120),
      site: meta(['og:site_name', 'application-name']),
      published: published || '',
      lang: (document.documentElement.lang || '').slice(0, 5),
      image: meta(['og:image', 'twitter:image']),
      blocks: blocks
    };
    """
}
