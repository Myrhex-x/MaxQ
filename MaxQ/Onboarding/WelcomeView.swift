//
//  WelcomeView.swift
//  Max Q
//
//  First run, across the whole window, built the way SpaceXAI builds its pages:
//    1. x.ai's hero: a "New" badge, a headline whose words tip up into place one after another,
//       a last line that keeps changing (letters blurring between phrases) over the spectrum line,
//       white and dark pills, and a grid of cards with small live demos that slowly fades in.
//    2. Your name, for the sidebar's account row. The avatar's initial follows what you type.
//    3. Connecting Grok, accounts.x.ai's way: a centered title over outlined capsules. "Sign in to
//       grok.com" grows into SpaceXAI's own sign-in page, and the session stays in the browser;
//       "Add an API key" grows into the key field (the control becomes what it opens).
//    4. How you search: Max Q's own results page first, then the classic engines.
//    5. With Max Q's page: the user's own Brave Search API key for web results, pictures, videos
//       and news, tried with one small search before it's saved, or the way to get one.
//
//  Settings can bring setup back over a window that's in use ("Set up Max Q again"): then a Close
//  button sits in the top bar, and leaving early changes nothing.
//

import AppKit
import SwiftUI

struct WelcomeView: View {
    @Bindable var browser: BrowserModel
    /// Opened again from Settings rather than on first launch.
    var revisiting = false
    let finish: () -> Void

    @State private var step = 0
    @State private var settings = AppSettings.shared
    @State private var name = AppSettings.shared.displayName
    @State private var key = ""
    @State private var keyError: String?
    @State private var checking = false
    /// "Get one at console.x.ai": open the console and the key form once setup is done.
    @State private var openConsoleAfterSetup = false
    @State private var searchKey = ""
    @State private var searchKeyError: String?
    /// "Get one at brave.com/search/api": open Brave's page once setup is done.
    @State private var openBraveAfterSetup = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings

    init(browser: BrowserModel, revisiting: Bool = false, finish: @escaping () -> Void) {
        _browser = Bindable(browser)
        self.revisiting = revisiting
        self.finish = finish
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 780 || proxy.size.width < 1080
            ZStack {
                Color.clear
                    .onAppear { cardHeight = Self.cardHeight(for: proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in cardHeight = Self.cardHeight(for: height) }
                backdrop

                VStack(spacing: 0) {
                    topBar
                    ZStack {
                        scene(compact: compact, width: proxy.size.width)
                            .id(step)
                            .transition(.welcomeScene)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    footer
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            scheme == .dark ? Theme.hex(0x090909) : Theme.hex(0xFAFAFA)
            if step == 0 {
                TwinkleField(count: 44, seed: 11)
                    .opacity(scheme == .dark ? 0.8 : 0.5)
                    .transition(.opacity)
            }
        }
        .animation(Motion.standard(0.6), value: step)
        .allowsHitTesting(false)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 9) {
            // The window's traffic lights sit here.
            Color.clear.frame(width: 64, height: 1)
            MaxQMark(size: 20, glow: false)
            Text("Max Q")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if step > 0 {
                Button {
                    go(step - 1)
                } label: {
                    HStack(spacing: 6) {
                        Icon(.arrowLeft, size: 15)
                        Text("Back")
                    }
                }
                .pill(.ghost, size: .small)
                .keyboardShortcut(.cancelAction)
                .transition(.opacity)
            }
            if revisiting {
                Button("Close", action: finish)
                    .pill(.secondary, size: .small)
                    .tip("Back to your tabs, nothing changed")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 20)
        .frame(height: 52)
        .overlay { if step > 0 { StepDots(step: step, count: settings.searchEngineID == .maxq ? 4 : 3) } }
        .animation(Motion.standard(0.24), value: step)
    }

    private var footer: some View {
        Text("Max Q is an independent open-source project, not affiliated with SpaceXAI or X Corp.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textQuaternary)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
    }

    // MARK: Scenes

    @State private var cardHeight: CGFloat = 600

    @ViewBuilder
    private func scene(compact: Bool, width: CGFloat) -> some View {
        switch step {
        case 0:
            IntroScene(compact: compact, width: width, skipTitle: revisiting ? String(localized: "Close") : String(localized: "Skip setup"),
                       start: { go(1) }, skip: revisiting ? finish : skipSetup)
        case 1:
            NameScene(name: $name, next: saveName)
        case 2:
            GrokScene(browser: browser, cardHeight: cardHeight, key: $key, keyError: $keyError, checking: checking,
                      useWeb: useGrokWeb, submitKey: submitKey, getKey: getKeyLater, skip: { go(3) })
        case 3:
            SearchScene(selection: $settings.searchEngineID, hasKey: browser.grokAccount.hasKey, chose: chose)
        default:
            SearchKeyScene(key: $searchKey, keyError: $searchKeyError, submit: submitSearchKey,
                           getKey: getSearchKeyLater, skip: done)
        }
    }

    /// The sign-in page fits between the top bar and the footer.
    private static func cardHeight(for windowHeight: CGFloat) -> CGFloat {
        min(600, max(360, windowHeight - 170))
    }

    private func go(_ target: Int) {
        withAnimation(Motion.spring(0.6)) { step = max(0, target) }
    }

    // MARK: Finishing

    private func skipSetup() {
        settings.grokPanelMode = browser.grokAccount.hasKey ? .native : .web
        done()
    }

    private func saveName() {
        settings.displayName = AppSettings.cleanName(name)
        go(2)
    }

    private func useGrokWeb() {
        if !browser.grokAccount.hasKey { settings.grokPanelMode = .web }
        go(3)
    }

    private func submitKey() {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty {
            if browser.grokAccount.hasKey {
                settings.grokPanelMode = .native
                done()
            } else {
                withAnimation(Motion.standard(0.2)) { keyError = String(localized: "Paste your API key, or use grok.com for now.") }
            }
            return
        }
        checking = true
        keyError = nil
        Task {
            let failure = await browser.grokAccount.setKey(candidate)
            checking = false
            if let failure {
                withAnimation(Motion.standard(0.2)) { keyError = failure }
            } else {
                settings.grokPanelMode = .native
                go(3)
            }
        }
    }

    /// No key yet: carry on, and once setup is done open console.x.ai in a tab with the Grok
    /// panel's key form beside it.
    private func getKeyLater() {
        settings.grokPanelMode = .native
        openConsoleAfterSetup = true
        go(3)
    }

    /// Max Q's own page needs a search key for its web results; a classic engine doesn't.
    private func chose(_ engine: SearchEngineID) {
        if engine == .maxq { go(4) } else { done() }
    }

    private func submitSearchKey() {
        let account = SearchAPIAccount.shared
        let candidate = searchKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            if account.hasKey {
                done()
            } else {
                withAnimation(Motion.standard(0.2)) { searchKeyError = String(localized: "Paste your Brave Search API key first.") }
            }
            return
        }
        guard !account.checking else { return }
        withAnimation(Motion.standard(0.2)) { searchKeyError = nil }
        Task {
            if let failure = await account.setKey(candidate) {
                withAnimation(Motion.standard(0.2)) { searchKeyError = failure }
            } else {
                done()
            }
        }
    }

    /// No key yet: finish, then open Brave's page for one in a tab, with the way to Settings.
    private func getSearchKeyLater() {
        openBraveAfterSetup = true
        done()
    }

    private func done() {
        settings.hasCompletedOnboarding = true
        finish()
        if openConsoleAfterSetup {
            if let url = URL(string: "https://console.x.ai") { browser.open(url) }
            browser.grokPanelVisible = true
        }
        if openBraveAfterSetup, let url = URL(string: "https://brave.com/search/api/") {
            browser.openInNewTab(url)
            let openSettings = openSettings
            browser.showToast(String(localized: "Once you have a key, add it in Settings, under General."),
                              actionTitle: String(localized: "Open Settings")) {
                SettingsRouter.shared.section = .general
                openSettings()
            }
        }
    }
}

// MARK: - 1. The hero

private struct IntroScene: View {
    let compact: Bool
    let width: CGFloat
    var skipTitle = String(localized: "Skip setup")
    let start: () -> Void
    let skip: () -> Void

    @State private var revealed = false
    @State private var phraseIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let phrases = [String(localized: "built in."), String(localized: "on every page."), String(localized: "beside your search.")]

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    private var headlineSize: CGFloat { compact ? 48 : 64 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            badge
                .reveal(revealed, delay: 0.32)
                .padding(.bottom, compact ? 22 : 30)

            VStack(spacing: 2) {
                FlipText(text: String(localized: "The web, with Grok"), font: .hero(headlineSize), size: headlineSize, delay: 0.1)
                    .tracking(-headlineSize * 0.012)
                    .foregroundStyle(Theme.textPrimary)
                MorphText(text: Self.phrases[phraseIndex], font: .hero(headlineSize), size: headlineSize)
                    .tracking(-headlineSize * 0.012)
                    .foregroundStyle(Theme.textPrimary)
                    .overlay(alignment: .bottom) {
                        SpectrumLine(height: 3, growDelay: 0.8, sweepDelay: 0.4)
                            .offset(y: compact ? 4 : 6)
                    }
                    .opacity(revealed ? 1 : 0)
                    .blur(radius: revealed ? 0 : 6)
                    .animation(Motion.spring(0.65).delay(0.28), value: revealed)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, compact ? 22 : 28)

            Text("A fast, native Mac browser. Search the web with Grok's answers, ask about any page, see what X is saying, and read Grokipedia beside your results.")
                .font(.system(size: compact ? 15 : 17))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(revealed, delay: 0.5)
                .padding(.bottom, compact ? 26 : 36)

            HStack(spacing: 12) {
                Button(action: start) {
                    HStack(spacing: 6) {
                        Text("Get started")
                        Icon(.chevronRight, size: 14)
                    }
                }
                .pill(.primary, size: .hero)
                .keyboardShortcut(.defaultAction)
                Button(skipTitle, action: skip)
                    .pill(.secondary, size: .hero)
            }
            .reveal(revealed, delay: 0.7)

            if !compact {
                FeatureGrid(width: min(width - 120, 1180))
                    .padding(.top, 64)
                    .opacity(revealed ? 1 : 0)
                    .animation(Motion.spring(1.25).delay(0.76), value: revealed)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 40)
        .onAppear { revealed = true }
        .task {
            // The last line changes every few seconds, after the headline has landed.
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(3.4))
            while !Task.isCancelled {
                phraseIndex = (phraseIndex + 1) % Self.phrases.count
                try? await Task.sleep(for: .seconds(3.2))
            }
        }
    }

    /// x.ai's announcement badge: an orange "New" tag, the name and a dimmed separator.
    private var badge: some View {
        HStack(spacing: 10) {
            Text("New")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.solar)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Theme.solar.opacity(0.1)))
            HStack(spacing: 0) {
                Text("Max Q \(version)")
                    .foregroundStyle(Theme.textPrimary)
                Text("  ·  ")
                    .foregroundStyle(Theme.textQuaternary)
                Text("Free and open source")
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 13))
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 34)
        .background(Capsule().fill(Theme.hover))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: Feature cards (x.ai's bento)

private struct FeatureGrid: View {
    let width: CGFloat

    var body: some View {
        let spacing: CGFloat = 12
        let cardWidth = max((width - spacing * 3) / 4, 200)
        HStack(spacing: spacing) {
            FeatureCard(title: String(localized: "Max Q search"), detail: String(localized: "Grok's answer, web and X")) {
                GrokSearchDemo().padding(.top, 10).padding(.horizontal, 8)
            }
            FeatureCard(title: String(localized: "Ask Grok"), detail: String(localized: "About any page")) { ChatDemo() }
            FeatureCard(title: "Grokipedia", detail: String(localized: "Beside your results")) { BookDemo() }
            FeatureCard(title: String(localized: "What X says"), detail: String(localized: "About this page")) { PostsDemo() }
        }
        .frame(width: cardWidth * 4 + spacing * 3)
    }
}

/// An x.ai product card: a live demo in a rounded tile, its name at the foot. On hover the demo
/// leans in (102%) and a band of light crosses the card.
private struct FeatureCard<Demo: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var demo: Demo
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            demo
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(hovering ? 1.02 : 1)
                .animation(.timingCurve(0, 0, 0.2, 1, duration: 0.5), value: hovering)
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textPrimary.opacity(0.8))
                Spacer(minLength: 8)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(hovering ? Theme.textSecondary : Theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(height: 220)
        .background(Theme.dynamic(light: Theme.hex(0xFFFFFF), dark: Theme.hex(0x111111)))
        .overlay(Sheen(active: hovering))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3), value: hovering)
    }
}

/// x.ai's chat card: a question arrives, Grok thinks, an answer blurs in, then it starts over.
private struct ChatDemo: View {
    @State private var phase = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            if phase >= 1 {
                Text("Summarize this page")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.selected))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.modifier(active: EntryModifier(shown: false), identity: EntryModifier(shown: true)))
            }
            if phase == 2 {
                ShimmerText(text: String(localized: "Thinking"), font: .system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .transition(.blurFade())
            }
            if phase >= 3 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Here's the short version, with sources:")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                    ForEach(0..<3, id: \.self) { line in
                        HStack(spacing: 6) {
                            Circle().fill(Theme.textTertiary).frame(width: 3, height: 3)
                            Capsule().fill(Theme.selected).frame(width: [140, 118, 96][line], height: 6)
                        }
                    }
                }
                .transition(.blurFade())
            }
        }
        .padding(16)
        .animation(Motion.overshoot(0.42), value: phase)
        .task {
            while !Task.isCancelled {
                for (next, pause) in [(1, 0.6), (2, 0.9), (3, 1.4), (3, 3.0), (0, 0.6)] {
                    try? await Task.sleep(for: .seconds(pause))
                    if Task.isCancelled { return }
                    phase = next
                }
            }
        }
    }
}

/// x.ai's chat entries: up 8 points from 97%, with a hair of overshoot.
private struct EntryModifier: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.97, anchor: .bottomTrailing)
            .offset(y: shown ? 0 : 8)
    }
}

private struct BookDemo: View {
    var body: some View {
        GrokipediaBook(title: "Starship", width: 86, height: 124)
            .padding(.top, 6)
    }
}

/// A live stream of posts: new ones slide in from the left (x.ai's row entry), with Grokipedia's
/// live dot.
private struct PostsDemo: View {
    @State private var rows: [Int] = [0, 1, 2]
    @State private var next = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                LiveDot(color: Theme.textPrimary, size: 5)
                Text("Live on X")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    Circle().fill(Theme.selected).frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Theme.selected).frame(width: CGFloat(64 + (row * 37) % 50), height: 5)
                        Capsule().fill(Theme.hover).frame(width: CGFloat(110 + (row * 53) % 40), height: 5)
                    }
                }
                .transition(.asymmetric(insertion: .modifier(active: RowEntry(shown: false), identity: RowEntry(shown: true)),
                                        removal: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.spring(0.42), value: rows)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.7))
                if Task.isCancelled { return }
                rows.insert(next, at: 0)
                next += 1
                if rows.count > 4 { rows.removeLast() }
            }
        }
    }
}

private struct RowEntry: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown ? 0 : -10)
    }
}

// MARK: - 2. Your name

private struct NameScene: View {
    @Binding var name: String
    let next: () -> Void

    @State private var revealed = false
    @FocusState private var focused: Bool

    private var cleaned: String { AppSettings.cleanName(name) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            SceneTitle(title: String(localized: "What should we call you?"),
                       detail: String(localized: "Your name goes at the foot of the sidebar, where your settings are. It stays on this Mac."))
                .padding(.bottom, 40)

            HStack(spacing: 12) {
                // The avatar takes the first letter as you type it.
                ProfileAvatar(name: cleaned.isEmpty ? nil : cleaned, size: 32)
                    .id(cleaned.first.map(String.init) ?? "")
                    .transition(.blurFade(radius: 4).combined(with: .scale(scale: 0.85)))
                    .animation(Motion.spring(0.35), value: cleaned.first)
                TextField("Your name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: name) { _, value in
                        if value.count > 32 { name = String(value.prefix(32)) }
                    }
                Button(action: submit) { Icon(.arrowUp, size: 18, weight: 2.2) }
                    .sendButton(size: 36)
                    .disabled(cleaned.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Continue")
            }
            .padding(.leading, 9)
            .padding(.trailing, 7)
            .frame(width: 400, height: 52)
            .background(Capsule().fill(Theme.input))
            .overlay(Capsule().strokeBorder(focused ? Theme.border : Theme.composerBorder, lineWidth: 1))
            .elevation(.composer)
            .animation(Motion.standard(0.18), value: focused)
            .reveal(revealed, delay: 0.2)

            Button("Skip", action: next)
                .pill(.ghost, size: .small)
                .padding(.top, 22)
                .reveal(revealed, delay: 0.3)
            Spacer(minLength: 20)
        }
        .onAppear {
            revealed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focused = true }
        }
    }

    private func submit() {
        guard !cleaned.isEmpty else { return }
        next()
    }
}

// MARK: - 3. Grok

private struct GrokScene: View {
    @Bindable var browser: BrowserModel
    /// The sign-in page's height, fitted to the window.
    var cardHeight: CGFloat = 600
    @Binding var key: String
    @Binding var keyError: String?
    let checking: Bool
    let useWeb: () -> Void
    let submitKey: () -> Void
    let getKey: () -> Void
    let skip: () -> Void

    @State private var revealed = false
    @State private var addingKey = false
    @State private var signingIn = false
    /// Set when the sign-in finishes here, for the check that lands before moving on.
    @State private var justSignedIn = false
    @FocusState private var keyFocused: Bool
    @Namespace private var morph
    private var webAccount: GrokWebAccount { GrokWebAccount.shared }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            if !signingIn {
                SceneTitle(title: String(localized: "Connect Grok"),
                           detail: String(localized: "Sign in to grok.com with your Grok account, free, or use your own SpaceXAI API key for answers built into Max Q. There's no Max Q server: everything goes straight to SpaceXAI."))
                    .padding(.bottom, 40)
                    .transition(.blurFade(radius: 6))
            }

            VStack(spacing: 10) {
                // One shape that grows from the capsule into SpaceXAI's sign-in page and shrinks
                // back, the way grok.com's panels grow out of the control that opens them.
                SignInMorph(browser: browser, open: signingIn, signedIn: webAccount.isSignedIn || justSignedIn,
                            landed: justSignedIn, cardHeight: cardHeight) {
                    if webAccount.isSignedIn {
                        useWeb()
                    } else {
                        addingKey = false
                        withAnimation(Motion.grow) { signingIn = true }
                    }
                } close: {
                    withAnimation(Motion.grow) { signingIn = false }
                } signedInHere: {
                    finishSignIn()
                }
                .reveal(revealed, delay: 0.2)

                if !signingIn {
                    if addingKey {
                        keyField
                            .matchedGeometryEffect(id: "key", in: morph)
                    } else {
                        ChoiceCapsule(selected: false, landed: false) {
                            HStack(spacing: 10) {
                                Icon(.key, size: 18)
                                Text(browser.grokAccount.hasKey ? "Use my saved API key" : "Add an API key")
                            }
                        } action: {
                            if browser.grokAccount.hasKey && key.isEmpty {
                                submitKey()
                            } else {
                                withAnimation(Motion.spring(0.5)) { addingKey = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { keyFocused = true }
                            }
                        }
                        .matchedGeometryEffect(id: "key", in: morph)
                        .reveal(revealed, delay: 0.24)
                    }
                }
            }
            .frame(width: signingIn ? 460 : 400)

            if !signingIn {
                VStack(spacing: 8) {
                    if let keyError {
                        Text(keyError)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.warning)
                            .multilineTextAlignment(.center)
                            .transition(.blurFade())
                    }
                    if addingKey {
                        HStack(spacing: 4) {
                            Text("No key yet?")
                                .foregroundStyle(Theme.textTertiary)
                            Button("Get one at console.x.ai", action: getKey)
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .font(.system(size: 13))
                        .transition(.blurFade())
                        Text("Your key stays in your Mac's Keychain.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textQuaternary)
                            .transition(.blurFade())
                    } else {
                        Button("Not now", action: skip)
                            .pill(.ghost, size: .small)
                            .transition(.blurFade())
                    }
                }
                .frame(width: 400)
                .padding(.top, 22)
                .animation(Motion.standard(0.24), value: keyError)
                .animation(Motion.standard(0.24), value: addingKey)
                .transition(.blurFade(radius: 6))
            }
            Spacer(minLength: 16)
        }
        .animation(Motion.grow, value: signingIn)
        .onAppear {
            revealed = true
            GrokWebAccount.shared.start()
        }
        .onChange(of: webAccount.isSignedIn) { _, signedIn in
            if signedIn { finishSignIn() }
        }
    }

    /// The page closes back into its capsule, the check lands, and setup moves on.
    private func finishSignIn() {
        guard signingIn, !justSignedIn else { return }
        withAnimation(Motion.grow) { signingIn = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { justSignedIn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { useWeb() }
    }

    /// The key field: grok.com's composer in one line, with the blue send button.
    private var keyField: some View {
        HStack(spacing: 10) {
            Icon(.key, size: 18)
                .foregroundStyle(Theme.textTertiary)
            SecureField("xai-…", text: $key)
                .textFieldStyle(.plain)
                .font(.mono(14, weight: .regular))
                .focused($keyFocused)
                .onSubmit(submitKey)
            if checking {
                ShimmerText(text: String(localized: "Checking"), font: .system(size: 13, weight: .medium))
                    .transition(.opacity)
            }
            Button(action: submitKey) { Icon(.arrowUp, size: 18, weight: 2.2) }
                .sendButton(size: 34)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Connect")
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .frame(height: 48)
        .background(Capsule().fill(Theme.input))
        .overlay(Capsule().strokeBorder(keyFocused ? Theme.border : Theme.composerBorder, lineWidth: 1))
        .elevation(.composer)
        .animation(Motion.standard(0.18), value: keyFocused)
    }
}

/// "Sign in to grok.com": a capsule that grows into SpaceXAI's own sign-in page (accounts.x.ai) and
/// shrinks back into the capsule when it's done. The page signs in to the browser's normal website
/// data, so the grok.com session stays like any site's and the tabs and the Grok panel share it.
private struct SignInMorph: View {
    @Bindable var browser: BrowserModel
    let open: Bool
    let signedIn: Bool
    let landed: Bool
    let cardHeight: CGFloat
    let action: () -> Void
    let close: () -> Void
    /// The sign-in came back to grok.com.
    var signedInHere: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: open ? Theme.Radius.menu : 24, style: .continuous)
        ZStack {
            if open {
                // The page fades in once the card has grown, and goes at once when it closes: a web
                // view isn't clipped by the shrinking shape, so it mustn't linger outside it.
                SignInCardContent(browser: browser, close: close, signedIn: signedInHere)
                    .transition(.asymmetric(insertion: .opacity.animation(Motion.standard(0.22).delay(0.16)),
                                            removal: .identity))
            } else {
                Button(action: action) {
                    HStack(spacing: 10) {
                        Icon(.globe, size: 18)
                        if signedIn {
                            Text("Signed in to grok.com")
                        } else {
                            Text("Sign in to grok.com")
                            Text("Free with your account")
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        if signedIn {
                            Icon(.check, size: 16)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.trailing, 18)
                                .checkPop(landed)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ChoicePress())
                .onHover { hovering = $0 }
                .transition(.opacity.animation(.linear(duration: 0.08)))
            }
        }
        .frame(width: open ? 460 : 400, height: open ? cardHeight : 48)
        .background(shape.fill(open ? Theme.raised : (landed ? Theme.selected : (hovering ? Theme.hover : .clear))))
        .clipShape(shape)
        .overlay(shape.strokeBorder(open ? Theme.hairline : (signedIn || hovering ? Theme.borderStrong : Theme.border), lineWidth: 1))
        .elevation(open ? .menu : .raised)
        .animation(Motion.grow, value: open)
        .animation(Motion.hover, value: hovering)
        .animation(Motion.spring(0.4), value: landed)
    }
}

/// The sign-in card's inside: the page's address, SpaceXAI's page itself, and a line on who sees what.
private struct SignInCardContent: View {
    @Bindable var browser: BrowserModel
    let close: () -> Void
    var signedIn: () -> Void = {}
    @State private var controller = GrokSignInController()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Icon(.lock, size: 15)
                    .foregroundStyle(Theme.textTertiary)
                Text("accounts.x.ai")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if controller.isLoading {
                    ShimmerText(text: String(localized: "Loading"), font: .system(size: 12))
                        .transition(.opacity)
                }
                Spacer()
                Button(action: close) { Icon(.close, size: 14) }
                    .iconButton(size: 28)
                    .tip("Close")
                    .accessibilityLabel("Close sign-in")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(height: 44)
            .animation(Motion.standard(0.2), value: controller.isLoading)

            SignInWebHost(controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 6)

            Text("This is SpaceXAI's own page. Max Q never sees your password.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .frame(height: 38)
        }
        .onAppear {
            controller.openElsewhere = { url in browser.openInNewTab(url, select: false) }
            controller.start()
        }
        .onDisappear { controller.tearDown() }
        .onChange(of: controller.landedOnGrok) { _, landed in
            if landed { signedIn() }
        }
    }
}

private struct SignInWebHost: NSViewRepresentable {
    let controller: GrokSignInController

    func makeNSView(context: Context) -> NSView { controller.container }
    func updateNSView(_ view: NSView, context: Context) {}
}

// MARK: - 4. How you search

private struct SearchScene: View {
    @Binding var selection: SearchEngineID
    let hasKey: Bool
    let chose: (SearchEngineID) -> Void

    @State private var revealed = false
    @State private var chosen: SearchEngineID?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            SceneTitle(title: String(localized: "Choose how you search"),
                       detail: String(localized: "Max Q puts Grok's answer, web results, Grokipedia and posts from X on one page. A classic engine opens its own page, with Grokipedia beside it."))
                .padding(.bottom, 36)

            MaxQEngineCard(selected: (chosen ?? selection) == .maxq, landed: chosen == .maxq, hasKey: hasKey) {
                choose(.maxq)
            }
            .frame(width: 540)
            .reveal(revealed, delay: 0.18)

            Text("Or a classic engine")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 28)
                .padding(.bottom, 12)
                .reveal(revealed, delay: 0.26)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(174), spacing: 9), count: 3), spacing: 9) {
                ForEach(Array(SearchEngineID.classic.enumerated()), id: \.element) { index, id in
                    if let engine = SearchEngine.builtIn(id) {
                        ChoiceCapsule(selected: (chosen ?? selection) == id && chosen != nil, landed: chosen == id, height: 42) {
                            HStack(spacing: 9) {
                                EngineIcon(engine: engine, size: 16)
                                Text(engine.name)
                            }
                        } action: {
                            choose(id)
                        }
                        .reveal(revealed, delay: 0.3 + Double(index) * 0.035)
                    }
                }
            }
            .frame(width: 540)
            Spacer(minLength: 16)
        }
        .onAppear {
            revealed = true
            for id in SearchEngineID.classic {
                if let url = SearchEngine.builtIn(id)?.siteURL { FaviconStore.shared.prefetchIcon(forSite: url) }
            }
        }
    }

    private func choose(_ id: SearchEngineID) {
        guard chosen == nil else { return }
        chosen = id
        selection = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { chose(id) }
    }
}

// MARK: - 5. Web results

/// Max Q's results page takes its web results, pictures, videos and news from the Brave Search API
/// with the user's own key: the key field in grok.com's composer shape, as for the SpaceXAI key,
/// and the way to get one.
private struct SearchKeyScene: View {
    @Binding var key: String
    @Binding var keyError: String?
    let submit: () -> Void
    let getKey: () -> Void
    let skip: () -> Void

    @State private var revealed = false
    @FocusState private var focused: Bool
    private var account: SearchAPIAccount { SearchAPIAccount.shared }

    private var canSubmit: Bool {
        (!key.trimmingCharacters(in: .whitespaces).isEmpty || account.hasKey) && !account.checking
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            SceneTitle(title: String(localized: "Turn on web results"),
                       detail: String(localized: "Max Q's results page gets web results, pictures, videos and news from the Brave Search API, with your own key. A free Brave account comes with monthly credit for about a thousand searches. Without a key, those searches open on DuckDuckGo."))
                .padding(.bottom, 40)

            HStack(spacing: 10) {
                Icon(.key, size: 18)
                    .foregroundStyle(Theme.textTertiary)
                SecureField(account.hasKey ? String(localized: "Saved key \(account.keyHint)") : String(localized: "Brave Search API key"),
                            text: $key)
                    .textFieldStyle(.plain)
                    .font(.mono(14, weight: .regular))
                    .focused($focused)
                    .onSubmit(submit)
                if account.checking {
                    ShimmerText(text: String(localized: "Checking"), font: .system(size: 13, weight: .medium))
                        .transition(.opacity)
                }
                Button(action: submit) { Icon(.arrowUp, size: 18, weight: 2.2) }
                    .sendButton(size: 34)
                    .disabled(!canSubmit)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Continue")
            }
            .padding(.leading, 18)
            .padding(.trailing, 7)
            .frame(width: 400, height: 48)
            .background(Capsule().fill(Theme.input))
            .overlay(Capsule().strokeBorder(focused ? Theme.border : Theme.composerBorder, lineWidth: 1))
            .elevation(.composer)
            .animation(Motion.standard(0.18), value: focused)
            .animation(Motion.standard(0.2), value: account.checking)
            .reveal(revealed, delay: 0.2)

            VStack(spacing: 8) {
                if let keyError {
                    Text(keyError)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.warning)
                        .multilineTextAlignment(.center)
                        .transition(.blurFade())
                }
                HStack(spacing: 4) {
                    Text("No key yet?")
                        .foregroundStyle(Theme.textTertiary)
                    Button("Get one at brave.com/search/api", action: getKey)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                }
                .font(.system(size: 13))
                Text("Your key stays in your Mac's Keychain. Max Q tries it with one search before saving it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textQuaternary)
                    .multilineTextAlignment(.center)
                Button("Not now", action: skip)
                    .pill(.ghost, size: .small)
                    .padding(.top, 12)
            }
            .frame(width: 400)
            .padding(.top, 22)
            .animation(Motion.standard(0.24), value: keyError)
            .reveal(revealed, delay: 0.3)
            Spacer(minLength: 20)
        }
        .onAppear {
            revealed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focused = true }
        }
    }
}

/// Max Q's own search, as an x.ai product card: the mark and name, what it does, and a small
/// results page that keeps building itself (the answer blurs in, results rise, a book settles).
private struct MaxQEngineCard: View {
    let selected: Bool
    let landed: Bool
    let hasKey: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 9) {
                        MaxQMark(size: 22, glow: false)
                        Text("Max Q")
                            .font(.system(size: 18, weight: .semibold))
                            .tracking(-0.3)
                        Text("Recommended")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.solar)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Capsule().fill(Theme.solar.opacity(0.1)))
                        Spacer(minLength: 0)
                    }
                    Text(hasKey
                         ? "Grok's answer with its sources, web results, Grokipedia and posts from X, together on one page."
                         : "Web results and Grokipedia on one page, with Grok's answer from grok.com beside them. Add an API key later for answers built into the page.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.textPrimary)

                GrokSearchDemo()
                    .frame(width: 168, height: 112)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.dynamic(light: Theme.hex(0xF9F8F7), dark: Theme.hex(0x131211))))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    .scaleEffect(hovering ? 1.03 : 1)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(landed ? Theme.selected : (hovering ? Theme.hover : Theme.dynamic(light: Theme.hex(0xFFFFFF), dark: Theme.hex(0x111111)))))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(selected || hovering ? Theme.borderStrong : Theme.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if selected && landed {
                    Icon(.check, size: 16)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(14)
                        .checkPop(landed)
                }
            }
            .overlay(Sheen(active: hovering).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(ChoicePress())
        .onHover { hovering = $0 }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3), value: hovering)
        .animation(Motion.spring(0.4), value: landed)
    }
}

/// A results page in miniature, building itself on a loop: the answer's lines blur in, two
/// results rise under it, and a small book settles in the side column.
private struct GrokSearchDemo: View {
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Capsule().fill(Theme.textTertiary.opacity(0.7)).frame(width: 26, height: 4)
                }
                .foregroundStyle(Theme.textSecondary)
                ForEach(0..<3, id: \.self) { line in
                    if phase > line {
                        Capsule().fill(Theme.textSecondary.opacity(0.55))
                            .frame(width: [86, 92, 58][line], height: 4)
                            .transition(.blurFade(radius: 3))
                    }
                }
                Spacer(minLength: 4)
                ForEach(0..<2, id: \.self) { row in
                    if phase > 3 + row {
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(Theme.link.opacity(0.75)).frame(width: [70, 62][row], height: 4)
                            Capsule().fill(Theme.textTertiary.opacity(0.45)).frame(width: [92, 80][row], height: 3)
                        }
                        .transition(.rise)
                    }
                }
            }
            .frame(width: 96, alignment: .leading)
            VStack {
                if phase > 2 {
                    GrokipediaBook(title: "Mars", width: 34, height: 48)
                        .transition(.blurFade(radius: 4).combined(with: .offset(y: 6)))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.spring(0.5), value: phase)
        .task {
            while !Task.isCancelled {
                for (next, pause) in [(1, 0.5), (2, 0.25), (3, 0.25), (4, 0.4), (5, 0.25), (5, 2.6), (0, 0.5)] {
                    try? await Task.sleep(for: .seconds(pause))
                    if Task.isCancelled { return }
                    phase = next
                }
            }
        }
    }
}

/// Where you are in setup: three small dots in the top bar, the current one stretched into a pill.
private struct StepDots: View {
    let step: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...count, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Theme.textPrimary : (index < step ? Theme.textTertiary : Theme.selected))
                    .frame(width: index == step ? 18 : 6, height: 6)
            }
        }
        .animation(Motion.glide, value: step)
        .accessibilityLabel("Step \(step) of \(count)")
    }
}

// MARK: - Pieces

/// A centered title and line, as on accounts.x.ai: the title's words tip up into place.
private struct SceneTitle: View {
    let title: String
    let detail: String
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 16) {
            FlipText(text: title, font: .hero(40), size: 40, delay: 0.05)
                .tracking(-0.6)
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(revealed, delay: 0.14)
        }
        .onAppear { revealed = true }
    }
}

/// accounts.x.ai's outlined capsule choice. The chosen one fills and a check lands at its end.
private struct ChoiceCapsule<Label: View>: View {
    let selected: Bool
    let landed: Bool
    var height: CGFloat = 48
    @ViewBuilder var label: Label
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                label
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(height: height)
            .overlay(alignment: .trailing) {
                if selected {
                    Icon(.check, size: 16)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.trailing, 18)
                        .checkPop(landed)
                        .transition(.opacity)
                }
            }
            .background(Capsule().fill(landed ? Theme.selected : (hovering ? Theme.hover : .clear)))
            .overlay(Capsule().strokeBorder(selected || hovering ? Theme.borderStrong : Theme.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(ChoicePress())
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.spring(0.4), value: landed)
    }
}

private struct ChoicePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Scenes rise in out of a slight blur and leave upward, fading (x.ai's blur-in, Grokipedia's
/// card exit).
private struct SceneTransition: ViewModifier {
    /// -1 arriving, 0 shown, 1 leaving.
    let phase: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - abs(phase))
            .offset(y: phase < 0 ? 18 : -22 * phase)
            .blur(radius: abs(phase) * 8)
    }
}

extension AnyTransition {
    fileprivate static var welcomeScene: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: SceneTransition(phase: -1), identity: SceneTransition(phase: 0)),
            removal: .modifier(active: SceneTransition(phase: 1), identity: SceneTransition(phase: 0))
        )
    }
}
