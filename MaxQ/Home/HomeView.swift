//
//  HomeView.swift
//  Max Q
//
//  The new-tab page, after grok.com's own: one question in the middle with grok.com's spectrum
//  line under its last word, the composer below it, and a row of SpaceXAI's sites in Grokipedia's
//  "Trending" chips. Parts rise into place 60 ms apart, as Grokipedia's home does. Below the fold,
//  reached by scrolling or "Today's news", the day's news (normal windows, when it's on).
//

import SwiftUI

struct HomeView: View {
    @Bindable var browser: BrowserModel
    var tab: BrowserTab? = nil
    var addressFocus: FocusState<Bool>.Binding

    @State private var revealed = false
    @State private var settings = AppSettings.shared

    /// The news below the question: normal windows, when it's on.
    private var showsNews: Bool { settings.homeNews && !browser.isPrivate }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        hero(proxy.size) { withAnimation(Motion.page) { reader.scrollTo("news", anchor: .top) } }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        if showsNews {
                            HomeNewsSection(browser: browser) { id in
                                withAnimation(Motion.page) { reader.scrollTo(id, anchor: .top) }
                            }
                            .frame(maxWidth: 1080)
                            .padding(.horizontal, 40)
                            .padding(.top, 34)
                            .padding(.bottom, 64)
                            .frame(maxWidth: .infinity)
                            .id("news")
                        }
                    }
                }
                .scrollDisabled(!showsNews)
                .scrollIndicators(showsNews ? .automatic : .never)
                .scrollEdgeFade()
                .onChange(of: tab?.showNewsRequest ?? 0) { _, _ in
                    withAnimation(Motion.page) { reader.scrollTo("news", anchor: .top) }
                }
                .onAppear {
                    if (tab?.showNewsRequest ?? 0) > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(Motion.page) { reader.scrollTo("news", anchor: .top) }
                        }
                    }
                }
            }
        }
        .background(browser.isPrivate ? Theme.privateSurface : Theme.surface)
        .onAppear {
            revealed = true
            if showsNews {
                // After the question has risen into place.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { HomeNewsFeed.shared.prime() }
            }
        }
    }

    /// The question, the field and the sites, filling the window.
    private func hero(_ size: CGSize, showNews: @escaping () -> Void) -> some View {
        ZStack {
            (browser.isPrivate ? Theme.privateSurface : Theme.surface)
                .contentShape(Rectangle())
                .onTapGesture {
                    addressFocus.wrappedValue = false
                    browser.dismissSuggestions()
                }

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                if browser.isPrivate {
                    GhostMark(size: 34)
                        .foregroundStyle(Theme.privateTint)
                        .padding(.bottom, 18)
                        .reveal(revealed)
                }

                headline
                    .reveal(revealed)
                    .padding(.bottom, browser.isPrivate ? 10 : 30)

                if browser.isPrivate {
                    Text("Nothing from this window is saved: no history, no cookies, no tabs.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .reveal(revealed, delay: 0.06)
                        .padding(.bottom, 28)
                }

                AddressField(browser: browser, focus: addressFocus, isHero: true)
                    .frame(maxWidth: 720)
                    .overlay(alignment: .top) {
                        if !browser.suggestions.isEmpty && addressFocus.wrappedValue {
                            SuggestionsPanel(browser: browser, maxWidth: 720)
                                .offset(y: 112)
                                .transition(.pop(anchor: .top, scale: 0.985))
                        }
                    }
                    .zIndex(2)
                    .reveal(revealed, delay: 0.12)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 18)

                LauncherChips(browser: browser)
                    .reveal(revealed, delay: 0.18)

                Spacer(minLength: 40)
                Spacer(minLength: 40)

                if showsNews {
                    NewsCue(action: showNews)
                        .reveal(revealed, delay: 0.26)
                        .padding(.bottom, 14)
                }

                Text("Max Q is an independent open-source browser, not affiliated with SpaceXAI or X Corp.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textQuaternary)
                    .multilineTextAlignment(.center)
                    .reveal(revealed, delay: 0.3)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
            .frame(width: size.width, height: size.height)
            .animation(Motion.decelerate(0.2), value: browser.suggestions.isEmpty)
        }
    }

    /// grok.com's greeting, 26 points at its 550 weight and -2% tracking, the last word underlined:
    /// the user's name when they gave one.
    private var headline: some View {
        let (lead, last): (String, String) = {
            if browser.isPrivate { return (String(localized: "Browse "), String(localized: "privately.")) }
            if let name = AppSettings.shared.name { return (String(localized: "Where to next, "), String(localized: "\(name)?")) }
            return (String(localized: "Where do you want to "), String(localized: "go?"))
        }()
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(lead)
            Text(last)
                .overlay(alignment: .bottom) {
                    SpectrumLine(height: 2)
                        .offset(y: 5)
                }
        }
        .font(.heading(26))
        .tracking(-0.52)
        .foregroundStyle(Theme.textPrimary)
        .accessibilityElement(children: .combine)
    }
}

/// "Today's news" at the foot of the new-tab page: the way down to the news. The chevron dips on
/// hover, toward where the news is.
private struct NewsCue: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Today's news")
                Icon(.chevronDown, size: 13)
                    .offset(y: hovering ? 2 : 0)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(hovering ? Theme.hover : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.3), value: hovering)
    }
}
