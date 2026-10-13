//
//  GrokWebAccount.swift
//  Max Q
//
//  Whether this Mac is signed in to grok.com, read from the browser's own cookies: the same
//  persistent website data the tabs and the Grok panel use, so one sign-in covers all of them and
//  lasts like any site's. Signing in happens on SpaceXAI's own page (accounts.x.ai); Max Q never
//  sees a password, only that the session cookie exists.
//

import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class GrokWebAccount: NSObject {
    static let shared = GrokWebAccount()

    /// SpaceXAI's sign-in page, returning to grok.com afterwards.
    nonisolated static let signInURL = URL(string: "https://accounts.x.ai/sign-in?redirect=grok-com")!

    /// grok.com's session cookies.
    nonisolated static let sessionCookieNames: Set<String> = ["sso", "sso-rw"]
    nonisolated static let sessionDomains = ["grok.com", "x.ai"]

    private(set) var isSignedIn = false
    /// False until the cookies have been read once.
    private(set) var isKnown = false

    @ObservationIgnored private var observing = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    /// Starts watching the cookie store, so signing in anywhere (setup, a tab, the panel) shows up
    /// at once.
    func start() {
        guard !observing else { return }
        observing = true
        store.add(self)
        scheduleRefresh(after: 0)
    }

    func refresh() async {
        let cookies = await store.allCookies()
        let signedIn = Self.hasSession(cookies)
        if signedIn != isSignedIn { isSignedIn = signedIn }
        isKnown = true
    }

    fileprivate func scheduleRefresh(after delay: Double) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Signs out of grok.com on this Mac by removing SpaceXAI's website data (grok.com and x.ai).
    func signOut() async {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let ours = records.filter { record in
            Self.sessionDomains.contains { record.displayName == $0 || record.displayName.hasSuffix(".\($0)") }
        }
        await dataStore.removeData(ofTypes: types, for: ours)
        for cookie in await store.allCookies() where Self.isSpaceXAI(cookie.domain) {
            await store.deleteCookie(cookie)
        }
        await refresh()
    }

    nonisolated static func isSpaceXAI(_ domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return sessionDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// A live grok.com session: one of its session cookies on grok.com or x.ai, not expired.
    nonisolated static func hasSession(_ cookies: [HTTPCookie], now: Date = Date()) -> Bool {
        cookies.contains { cookie in
            sessionCookieNames.contains(cookie.name) && isSpaceXAI(cookie.domain)
                && !cookie.value.isEmpty && (cookie.expiresDate.map { $0 > now } ?? true)
        }
    }
}

extension GrokWebAccount: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in GrokWebAccount.shared.scheduleRefresh(after: 0.25) }
    }
}
