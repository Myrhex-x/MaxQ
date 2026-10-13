//
//  AgentScripts.swift
//  Max Q
//
//  What the agent sees of a page and how it acts on it. A snapshot numbers the page's links,
//  buttons, fields and menus (what someone could click or type into), nearest the screen first,
//  with their labels, and adds the text around what's on screen; Grok answers with an action on a
//  number. The actions are what a person would do: click, type, choose, scroll. Everything runs in
//  Max Q's isolated world: the page can't see the numbering or forge it, and every action shows on
//  the page as it happens.
//

import Foundation

enum AgentScripts {
    /// The words a control goes by: its accessible name, its label, its placeholder, its text.
    nonisolated private static let labelFunction = """
    function label(el) {
      var text = el.getAttribute('aria-label') || el.getAttribute('title') || '';
      if (!text && el.labels && el.labels.length) text = el.labels[0].textContent;
      if (!text && el.getAttribute('aria-labelledby')) {
        var by = document.getElementById(el.getAttribute('aria-labelledby'));
        if (by) text = by.textContent;
      }
      if (!text && el.placeholder) text = el.placeholder;
      if (!text) text = el.innerText || el.textContent || '';
      if (!text && el.tagName === 'INPUT' && /^(submit|button)$/i.test(el.type)) text = el.value;
      if (!text && el.querySelector) { var img = el.querySelector('img[alt]'); if (img) text = img.alt; }
      if (!text && el.name) text = el.name;
      return text.replace(/\\s+/g, ' ').trim().slice(0, 90);
    }
    """

    /// Numbers the page's controls and reads the text around the screen.
    /// Returns { url, title, scroll, more, elements, text }.
    nonisolated static let snapshot = labelFunction + """
    var refs = new Map();
    window.__maxqAgentRefs = refs;
    var hiddenCache = new Map();
    function hidden(el) {
      if (!el || el === document.body || el === document.documentElement) return false;
      if (hiddenCache.has(el)) return hiddenCache.get(el);
      var h = false;
      if (/^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|HEAD|svg)$/.test(el.tagName)) h = true;
      else if (el.getAttribute('aria-hidden') === 'true') h = true;
      else {
        var cs = getComputedStyle(el);
        if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) < 0.05 || parseFloat(cs.fontSize) < 4) h = true;
      }
      if (!h) h = hidden(el.parentElement);
      hiddenCache.set(el, h);
      return h;
    }
    function distance(r) {
      if (r.bottom < 0) return -r.bottom;
      if (r.top > innerHeight) return r.top - innerHeight;
      return 0;
    }

    // Controls, nearest the screen first, numbered top to bottom.
    var nodes = document.querySelectorAll('a[href], button, input, textarea, select, [role=button], [role=link], [role=tab], [role=menuitem], [role=option], [role=checkbox], [role=radio], [role=switch], [role=combobox], [role=searchbox], [role=textbox], [contenteditable=true], summary');
    var candidates = [];
    for (var i = 0; i < nodes.length && i < 4000; i++) {
      var el = nodes[i];
      if (el.disabled || (el.tagName === 'INPUT' && (el.type || '').toLowerCase() === 'hidden')) continue;
      var r = el.getBoundingClientRect();
      if (r.width < 2 || r.height < 2 || hidden(el)) continue;
      // A control inside another (a span with role=button inside a link) counts once.
      if (el.parentElement && el.parentElement.closest('a[href], button, [role=button]') && !/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)) continue;
      candidates.push({ el: el, rect: r, order: i, distance: distance(r) });
    }
    candidates.sort(function (a, b) { return a.distance - b.distance || a.order - b.order; });
    var chosen = candidates.slice(0, 140).sort(function (a, b) { return a.order - b.order; });
    var list = [];
    chosen.forEach(function (c, index) {
      var el = c.el, ref = index + 1;
      var type = (el.getAttribute('type') || '').toLowerCase();
      refs.set(ref, el);
      var role = el.getAttribute('role') || (el.tagName === 'A' ? 'link' : el.tagName === 'BUTTON' ? 'button' :
                 el.tagName === 'SELECT' ? 'menu' : el.tagName === 'TEXTAREA' || el.isContentEditable ? 'textbox' :
                 el.tagName === 'SUMMARY' ? 'button' :
                 el.tagName === 'INPUT' ? (['checkbox', 'radio', 'submit', 'button', 'file', 'range', 'date'].indexOf(type) >= 0 ? type : 'textbox') : el.tagName.toLowerCase());
      var item = { ref: ref, role: role, label: label(el), inView: c.distance === 0 };
      if (el.tagName === 'A') item.href = el.href.slice(0, 160);
      if (el.tagName === 'SELECT') {
        item.options = Array.prototype.slice.call(el.options, 0, 15).map(function (o) { return o.text.trim().slice(0, 40); });
        if (el.selectedIndex >= 0) item.value = el.options[el.selectedIndex].text.trim().slice(0, 40);
      } else if ((el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && type !== 'password') {
        item.value = (el.value || '').slice(0, 60);
      }
      if (type === 'checkbox' || type === 'radio') item.checked = !!el.checked;
      else if (el.getAttribute('aria-checked')) item.checked = el.getAttribute('aria-checked') === 'true';
      if (el.getAttribute('aria-expanded')) item.expanded = el.getAttribute('aria-expanded') === 'true';
      var hints = (el.getAttribute('autocomplete') || '') + ' ' + (el.name || '') + ' ' + (el.id || '');
      if (type === 'password' || /cc-|card|cvc|cvv|csc|iban|ssn|one-time-code|otp/i.test(hints)) item.sensitive = true;
      list.push(item);
    });

    // Text from half a screen above to two screens below, grouped by block.
    var lines = [], line = '', lastBlock = null, total = 0, seen = 0, node;
    var walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
    var low = -innerHeight * 0.5, high = innerHeight * 2.5;
    while ((node = walker.nextNode()) && total < 6000 && seen < 40000) {
      seen++;
      var t = node.nodeValue.replace(/\\s+/g, ' ').trim();
      if (!t) continue;
      var p = node.parentElement;
      if (!p || hidden(p)) continue;
      var pr = p.getBoundingClientRect();
      if (pr.width < 2 || pr.height < 2 || pr.bottom < low || pr.top > high) continue;
      var block = p.closest('p, li, h1, h2, h3, h4, h5, h6, td, th, dt, dd, blockquote, pre, figcaption, label, button, a, article, section, div');
      if (block !== lastBlock && line) { lines.push(line); line = ''; }
      lastBlock = block;
      line = line ? line + ' ' + t : t;
      total += t.length + 1;
    }
    if (line) lines.push(line);
    var height = Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0, 1);
    var room = Math.max(1, height - innerHeight);
    return { url: location.href, title: document.title, scroll: Math.min(100, Math.round(100 * scrollY / room)),
             more: scrollY + innerHeight * 2.5 < height, elements: list, text: lines.join('\\n') };
    """

    /// What a control is, for Max Q's safety checks before acting on it.
    /// Returns { label, role, tag, type, href, submits, searchy, sensitive } or null.
    nonisolated static let inspect = labelFunction + """
    var el = window.__maxqAgentRefs && window.__maxqAgentRefs.get(ref);
    if (!el || !el.isConnected) return null;
    var type = (el.getAttribute('type') || '').toLowerCase();
    var form = el.form || (el.closest ? el.closest('form') : null);
    var words = [el.name, el.id, el.placeholder, el.getAttribute('aria-label'), el.getAttribute('role'), type].join(' ');
    var searchy = type === 'search' || el.getAttribute('role') === 'searchbox' || /search|recherch|query|\\bq\\b/i.test(words) ||
                  !!(el.closest && el.closest('[role=search]'));
    if (form && !searchy) {
      var action = (form.getAttribute('action') || '').toLowerCase();
      searchy = form.getAttribute('role') === 'search' || /search|recherche/.test(action) ||
                !!form.querySelector('input[type=search], input[name=q], input[name=query], input[name=search_query], input[name=field-keywords]');
    }
    var submits = el.tagName === 'BUTTON' ? !!form && (type === '' || type === 'submit')
                : el.tagName === 'INPUT' ? /^(submit|image)$/.test(type) : false;
    var hints = (el.getAttribute('autocomplete') || '') + ' ' + (el.name || '') + ' ' + (el.id || '');
    return { label: label(el), role: el.getAttribute('role') || '', tag: el.tagName, type: type,
             href: el.tagName === 'A' ? el.href : '', submits: submits, searchy: searchy,
             sensitive: type === 'password' || /cc-|card|cvc|cvv|csc|iban|ssn|one-time-code|otp/i.test(hints) };
    """

    /// Shows where the agent is about to act: an outline around the element for a moment.
    nonisolated static let highlight = """
    var el = window.__maxqAgentRefs && window.__maxqAgentRefs.get(ref);
    if (!el || !el.isConnected) return false;
    el.scrollIntoView({ block: 'center', behavior: 'smooth' });
    await new Promise(function (r) { setTimeout(r, 280); });
    var r = el.getBoundingClientRect();
    var box = document.createElement('div');
    box.style.cssText = 'position:fixed;z-index:2147483647;pointer-events:none;border-radius:8px;' +
      'box-shadow:0 0 0 2px rgba(41,159,255,0.95),0 0 0 6px rgba(41,159,255,0.25);transition:opacity .3s;' +
      'left:' + (r.left - 3) + 'px;top:' + (r.top - 3) + 'px;width:' + (r.width + 6) + 'px;height:' + (r.height + 6) + 'px';
    document.documentElement.appendChild(box);
    setTimeout(function () { box.style.opacity = '0'; setTimeout(function () { box.remove(); }, 320); }, 900);
    return true;
    """

    /// Clicks element `ref` the way a pointer would.
    nonisolated static let click = """
    var el = window.__maxqAgentRefs && window.__maxqAgentRefs.get(ref);
    if (!el || !el.isConnected) return 'That element is gone. Read the page again.';
    el.scrollIntoView({ block: 'center' });
    var r = el.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
    var opts = { bubbles: true, cancelable: true, composed: true, view: window, clientX: x, clientY: y, button: 0 };
    try { el.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch (e) {}
    el.dispatchEvent(new MouseEvent('mousedown', opts));
    if (el.focus) el.focus();
    try { el.dispatchEvent(new PointerEvent('pointerup', opts)); } catch (e) {}
    el.dispatchEvent(new MouseEvent('mouseup', opts));
    el.click();
    return 'Clicked.';
    """

    /// Types `text` into element `ref` (replacing what's there), then presses Return when `submit`.
    nonisolated static let type = """
    var el = window.__maxqAgentRefs && window.__maxqAgentRefs.get(ref);
    if (!el || !el.isConnected) return 'That element is gone. Read the page again.';
    el.scrollIntoView({ block: 'center' });
    el.focus();
    if (el.isContentEditable) {
      document.execCommand('selectAll', false, null);
      document.execCommand('insertText', false, text);
    } else if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
      var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
      el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    } else {
      return 'That is not a field. Pick a text box.';
    }
    if (submit) {
      var key = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
      var go = el.dispatchEvent(new KeyboardEvent('keydown', key));
      el.dispatchEvent(new KeyboardEvent('keypress', key));
      el.dispatchEvent(new KeyboardEvent('keyup', key));
      if (go && el.form && el.tagName === 'INPUT') {
        try { el.form.requestSubmit(); } catch (e) { try { el.form.submit(); } catch (e2) {} }
      }
      return 'Typed it and pressed Return.';
    }
    return 'Typed it.';
    """

    /// Chooses `option` (its text or value) in the menu `ref`.
    nonisolated static let select = """
    var el = window.__maxqAgentRefs && window.__maxqAgentRefs.get(ref);
    if (!el || !el.isConnected) return 'That element is gone. Read the page again.';
    if (el.tagName !== 'SELECT') return 'That is not a menu. Click it to open it instead.';
    var wanted = String(option).trim().toLowerCase(), match = null;
    for (var i = 0; i < el.options.length && !match; i++) {
      var o = el.options[i];
      if (o.text.trim().toLowerCase() === wanted || o.value.toLowerCase() === wanted) match = o;
    }
    for (var j = 0; j < el.options.length && !match; j++) {
      if (el.options[j].text.toLowerCase().indexOf(wanted) >= 0) match = el.options[j];
    }
    if (!match) return 'There is no such option.';
    el.value = match.value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return 'Chose ' + match.text.trim() + '.';
    """

    nonisolated static let scroll = """
    var before = scrollY;
    window.scrollBy({ top: 0.8 * innerHeight * (down ? 1 : -1), behavior: 'smooth' });
    await new Promise(function (r) { setTimeout(r, 450); });
    return Math.abs(scrollY - before) < 4 ? (down ? 'Already at the bottom.' : 'Already at the top.') : 'Scrolled.';
    """

    nonisolated static let findText = """
    var found = window.find ? window.find(text, false, false, true) : false;
    if (!found) return 'Not on the page.';
    var sel = getSelection();
    if (sel && sel.rangeCount) {
      var r = sel.getRangeAt(0).getBoundingClientRect();
      window.scrollBy({ top: r.top - innerHeight / 3 });
    }
    return 'Found it and scrolled to it.';
    """

    /// The page as Grok reads it: where it is, the numbered controls, the text around the screen.
    static func describe(_ snapshot: [String: Any]) -> String {
        var lines = [
            "URL: \(snapshot["url"] as? String ?? "")",
            "Title: \(snapshot["title"] as? String ?? "")",
            "Scrolled \(snapshot["scroll"] as? Int ?? 0)% down" + ((snapshot["more"] as? Bool ?? false) ? "; the page goes on below." : "."),
            "",
            "Controls: [number] kind \"label\"",
        ]
        let elements = snapshot["elements"] as? [[String: Any]] ?? []
        if elements.isEmpty { lines.append("(none)") }
        for element in elements {
            guard let ref = element["ref"] as? Int else { continue }
            var line = "[\(ref)] \(element["role"] as? String ?? "") \"\(element["label"] as? String ?? "")\""
            if let href = element["href"] as? String, !href.isEmpty { line += " → \(href)" }
            if let value = element["value"] as? String, !value.isEmpty { line += " value=\"\(value)\"" }
            if let checked = element["checked"] as? Bool { line += checked ? " (checked)" : " (not checked)" }
            if let expanded = element["expanded"] as? Bool { line += expanded ? " (open)" : " (closed)" }
            if let options = element["options"] as? [String] { line += " options: " + options.joined(separator: " | ") }
            if element["sensitive"] as? Bool == true { line += " (password or payment field: you may not type here)" }
            if element["inView"] as? Bool == false { line += " (off screen)" }
            lines.append(line)
        }
        lines.append("")
        lines.append("Text around the screen:")
        lines.append(snapshot["text"] as? String ?? "")
        return lines.joined(separator: "\n")
    }
}
