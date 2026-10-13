//
//  MaxQApp.swift
//  Max Q
//
//  An independent, open-source macOS browser that works with Grok.
//  Not affiliated with, endorsed by, or sponsored by SpaceXAI, xAI, X Corp. or SpaceX.
//

import AppKit
import SwiftUI
import UserNotifications

@main
struct MaxQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings.shared

    init() {
        MQFonts.register()
    }

    var body: some Scene {
        WindowGroup(id: "browser") {
            if AppDelegate.isRunningTests {
                // Hosting unit tests: no browser window, so tests leave no history or session behind.
                Text("Running tests")
                    .frame(width: 240, height: 80)
            } else {
                BrowserWindow(isPrivate: false)
                    .preferredColorScheme(settings.appearance.colorScheme)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1360, height: 860)
        // Links from other apps (Max Q as the default browser) go to an open window as a tab;
        // a window is only created when none is open. See BrowserWindow's onOpenURL.
        .handlesExternalEvents(matching: ["*"])
        .commands { BrowserCommands() }

        WindowGroup("Private Window", id: "private") {
            BrowserWindow(isPrivate: true)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .handlesExternalEvents(matching: [])

        Settings {
            SettingsView()
                .preferredColorScheme(settings.appearance.colorScheme)
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .containerBackground(Theme.canvas, for: .window)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when the app is only hosting unit tests.
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        guard !Self.isRunningTests else { return }
        Updater.shared.start()
        GrokWebAccount.shared.start()
        Task { await GrokAccount.shared.refresh() }
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        if !FollowStore.shared.searches.isEmpty { FollowStore.shared.start() }
        // iCloud sync, when this copy has a container and the user turned it on.
        CloudSync.shared.start()
        // Max Q from anywhere: the bar's shortcut, and the Services menu of every app. Test copies
        // leave the shortcut to the real app.
        if Bundle.main.bundleIdentifier == "com.myrhex.MaxQ" {
            QuickAskController.shared.apply(AppSettings.shared.globalShortcut)
        }
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HistoryStore.shared.flush()
        if let browser = BrowserRegistry.lastNormal { SessionStore.saveNow(browser) }
    }
}

/// Keeps track of open windows, most recently active last (the session saved at quit is the
/// last active normal window's).
@MainActor
enum BrowserRegistry {
    private static var browsers: [WeakBrowser] = []

    private struct WeakBrowser { weak var model: BrowserModel? }

    static func register(_ browser: BrowserModel) {
        browsers.removeAll { $0.model == nil || $0.model === browser }
        browsers.append(WeakBrowser(model: browser))
    }

    static func markActive(_ browser: BrowserModel) {
        register(browser)
    }

    static var lastNormal: BrowserModel? {
        browsers.reversed().compactMap(\.model).first { !$0.isPrivate }
    }

    /// Every window's browser, private ones included.
    static var all: [BrowserModel] {
        browsers.compactMap(\.model)
    }
}

/// Opens what a notification is about (a followed search with news) in the last window used.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let query = response.notification.request.content.userInfo["followedQuery"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let query, let browser = BrowserRegistry.lastNormal {
                    browser.openMaxQSearch(query, on: .news, inNewTab: true)
                    browser.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate()
                }
            }
            completionHandler()
        }
    }
}
