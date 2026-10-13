//
//  BotEmailAutofill.swift
//  Max Q
//
//  Offers the Grok Bot's own inbox (on mail.grokbot.com) under email fields, the way Hide My Email
//  offers a relay address: click into a sign-up form's email field and a suggestion appears under
//  it; pick it (or press Down, then Return) and the field is filled, so the codes and receipts go
//  to the Bot instead of your own inbox.
//
//  How it works: a small script in Max Q's isolated content world (the page can't see, call or fake
//  it) notices when an email field gets focus and reports where the field is. Max Q draws the
//  suggestion in its own panel over the page, never inside the page, and fills the field only when
//  the user picks it. Nothing is filled automatically, and the address never leaves this Mac except
//  into the field the user chose.
//

import AppKit
import SwiftUI
import WebKit

@MainActor
final class BotEmailAutofill: NSObject, WKScriptMessageHandler {
    static let shared = BotEmailAutofill()
    nonisolated static let handlerName = "maxqBotEmail"

    /// The field the suggestion is showing for.
    private struct Target {
        weak var webView: MaxQWebView?
        let frame: WKFrameInfo
        let fieldID: Int
        /// The field in screen coordinates.
        var rect: NSRect
    }

    private var target: Target?
    private var panel: NSPanel?
    private let presentation = SuggestionPresentation()
    private var hideTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private var settings: AppSettings { AppSettings.shared }

    /// Adds the field watcher to a tab's web view configuration.
    static func install(in configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(source: watcherScript, injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: false, in: .defaultClient))
        controller.add(shared, contentWorld: .defaultClient, name: handlerName)
    }

    /// Whether there's anything to offer: the address, or (with Grok Bot installed) setting it up.
    private var offering: Bool {
        guard settings.botEmailSuggestions else { return false }
        return settings.botEmailIsValid || GrokBot.isInstalled
    }

    // MARK: - Messages from the page

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView as? MaxQWebView,
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "focus", "input", "move":
            guard offering, let id = body["id"] as? Int, body["positioned"] as? Bool == true,
                  let rect = screenRect(of: body, in: webView) else {
                hide()
                return
            }
            let value = (body["value"] as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let address = settings.botEmail.trimmingCharacters(in: .whitespaces).lowercased()
            // Typing something else (your own address) puts the suggestion away; typing the start
            // of the Bot's keeps it.
            if !value.isEmpty, address.isEmpty || !address.hasPrefix(value) || value == address {
                hide()
                return
            }
            if type == "move", target == nil { return }
            show(Target(webView: webView, frame: message.frameInfo, fieldID: id, rect: rect))
        case "blur":
            hideSoon()
        case "dismiss":
            hide()
        case "arm":
            if target != nil { presentation.armed = true }
        case "disarm":
            presentation.armed = false
        case "accept":
            if target != nil { accept() }
        default:
            break
        }
    }

    /// The field's rectangle on screen, from its CSS-pixel rectangle in the page.
    private func screenRect(of body: [String: Any], in webView: WKWebView) -> NSRect? {
        guard let window = webView.window,
              let x = (body["x"] as? NSNumber)?.doubleValue, let y = (body["y"] as? NSNumber)?.doubleValue,
              let w = (body["w"] as? NSNumber)?.doubleValue, let h = (body["h"] as? NSNumber)?.doubleValue,
              w > 1, h > 1 else { return nil }
        let scale = webView.pageZoom * webView.magnification
        var rect = NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
        // Off the visible part of the page: nothing to point at.
        guard rect.maxY > 0, rect.minY < webView.bounds.height, rect.maxX > 0, rect.minX < webView.bounds.width else { return nil }
        if !webView.isFlipped { rect.origin.y = webView.bounds.height - rect.maxY }
        return window.convertToScreen(webView.convert(rect, to: nil))
    }

    // MARK: - The suggestion

    private func show(_ new: Target) {
        hideTask?.cancel()
        let sameField = target?.fieldID == new.fieldID && target?.webView === new.webView
        target = new
        guard let webView = new.webView, let window = webView.window else { return }
        if !sameField { presentation.armed = false; presentation.filled = false }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        presentation.colorScheme = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        panel.appearance = window.effectiveAppearance

        let width = min(max(new.rect.width, 300), 380)
        let content = SuggestionRoot(presentation: presentation, width: width,
                                     address: settings.botEmailIsValid ? settings.botEmail : nil,
                                     botIcon: GrokBot.appIcon,
                                     pick: { [weak self] in self?.accept() },
                                     turnOff: { [weak self] in
                                         self?.settings.botEmailSuggestions = false
                                         self?.hide()
                                     })
        let hosting = SuggestionHostingView(rootView: content)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        // Under the field, its leading edges lined up; above it when there's no room below.
        let margin = SuggestionRoot.margin
        var origin = NSPoint(x: new.rect.minX - margin, y: new.rect.minY - 6 - size.height + margin)
        presentation.above = false
        if let visible = window.screen?.visibleFrame {
            if origin.y + margin < visible.minY {
                origin.y = new.rect.maxY + 6 - margin
                presentation.above = true
            }
            origin.x = min(max(origin.x, visible.minX - margin + 4), visible.maxX - size.width + margin - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        let wasVisible = panel.isVisible && presentation.shown
        panel.orderFront(nil)
        if !wasVisible {
            presentation.shown = false
            DispatchQueue.main.async { [presentation] in
                withAnimation(Motion.outQuint(0.2)) { presentation.shown = true }
            }
            setPageFlag(true)
        }
        observe(window)
    }

    /// Lets the page's watcher know the suggestion is up, so Down and Return reach it.
    private func setPageFlag(_ shown: Bool) {
        guard let target, let webView = target.webView else { return }
        let frame = target.frame
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "var s = window.__maxqBotFill; if (s) { s.shown = shown; if (!shown) s.armed = false; } return true;",
                arguments: ["shown": shown], in: frame, contentWorld: .defaultClient)
        }
    }

    private func hideSoon() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        guard let panel, panel.isVisible else { target = nil; return }
        setPageFlag(false)
        target = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        withAnimation(Motion.accelerate(0.12)) { presentation.shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self, self.target == nil else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func observe(_ window: NSWindow) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            })
        }
    }

    /// The tab's page changed or the tab left the screen.
    func pageChanged(in webView: WKWebView) {
        if target?.webView === webView { hide() }
    }

    // MARK: - Filling

    private func accept() {
        guard let target, let webView = target.webView else { return }
        guard settings.botEmailIsValid else {
            // Grok Bot is installed but its address isn't saved yet: ask for it, then fill.
            let pending = (webView: webView, frame: target.frame, id: target.fieldID)
            hide()
            (webView.menuHandler as? TabController)?.tab?.browser?.botEmailSetup = BotEmailSetup { [weak self] in
                self?.fill(webView: pending.webView, frame: pending.frame, id: pending.id)
            }
            return
        }
        presentation.filled = true
        fill(webView: webView, frame: target.frame, id: target.fieldID)
        // The envelope turns into a check, then the suggestion goes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in self?.hide() }
    }

    private func fill(webView: WKWebView, frame: WKFrameInfo, id: Int) {
        let address = settings.botEmail.trimmingCharacters(in: .whitespaces)
        Task {
            _ = try? await webView.callAsyncJavaScript(Self.fillScript, arguments: ["id": id, "email": address],
                                                       in: frame, contentWorld: .defaultClient)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = SuggestionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }

    // MARK: - Scripts

    /// Watches for email fields getting focus. Runs in Max Q's isolated world, in every frame;
    /// reports a field's position in the top page when every frame above it is same-origin.
    nonisolated static let watcherScript = """
    (function () {
      if (window.__maxqBotFill) return;
      var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.maxqBotEmail;
      if (!handler) return;
      var S = window.__maxqBotFill = { ids: new WeakMap(), refs: new Map(), next: 1, current: null, shown: false,
                                       armed: false, raf: 0, timer: 0, last: '', userAt: 0 };
      var HINT = /e-?mail|courriel|correo|e-?post/i;
      function isEmailField(el) {
        if (!el || el.tagName !== 'INPUT' || el.disabled || el.readOnly) return false;
        var type = (el.getAttribute('type') || 'text').toLowerCase();
        if (type === 'email') return true;
        if (type !== 'text') return false;
        var ac = (el.getAttribute('autocomplete') || '').toLowerCase();
        if (/(^|\\s)email(\\s|$)/.test(ac)) return true;
        return HINT.test([el.name, el.id, el.getAttribute('placeholder'), el.getAttribute('aria-label')].join(' '));
      }
      function idFor(el) {
        var id = S.ids.get(el);
        if (!id) { id = S.next++; S.ids.set(el, id); S.refs.set(id, new WeakRef(el)); }
        return id;
      }
      function offset() {
        var x = 0, y = 0, w = window;
        try {
          while (w !== w.top) {
            var fe = w.frameElement;
            if (!fe) return null;
            var r = fe.getBoundingClientRect(), cs = w.parent.getComputedStyle(fe);
            x += r.left + parseFloat(cs.borderLeftWidth) + parseFloat(cs.paddingLeft);
            y += r.top + parseFloat(cs.borderTopWidth) + parseFloat(cs.paddingTop);
            w = w.parent;
          }
        } catch (e) { return null; }
        return { x: x, y: y };
      }
      function geometry(el) {
        var r = el.getBoundingClientRect(), o = offset(), vx = 0, vy = 0;
        // Pinch-zoomed, the visible part of the page is panned within it.
        try { var vv = window.top.visualViewport; if (vv) { vx = vv.offsetLeft; vy = vv.offsetTop; } } catch (e) {}
        return { x: r.left + (o ? o.x : 0) - vx, y: r.top + (o ? o.y : 0) - vy, w: r.width, h: r.height, positioned: !!o };
      }
      function report(type, el) {
        var g = geometry(el);
        S.last = [g.x, g.y, g.w, g.h].map(Math.round).join(',');
        handler.postMessage({ type: type, id: idFor(el), x: g.x, y: g.y, w: g.w, h: g.h, positioned: g.positioned,
                              value: String(el.value || '').slice(0, 320) });
      }
      // Pages move fields around as they finish loading; follow the field while it has focus.
      function watch() {
        clearInterval(S.timer);
        S.timer = setInterval(function () {
          if (!S.current || !S.current.isConnected) {
            clearInterval(S.timer);
            // The field went away (a single-page form moved on): put the suggestion away too.
            if (S.current) { S.current = null; S.armed = false; handler.postMessage({ type: 'blur' }); }
            return;
          }
          var g = geometry(S.current), key = [g.x, g.y, g.w, g.h].map(Math.round).join(',');
          if (key !== S.last) report('move', S.current);
        }, 250);
      }
      // Only focus the user gave: a click or a key, not a page focusing its own field on load.
      function userJustActed() { return Date.now() - S.userAt < 1200; }
      ['mousedown', 'pointerdown', 'keydown', 'touchstart'].forEach(function (name) {
        window.addEventListener(name, function (e) { if (e.isTrusted) S.userAt = Date.now(); }, true);
      });
      document.addEventListener('focusin', function (e) {
        if (isEmailField(e.target) && userJustActed()) {
          S.current = e.target; S.armed = false; report('focus', e.target); watch();
        }
      }, true);
      document.addEventListener('focusout', function (e) {
        if (e.target === S.current) {
          S.current = null; S.armed = false; clearInterval(S.timer);
          handler.postMessage({ type: 'blur' });
        }
      }, true);
      document.addEventListener('mousedown', function (e) {
        var el = e.target;
        if (e.isTrusted && isEmailField(el) && document.activeElement === el) {
          S.current = el;
          setTimeout(function () { report('focus', el); watch(); }, 0);
        }
      }, true);
      document.addEventListener('input', function (e) {
        if (e.isTrusted && e.target === S.current) { S.armed = false; report('input', e.target); }
      }, true);
      // Only the user's own keys can pick the suggestion: a page can't press Down and Return for them.
      document.addEventListener('keydown', function (e) {
        if (!e.isTrusted || !S.current || !S.shown) return;
        if (e.key === 'Escape') { handler.postMessage({ type: 'dismiss' }); return; }
        if (e.key === 'ArrowDown' && !S.armed) { S.armed = true; e.preventDefault(); handler.postMessage({ type: 'arm' }); return; }
        if (e.key === 'ArrowUp' && S.armed) { S.armed = false; e.preventDefault(); handler.postMessage({ type: 'disarm' }); return; }
        if (e.key === 'Enter' && S.armed) { S.armed = false; e.preventDefault(); e.stopPropagation(); handler.postMessage({ type: 'accept' }); }
      }, true);
      function moved() {
        if (!S.current) return;
        cancelAnimationFrame(S.raf);
        S.raf = requestAnimationFrame(function () { if (S.current) report('move', S.current); });
      }
      window.addEventListener('scroll', moved, true);
      window.addEventListener('resize', moved);
    })();
    """

    /// Fills the field the suggestion was for. Arguments: `id`, `email`. Uses the input's own value
    /// setter plus input and change events, so React and similar frameworks see the change.
    nonisolated static let fillScript = """
    var S = window.__maxqBotFill;
    var ref = S && S.refs.get(id), el = ref && ref.deref();
    if (!el || !el.isConnected) return false;
    el.focus();
    var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(el, email);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    S.shown = false; S.armed = false;
    return true;
    """
}

/// Asks for the Bot's address the first time its suggestion is picked, then fills the field.
struct BotEmailSetup: Identifiable {
    let id = UUID()
    let fill: () -> Void
}

// MARK: - Panel

private final class SuggestionPanel: NSPanel {
    // Never takes keyboard focus: the field keeps it while the suggestion is up.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SuggestionHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@Observable
private final class SuggestionPresentation {
    var shown = false
    var above = false
    var armed = false
    var filled = false
    var colorScheme: ColorScheme = .dark
}

/// The suggestion: grok.com's menu card holding one row, the Bot's icon (or an envelope), "Use your
/// Grok Bot's email" and the address. It grows from the field like a SpaceXAI menu.
private struct SuggestionRoot: View {
    static let margin: CGFloat = 24

    let presentation: SuggestionPresentation
    let width: CGFloat
    let address: String?
    let botIcon: NSImage?
    let pick: () -> Void
    let turnOff: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: pick) {
                HStack(spacing: 12) {
                    ZStack {
                        if presentation.filled {
                            Icon(.check, size: 16, weight: 2.2)
                                .foregroundStyle(Theme.success)
                                .transition(.glyphSwap)
                        } else if let botIcon {
                            Image(nsImage: botIcon).resizable().interpolation(.high)
                                .frame(width: 28, height: 28)
                                .transition(.glyphSwap)
                        } else {
                            Icon(.envelope, size: 17)
                                .foregroundStyle(Theme.textSecondary)
                                .transition(.glyphSwap)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .animation(Motion.spring(0.3), value: presentation.filled)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use your Grok Bot's email")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(address ?? String(localized: "Add its address once, then fill"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if presentation.armed {
                        KeyHint("↩")
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(presentation.armed || hovering ? Theme.selected : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            HStack(spacing: 4) {
                Text("Codes and receipts go to your Bot's inbox.")
                Spacer(minLength: 6)
                Button("Don't suggest", action: turnOff)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textQuaternary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 6)
        }
        .padding(6)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
        .animation(Motion.hover, value: hovering)
        .animation(Motion.standard(0.16), value: presentation.armed)
        .scaleEffect(presentation.shown ? 1 : 0.95, anchor: presentation.above ? .bottomLeading : .topLeading)
        .offset(y: presentation.shown ? 0 : (presentation.above ? 8 : -8))
        .opacity(presentation.shown ? 1 : 0)
        .padding(Self.margin)
        .environment(\.colorScheme, presentation.colorScheme)
    }
}
