//
//  Updater.swift
//  Max Q
//
//  Sparkle updates. Only switched on when the build carries a release feed URL and the public
//  signing key (set in Config/Base.xcconfig): until then there is no feed to check, so Max Q
//  never polls a host nobody controls.
//

import Foundation
import Sparkle

@MainActor
final class Updater {
    static let shared = Updater()
    private var controller: SPUStandardUpdaterController?

    nonisolated static var isConfigured: Bool {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return feed.hasPrefix("https://") && !key.isEmpty
    }

    func start() {
        guard Self.isConfigured, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var canCheckForUpdates: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
