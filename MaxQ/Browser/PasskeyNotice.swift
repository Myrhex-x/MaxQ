//
//  PasskeyNotice.swift
//  Max Q
//
//  Passkeys and security keys work in a WebKit browser only once Apple approves it as one (the
//  restricted com.apple.developer.web-browser.public-key-credential entitlement, granted per app
//  and developer team). A copy built from source doesn't have it, so a site's "Use a passkey" just
//  fails with the site's own vague error. In such a copy, a small script in each page notices when
//  the site asks for a passkey (not the quiet autofill check many sign-in pages make as they load)
//  and Max Q says what's going on. It changes nothing about the request itself. A copy Apple
//  approved never gets the script.
//

import Foundation
import Security
import WebKit

enum PasskeyNotice {
    nonisolated static let handlerName = "maxqPasskey"

    /// This copy may use passkeys on any site: Apple approved it as a browser.
    nonisolated static let passkeysAllowed: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.web-browser.public-key-credential" as CFString, nil)
        return (value as? Bool) == true
    }()

    /// Runs in the page's own world, the only place its calls can be seen, and only reports them.
    nonisolated static let source = """
    (() => {
      const credentials = navigator.credentials;
      if (!credentials) return;
      const report = () => { try { window.webkit.messageHandlers.\(handlerName).postMessage('passkey'); } catch (_) {} };
      for (const name of ['get', 'create']) {
        const original = credentials[name];
        if (typeof original !== 'function') continue;
        const watched = new Proxy(original, {
          apply(target, thisArg, args) {
            const options = args[0];
            if (options && options.publicKey && options.mediation !== 'conditional') report();
            return Reflect.apply(target, thisArg, args);
          }
        });
        try { Object.defineProperty(credentials, name, { value: watched, configurable: true, writable: true }); } catch (_) {}
      }
    })();
    """

    static func install(in configuration: WKWebViewConfiguration) {
        guard !passkeysAllowed else { return }
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(PasskeyNoticeHandler.shared, contentWorld: .page, name: handlerName)
    }
}

final class PasskeyNoticeHandler: NSObject, WKScriptMessageHandler {
    static let shared = PasskeyNoticeHandler()

    /// The page can post here too (it's the page's own world), so a window says it at most once a minute.
    private var lastShown: [ObjectIdentifier: Date] = [:]

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView, let window = webView.window else { return }
        // A tab says it when it's the one on screen; the Grok panel and setup's sign-in, in their window.
        let browser: BrowserModel?
        if let tab = (webView as? MaxQWebView)?.tab {
            browser = tab.isSelected ? tab.browser : nil
        } else {
            browser = BrowserRegistry.all.first { $0.window === window }
        }
        guard let browser else { return }
        let key = ObjectIdentifier(browser)
        if let last = lastShown[key], Date().timeIntervalSince(last) < 60 { return }
        lastShown[key] = Date()
        browser.showToast(String(localized: "Passkeys aren't available in this copy of Max Q. Use your password or a code instead."),
                          duration: 7)
    }
}
