//
//  BrowserWindow.swift
//  Max Q
//
//  One browser window, laid out like grok.com: the sidebar sits straight on the window, the
//  toolbar runs above the page, and the page and the Grok panel are flat cards with a hairline
//  edge, in grok.com's page color.
//

import AppKit
import SwiftUI

struct BrowserWindow: View {
    @State private var browser: BrowserModel
    @FocusState private var addressFieldFocused: Bool
    @State private var showingWelcome = false
    /// Setup brought back from Settings, over tabs already in use.
    @State private var revisitingSetup = false

    init(isPrivate: Bool) {
        _browser = State(initialValue: BrowserModel(isPrivate: isPrivate))
        _showingWelcome = State(initialValue: !isPrivate && !AppSettings.shared.hasCompletedOnboarding)
    }

    private let panelSpring = Motion.smooth

    var body: some View {
        ZStack {
            if showingWelcome {
                // First run takes the whole window; the browser lifts in behind it when it's done.
                WelcomeView(browser: browser, revisiting: revisitingSetup, finish: finishWelcome)
                    .transition(.launchFade(scale: 1.05))
                    .zIndex(1)
            } else {
                browserLayout
                    .transition(.launchFade(scale: 0.975))
            }
        }
        .background(browser.isPrivate ? Theme.privateCanvas : Theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 480)
        .background(WindowAccessor { window in
            guard let window, browser.window !== window else { return }
            browser.window = window
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.title = browser.isPrivate ? String(localized: "Private") : "Max Q"
            BrowserRegistry.register(browser)
        })
        .focusedSceneValue(\.browser, browser)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window = note.object as? NSWindow, window === browser.window {
                BrowserRegistry.markActive(browser)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            // A tab preview never outlives the window's focus.
            if let window = note.object as? NSWindow, window === browser.window { browser.peek = nil }
        }
        .onChange(of: browser.setupRequest) { _, _ in
            guard !browser.isPrivate else { return }
            revisitingSetup = true
            browser.dismissSuggestions()
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)) { showingWelcome = true }
        }
        .onChange(of: browser.focusAddressRequest) { _, _ in
            browser.window?.makeFirstResponder(nil)
            DispatchQueue.main.async { addressFieldFocused = true }
        }
        .onChange(of: addressFieldFocused) { _, focused in
            browser.addressFocused = focused
            if focused {
                browser.addressTextChanged()
            } else {
                // Let a click on a suggestion land before the list disappears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    if !addressFieldFocused {
                        browser.dismissSuggestions()
                        browser.syncAddressText()
                    }
                }
            }
        }
        .onChange(of: browser.addressFocused) { _, focused in
            if addressFieldFocused != focused { addressFieldFocused = focused }
        }
        .sheet(item: $browser.botHandoff) { handoff in
            BotHandoffSheet(browser: browser, handoff: handoff)
        }
        .sheet(item: $browser.botEmailSetup) { setup in
            BotEmailSetupSheet(setup: setup)
        }
        .sheet(isPresented: $browser.showingImport) {
            ImportView()
        }
        .sheet(item: $browser.researchDraft) { draft in
            ResearchSheet(browser: browser, draft: draft)
        }
        .sheet(item: $browser.shareAnswer) { draft in
            ShareAnswerSheet(browser: browser, draft: draft)
        }
        // Links from other apps open here as tabs (private windows never take them).
        .handlesExternalEvents(preferring: browser.isPrivate ? [] : ["*"], allowing: browser.isPrivate ? [] : ["*"])
        .onOpenURL { url in
            guard !browser.isPrivate, ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { return }
            // A link that launches Max Q can arrive before the window appears: bring the last
            // session back first, so the link joins it instead of replacing it.
            browser.restoreSavedSession()
            browser.open(url)
            browser.window?.makeKeyAndOrderFront(nil)
        }
        .onAppear {
            browser.restoreSavedSession()
            #if DEBUG
            // Test copies open straight onto a results page: `-MaxQOpenSearch "starship"`.
            if !browser.isPrivate, let query = UserDefaults.standard.string(forKey: "MaxQOpenSearch"), !query.isEmpty {
                // `-MaxQSearchTab x` (or grokipedia, news, images, videos) opens on that tab.
                if let raw = UserDefaults.standard.string(forKey: "MaxQSearchTab"), let tab = GrokSearchTab(rawValue: raw) {
                    browser.openMaxQSearch(query, on: tab)
                } else {
                    browser.navigate(.search(query))
                }
            }
            // `-MaxQSpace "Work"`: into that space (made if it isn't there).
            if !browser.isPrivate, let name = UserDefaults.standard.string(forKey: "MaxQSpace"), !name.isEmpty {
                if name == "Personal" {
                    browser.switchSpace(to: nil)
                } else {
                    let id = SpaceStore.shared.spaces.first(where: { $0.name == name })?.id ?? SpaceStore.shared.create(name)
                    browser.switchSpace(to: id)
                }
            }
            if !browser.isPrivate, let raw = UserDefaults.standard.string(forKey: "MaxQOpenURL"), let url = URL(string: raw) {
                browser.open(url)
            }
            // And onto Max Q's own pages: `-MaxQOpenResearch "question"`, `-MaxQOpenImagine "prompt"`,
            // `-MaxQOpenCollection "name"` (with a few items in it).
            if !browser.isPrivate, let question = UserDefaults.standard.string(forKey: "MaxQOpenResearch"), !question.isEmpty {
                browser.openNative(.research(ResearchStore.shared.start(question, budget: 0.5)), inNewTab: true)
            }
            if !browser.isPrivate, let prompt = UserDefaults.standard.string(forKey: "MaxQOpenImagine") {
                ImagineStore.shared.draft = prompt.isEmpty ? nil : prompt
                browser.openNative(.imagine, inNewTab: true)
            }
            if !browser.isPrivate, let name = UserDefaults.standard.string(forKey: "MaxQOpenCollection"), !name.isEmpty {
                let store = CollectionStore.shared
                let id = store.collections.first(where: { $0.name == name })?.id ?? store.create(name)
                if store.collection(id)?.items.isEmpty == true {
                    store.add(CollectionItem(kind: .quote, title: "SpaceX", url: URL(string: "https://www.spacex.com/vehicles/starship/"),
                                             text: "Starship is the world's most powerful launch vehicle ever developed.", source: "spacex.com"), to: id)
                    store.add(CollectionItem(kind: .result, title: "SpaceX Starship - Wikipedia", url: URL(string: "https://en.wikipedia.org/wiki/SpaceX_Starship"),
                                             text: "Starship is a two-stage, fully reusable, super heavy-lift launch vehicle.", source: "en.wikipedia.org"), to: id)
                }
                browser.openNative(.collection(id), inNewTab: true)
            }
            // The agent: `-MaxQAgentTask "task"` starts it on the page `-MaxQOpenURL` opened (an
            // empty task just shows it).
            if let task = UserDefaults.standard.string(forKey: "MaxQAgentTask") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { browser.showAgent(task: task) }
            }
            #endif
            if !showingWelcome, browser.selectedTab?.isHome == true {
                browser.requestAddressFocus()
            } else {
                // macOS hands a new window's focus to its first text field: a restored page keeps
                // it instead, so the address bar doesn't open its suggestions over the page.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard browser.selectedTab?.isHome == false, addressFieldFocused else { return }
                    addressFieldFocused = false
                    browser.window?.makeFirstResponder(nil)
                }
            }
        }
    }

    private func finishWelcome() {
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)) { showingWelcome = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { revisitingSetup = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if browser.selectedTab?.isHome == true { browser.requestAddressFocus() }
        }
    }

    private var browserLayout: some View {
        HStack(spacing: 0) {
            if browser.sidebarVisible {
                TabSidebar(browser: browser)
                    .frame(width: browser.sidebarMode == .compact ? 60 : 252)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                BrowserToolbar(browser: browser, addressFocus: $addressFieldFocused)
                    .frame(height: 52)
                    .zIndex(2)

                HStack(spacing: 8) {
                    ContentArea(browser: browser, addressFocus: $addressFieldFocused)
                        .modifier(PageCard(active: browser.activeSplit == nil))
                        .zIndex(1)

                    if browser.grokPanelVisible {
                        GrokPanelView(browser: browser)
                            .frame(width: 420)
                            .modifier(PageCard())
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.leading, browser.sidebarVisible ? 0 : 8)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
        .animation(panelSpring, value: browser.sidebarVisible)
        .animation(panelSpring, value: browser.sidebarMode)
        .animation(panelSpring, value: browser.grokPanelVisible)
        .overlay(alignment: .topLeading) { peekLayer }
        .overlay {
            if browser.commandBar.isOpen {
                CommandBarView(bar: browser.commandBar)
            }
        }
        .animation(Motion.menu, value: browser.commandBar.isOpen)
    }

    /// The sidebar's tab preview, floating beside the hovered row.
    private var peekLayer: some View {
        GeometryReader { proxy in
            if let peek = browser.peek, let tab = browser.tabs.first(where: { $0.id == peek.tabID }) {
                let height: CGFloat = tab.snapshot == nil ? 70 : 250
                let y = min(max(peek.anchor.midY - height / 2, 10), proxy.size.height - height - 10)
                TabPeekCard(tab: tab)
                    .offset(x: peek.anchor.maxX + 12, y: y)
                    .transition(.pop(anchor: .leading, scale: 0.96))
                    .id("peek")
            }
        }
        .allowsHitTesting(false)
        .animation(Motion.menu, value: browser.peek)
    }
}

/// The page and the Grok panel: flat cards in grok.com's page color with a hairline edge. A split
/// draws a card for each of its panes instead.
private struct PageCard: ViewModifier {
    var active = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .clipShape(shape)
            .overlay(shape.strokeBorder(active ? Theme.hairline : .clear, lineWidth: 1).allowsHitTesting(false))
    }
}

/// Fade with a slight zoom and blur: the setup lifting away, the browser settling in.
private struct LaunchFade: ViewModifier {
    /// 0 hidden, 1 shown.
    let progress: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(1 + (1 - progress) * (scale - 1))
            .blur(radius: (1 - progress) * 14)
    }
}

extension AnyTransition {
    fileprivate static func launchFade(scale: CGFloat) -> AnyTransition {
        .modifier(active: LaunchFade(progress: 0, scale: scale), identity: LaunchFade(progress: 1, scale: scale))
    }
}

/// Reports the NSWindow a view lives in.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
