//
//  PageScripts.swift
//  Max Q
//
//  JavaScript that Max Q runs in pages, always in response to something the user did (opening a
//  tab, pressing Summarize, choosing a context-menu item).
//
//  Every script runs in WebKit's isolated client content world (`.defaultClient`), never in the
//  page's own world: the page can't read Max Q's state, forge it, or override the DOM functions
//  these scripts rely on (getComputedStyle, getSelection). Values go in as typed arguments to
//  `callAsyncJavaScript`, so nothing is ever spliced into script source.
//

import Foundation
import WebKit

enum PageScripts {

    /// Runs a script body in Max Q's isolated world and returns its result.
    @MainActor
    static func run(_ body: String, arguments: [String: Any] = [:], in webView: WKWebView) async -> Any? {
        try? await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .defaultClient)
    }

    /// Human-visible text of the page, for Grok context. Skips the hidden-text tricks used for
    /// prompt injection (display:none, transparent, 1px, off-screen, tiny font, aria-hidden).
    /// Argument: `max`. Returns { title, url, text, selection }.
    nonisolated static let visibleText = """
    var skip = {SCRIPT:1, STYLE:1, NOSCRIPT:1, TEMPLATE:1, IFRAME:1, SVG:1, CANVAS:1, HEAD:1,
                META:1, LINK:1, OBJECT:1, EMBED:1, AUDIO:1, VIDEO:1, MAP:1};
    var cache = new Map();
    function hidden(el) {
      if (cache.has(el)) return cache.get(el);
      var h = false;
      try {
        if (el.getAttribute && el.getAttribute('aria-hidden') === 'true') h = true;
        else {
          var cs = window.getComputedStyle(el);
          if (cs) {
            if (cs.display === 'none' || cs.visibility === 'hidden' || cs.visibility === 'collapse') h = true;
            else if (parseFloat(cs.opacity) === 0) h = true;
            // Transparent text only: an alpha of 0 ("rgba(r, g, b, 0)", "rgb(r g b / 0)"), never
            // plain black, whose "rgb(0, 0, 0)" ends the same way.
            else if (cs.color === 'transparent' || /^rgba\\((?:[^,]+,){3}\\s*0(?:\\.0+)?\\s*\\)$/.test(cs.color) ||
                     /\\/\\s*0(?:\\.0+)?%?\\s*\\)$/.test(cs.color)) h = true;
            else {
              var fs = parseFloat(cs.fontSize);
              if (!isNaN(fs) && fs < 4) h = true;
              else if (cs.textIndent && parseFloat(cs.textIndent) < -500) h = true;
              else {
                var r = el.getBoundingClientRect();
                if (r.width <= 1 || r.height <= 1) h = true;
                else if (r.right < -1500 || r.bottom < -1500) h = true;
              }
            }
          }
        }
      } catch (e) {}
      cache.set(el, h);
      return h;
    }
    var sel = '';
    try { sel = String(window.getSelection() || '').slice(0, 4000); } catch (e) {}
    if (!document.body) return { title: document.title || '', url: location.href, text: '', selection: sel };
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        var p = node.parentElement;
        while (p) {
          if (skip[p.tagName]) return NodeFilter.FILTER_REJECT;
          if (hidden(p)) return NodeFilter.FILTER_REJECT;
          p = p.parentElement;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var out = [], total = 0, n, visited = 0, deadline = Date.now() + 1500;
    while ((n = walker.nextNode())) {
      if (((++visited) & 1023) === 0 && Date.now() > deadline) break;
      var t = n.nodeValue.replace(/\\s+/g, ' ').trim();
      if (t) { out.push(t); total += t.length + 1; if (total > max) break; }
    }
    return { title: (document.title || '').slice(0, 300), url: location.href,
             text: out.join(' ').slice(0, max), selection: sel };
    """

    /// Icon links the page declares. Returns [{href, rel, sizes, type}].
    nonisolated static let iconLinks = """
    return Array.from(document.querySelectorAll('link[rel]'))
      .filter(function (l) { return /icon/i.test(l.rel || ''); })
      .slice(0, 20)
      .map(function (l) { return { href: l.href || '', rel: (l.rel || '').toLowerCase(),
                                   sizes: l.getAttribute('sizes') || '', type: l.type || '' }; });
    """

    /// Captures the current selection and remembers where it is (in Max Q's isolated world), so a
    /// later "Replace" puts Grok's rewrite back in the same field. Argument: `token` (the page id).
    /// Returns { text, editable, isField, isEmailField }.
    nonisolated static let captureSelection = """
    var el = document.activeElement;
    var isField = !!(el && (el.tagName === 'TEXTAREA' ||
      (el.tagName === 'INPUT' && /^(text|search|email|url|tel|password|)$/i.test(el.type || ''))));
    var state = { token: token, el: null, start: 0, end: 0, range: null };
    var text = '', editable = false;
    if (isField && typeof el.selectionStart === 'number') {
      text = (el.value || '').substring(el.selectionStart, el.selectionEnd);
      state.el = el; state.start = el.selectionStart; state.end = el.selectionEnd;
      editable = !el.readOnly && !el.disabled;
    } else {
      var s = window.getSelection();
      text = s ? s.toString() : '';
      if (s && s.rangeCount > 0) {
        state.range = s.getRangeAt(0).cloneRange();
        var node = s.anchorNode && (s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement);
        if (node && node.isContentEditable) { editable = true; state.el = node; }
      }
      if (!editable && el && el.isContentEditable) { editable = true; state.el = el; }
    }
    window.__maxqSelection = state;
    var isEmail = !!(isField && ((el.type || '').toLowerCase() === 'email' ||
      /e-?mail/i.test((el.name || '') + ' ' + (el.id || '') + ' ' + (el.autocomplete || '') + ' ' + (el.placeholder || ''))));
    // Where the selection is in the window, so a card can open beside it.
    var box = null;
    try {
      var r = state.range ? state.range.getBoundingClientRect() : (el ? el.getBoundingClientRect() : null);
      if (r && (r.width > 0 || r.height > 0)) box = { x: r.left, y: r.top, w: r.width, h: r.height };
    } catch (e) {}
    return { text: text.slice(0, 8000), editable: editable, isField: isField, isEmailField: isEmail, rect: box };
    """

    /// Replaces the remembered selection with `text`, only if it was captured on this same page
    /// (`token`). Uses insertText so the page's undo stack and input events behave as if typed.
    nonisolated static let replaceSelection = """
    var s = window.__maxqSelection;
    if (!s || s.token !== token) return false;
    if (s.el && typeof s.el.selectionStart === 'number') {
      if (!s.el.isConnected) return false;
      s.el.focus();
      s.el.setSelectionRange(s.start, s.end);
      if (!document.execCommand('insertText', false, text)) {
        s.el.setRangeText(text, s.start, s.end, 'end');
        s.el.dispatchEvent(new Event('input', { bubbles: true }));
      }
      return true;
    }
    if (s.range) {
      if (s.el && s.el.focus) s.el.focus();
      var sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(s.range);
      return document.execCommand('insertText', false, text);
    }
    return false;
    """

    /// Types `text` into the focused or last right-clicked input. Uses the native value setter plus
    /// input/change events so React and similar frameworks register the change.
    nonisolated static let fillField = """
    var s = window.__maxqSelection;
    var el = (s && s.token === token && s.el && s.el.tagName === 'INPUT') ? s.el : document.activeElement;
    if (!el || el.tagName !== 'INPUT') return false;
    el.focus();
    var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(el, text);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
    """

    // MARK: - Page translation (DOM pass carried over from Searxly's translator)

    /// Walks visible text nodes, remembers each node and its original text, and returns the
    /// strings. Arguments: `token`, `maxNodes`, `maxCharacters`.
    nonisolated static let collectTranslatableText = """
    if (!document.body) return [];
    var S = window.__maxqTx = { token: token, nodes: [], originals: [], on: false };
    var SKIP = { SCRIPT:1, STYLE:1, NOSCRIPT:1, TEMPLATE:1, TEXTAREA:1, CODE:1, PRE:1, KBD:1, SAMP:1 };
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        var p = n.parentElement;
        if (!p || SKIP[p.nodeName]) return NodeFilter.FILTER_REJECT;
        if (p.isContentEditable) return NodeFilter.FILTER_REJECT;
        var t = n.nodeValue;
        if (!t || t.trim().length < 2) return NodeFilter.FILTER_SKIP;
        if (!/[\\p{L}]/u.test(t)) return NodeFilter.FILTER_SKIP;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var n, count = 0, chars = 0;
    while ((n = walker.nextNode()) && count < maxNodes && chars < maxCharacters) {
      S.nodes.push(n); S.originals.push(n.nodeValue);
      chars += n.nodeValue.length; count += 1;
    }
    return S.originals.map(function (t) { return t.trim(); });
    """

    /// Writes `[index, text]` pairs back into their nodes, keeping each node's original leading and
    /// trailing whitespace. Only applies to the page the strings came from (`token`).
    nonisolated static let applyTranslations = """
    var S = window.__maxqTx;
    if (!S || S.token !== token || !S.nodes.length) return 0;
    var applied = 0;
    for (var k = 0; k < pairs.length; k++) {
      var i = pairs[k][0], t = pairs[k][1];
      var node = S.nodes[i];
      if (!node || typeof t !== 'string' || !t.length || !node.isConnected) continue;
      var orig = S.originals[i] || '';
      var lead = (orig.match(/^\\s*/) || [''])[0], trail = (orig.match(/\\s*$/) || [''])[0];
      try { node.nodeValue = lead + t + trail; applied += 1; } catch (e) {}
    }
    if (applied > 0) S.on = true;
    return applied;
    """

    nonisolated static let restoreTranslation = """
    var S = window.__maxqTx;
    if (!S || !S.nodes) return false;
    for (var i = 0; i < S.nodes.length; i++) {
      try { S.nodes[i].nodeValue = S.originals[i]; } catch (e) {}
    }
    S.on = false;
    return true;
    """
}
