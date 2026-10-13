//
//  XPostsPage.swift
//  Max Q
//
//  The Posts on X tab: x.com's own search for the same words, in the user's own X account, under
//  the results page's tabs and across their whole width. Max Q shows x.com itself, as X serves it,
//  rather than reading posts out of it: X's own tabs (Top, Latest, People, Media) switch the
//  search, and the rest of X is a click away in the tab.
//

import AppKit
import SwiftUI

struct XPostsPage: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    /// The tab is the one on show.
    let active: Bool

    var body: some View {
        SearchOnX(browser: browser, search: search, active: active)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - x.com's search

/// x.com's search itself, under the tabs. While it loads, the outlines of posts stand in; signed
/// out, a way to sign in to X.
private struct SearchOnX: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let active: Bool
    /// Stays true while the page slides away, so the posts leave with it.
    @State private var onScreen = false

    private var pane: XSearchPane { browser.xSearch }
    private var showing: Bool { pane.query == search.query && pane.state == .ready }

    var body: some View {
        ZStack(alignment: .top) {
            XSearchHost(pane: pane, visible: onScreen)
                .id(browser.spaceVersion)
                .padding(.top, searchTabBarHeight)
                .opacity(showing ? 1 : 0)
                .animation(Motion.standard(0.25), value: showing)

            switch pane.state {
            case .needsSignIn:
                XSignInPrompt { browser.openPinned(.x) }
                    .padding(.top, searchTabBarHeight)
                    .transition(.blurFade())
            case .failed(let message):
                VStack(spacing: 14) {
                    Text(message)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Try again") { pane.reload() }
                        .pill(.secondary, size: .small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            default:
                if !showing {
                    XPostsPlaceholder()
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity)
                        .padding(.top, searchTabBarHeight + 8)
                        .transition(.opacity)
                }
            }
        }
        .animation(Motion.standard(0.25), value: pane.state)
        .onAppear {
            onScreen = active
            if active { pane.show(query: search.query) }
        }
        .onChange(of: active) { _, now in
            if now {
                onScreen = true
                pane.show(query: search.query)
            } else {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    if !active { onScreen = false }
                }
            }
        }
    }
}

/// Outlines of x.com posts, breathing, while posts load.
struct XPostsPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<5, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.selected).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 9) {
                        SkeletonBar(width: 0.38, height: 10, delay: Double(row) * 0.1)
                        SkeletonBar(width: 0.94, height: 10, delay: Double(row) * 0.1 + 0.05)
                        SkeletonBar(width: [0.7, 0.5, 0.82, 0.6, 0.74][row], height: 10, delay: Double(row) * 0.1 + 0.1)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }
        .padding(.top, 2)
    }
}

/// Signed out of X: x.com searches for signed-in accounts.
private struct XSignInPrompt: View {
    let signIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("See what X is saying")
                .font(.system(size: 31, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("x.com's search is for signed-in accounts. Sign in to X once in its tab at the top of the sidebar, and its posts show here.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Button("Sign in to X", action: signIn)
                .pill(.primary, size: .large)
                .padding(.top, 26)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }
}
