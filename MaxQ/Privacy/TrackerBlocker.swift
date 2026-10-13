//
//  TrackerBlocker.swift
//  Max Q
//
//  Blocks the trackers on Max Q's list in every tab, with WebKit's own content blocker: the rules
//  are compiled once and WebKit applies them before a request leaves, so a blocked tracker never
//  learns the page was visited. A small script in Max Q's own world notes which trackers a page
//  tried to load, for the shield in the toolbar. Sites the user lets through are left alone.
//

import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class TrackerBlocker: NSObject {
    static let shared = TrackerBlocker()

    /// Sites where trackers are let through ("example.com"), by the user's choice.
    private(set) var allowedSites: [String]

    @ObservationIgnored private var ruleList: WKContentRuleList?
    @ObservationIgnored private var controllers: [WeakController] = []
    @ObservationIgnored private var compiling = false
    @ObservationIgnored private var compileAgain = false

    static let handlerName = "maxqTrackers"
    private static let identifier = "maxq-trackers"
    private static let allowedKey = "trackerAllowedSites"

    private struct WeakController { weak var controller: WKUserContentController? }

    override private init() {
        allowedSites = UserDefaults.standard.stringArray(forKey: Self.allowedKey) ?? []
        super.init()
    }

    var enabled: Bool { AppSettings.shared.blockTrackers }

    /// Adds the rules and the counting script to a tab's configuration.
    func install(in configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        controllers.removeAll { $0.controller == nil }
        controllers.append(WeakController(controller: controller))
        if enabled, let ruleList { controller.add(ruleList) }
        controller.addUserScript(WKUserScript(source: Self.countingScript, injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true, in: .defaultClient))
        controller.add(self, contentWorld: .defaultClient, name: Self.handlerName)
        if ruleList == nil { compile() }
    }

    /// Compiles the rules (at launch, and whenever the sites let through change) and hands them to
    /// every open tab.
    func compile() {
        guard !compiling else { compileAgain = true; return }
        compiling = true
        let source = TrackerList.rules(allowing: allowedSites)
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: Self.identifier, encodedContentRuleList: source) { [weak self] list, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.compiling = false
                if let list {
                    self.ruleList = list
                    self.apply()
                } else if let error {
                    Log.app.error("Tracker rules didn't compile: \(error.localizedDescription, privacy: .public)")
                }
                if self.compileAgain {
                    self.compileAgain = false
                    self.compile()
                }
            }
        }
    }

    /// Puts the current rules on every open tab, or takes them off when blocking is off.
    func apply() {
        controllers.removeAll { $0.controller == nil }
        for weak in controllers {
            guard let controller = weak.controller else { continue }
            controller.removeAllContentRuleLists()
            if enabled, let ruleList { controller.add(ruleList) }
        }
    }

    // MARK: - Sites let through

    func isAllowed(_ host: String?) -> Bool {
        guard let site = Self.site(host) else { return false }
        return allowedSites.contains(site)
    }

    func setAllowed(_ allowed: Bool, for host: String?) {
        guard let site = Self.site(host) else { return }
        if allowed {
            guard !allowedSites.contains(site) else { return }
            allowedSites.append(site)
        } else {
            allowedSites.removeAll { $0 == site }
        }
        UserDefaults.standard.set(allowedSites, forKey: Self.allowedKey)
        compile()
    }

    func clearAllowed() {
        allowedSites = []
        UserDefaults.standard.removeObject(forKey: Self.allowedKey)
        compile()
    }

    /// The site a host belongs to, as the rules name it ("news.example.co.uk" → "example.co.uk").
    nonisolated static func site(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return DomainDisplay.split(host: host).registrable
    }

    // MARK: - What a page tried

    /// Notes the trackers a page loads, or tries to, from other sites: scripts, pixels and frames
    /// with a tracker's address, now and as the page adds more. Runs in Max Q's world.
    private static let countingScript: String = {
        let patterns = TrackerList.patterns.map { [$0.filter, $0.tracker.company] }
        let json = (try? JSONSerialization.data(withJSONObject: patterns)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        return """
        (() => {
          if (window.top !== window) return;
          const patterns = \(json).map(([source, company]) => [new RegExp(source, 'i'), company]);
          const page = location.hostname.replace(/^www\\./, '');
          const found = new Set();
          let sent = 0;
          const check = (address) => {
            if (!address || address.startsWith('data:')) return;
            let host = '';
            try { host = new URL(address, location.href).hostname; } catch (_) { return; }
            // A site's own trackers load as the site's own (and aren't blocked there).
            if (host === page || host.endsWith('.' + page) || page.endsWith('.' + host.replace(/^www\\./, ''))) return;
            for (const [pattern, company] of patterns) {
              if (pattern.test(address)) { found.add(company); return; }
            }
          };
          const scan = () => {
            document.querySelectorAll('script[src], img[src], iframe[src], link[href]').forEach((element) => check(element.src || element.href));
            if (found.size !== sent) {
              sent = found.size;
              try { window.webkit.messageHandlers.\(handlerName).postMessage({ trackers: Array.from(found) }); } catch (_) {}
            }
          };
          scan();
          let timer = null;
          const watch = new MutationObserver(() => {
            if (timer) return;
            timer = setTimeout(() => { timer = null; scan(); }, 800);
          });
          watch.observe(document.documentElement, { childList: true, subtree: true });
          setTimeout(() => watch.disconnect(), 30000);
        })();
        """
    }()
}

extension TrackerBlocker: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard message.frameInfo.isMainFrame,
                  let tab = (message.webView as? MaxQWebView)?.tab,
                  let body = message.body as? [String: Any],
                  let trackers = body["trackers"] as? [String] else { return }
            tab.trackers = Array(Set(trackers)).sorted().prefix(40).map { $0 }
        }
    }
}
