//
//  GrokPanelView.swift
//  Max Q
//
//  The Grok side panel, built like grok.com's own chat. Its pages:
//    - Chat: native, streaming, through the user's own SpaceXAI API key. Reads the page or all
//      tabs when the user asks, and can search the web and X.
//    - grok.com: the real site in the panel, signed in with the user's own Grok account.
//    - On X: what X is saying about the page on screen.
//    - Agent: Grok doing a task in the tab, step by step, asking before anything that counts.
//  The user's messages sit in grok.com's rounded bubbles, Grok's answers run as plain text that
//  clears out of a slight blur as it streams, "Thinking" shimmers, and the composer is grok.com's:
//  attach on the left, the model as a word and a chevron, Grok's blue send button (white with a
//  stop square while it answers).
//

import SwiftUI

struct GrokPanelView: View {
    @Bindable var browser: BrowserModel
    @Namespace private var segment

    private var account: GrokAccount { browser.grokAccount }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Group {
                if browser.panelShowsAgent {
                    if account.hasKey {
                        AgentView(browser: browser, agent: browser.agent)
                    } else {
                        GrokKeySetupView(browser: browser)
                    }
                } else if browser.panelShowsX {
                    PanelXView(browser: browser)
                        .id(browser.spaceVersion)
                } else {
                    switch browser.grokPanelMode {
                    case .web:
                        GrokWebPanelHost(panel: browser.grokWebPanel)
                            .id(browser.spaceVersion)
                    case .native:
                        if account.hasKey {
                            GrokChatView(browser: browser, session: browser.grok)
                        } else {
                            GrokKeySetupView(browser: browser)
                        }
                    }
                }
            }
            .transition(.blurFade())
        }
        .background(browser.isPrivate ? Theme.privateSurface : Theme.surface)
        .animation(Motion.smooth, value: browser.grokPanelMode)
        .animation(Motion.smooth, value: browser.panelShowsX)
        .animation(Motion.smooth, value: browser.panelShowsAgent)
    }

    private var header: some View {
        HStack(spacing: 4) {
            modePicker
            Spacer(minLength: 4)

            if !browser.panelShowsX && !browser.panelShowsAgent && browser.grokPanelMode == .native && account.hasKey && browser.grok.sessionCostUSD > 0 {
                Text(GrokAccount.formatCost(browser.grok.sessionCostUSD))
                    .font(.mono(11.5, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
                    .tip("What this conversation has cost on your SpaceXAI account")
                    .padding(.trailing, 4)
            }

            if browser.panelShowsAgent {
                if account.hasKey {
                    Button { withAnimation(Motion.smooth) { browser.agent.reset() } } label: { Icon(.compose, size: 18) }
                        .iconButton(size: 32)
                        .tip("New task")
                        .accessibilityLabel("New Task")
                        .disabled(!browser.agent.hasRun || browser.agent.isActive)
                }
            } else if browser.panelShowsX {
                Button { browser.xPanelSearch.reload() } label: { Icon(.reload, size: 17) }
                    .iconButton(size: 32)
                    .tip("Check for new posts")
                    .accessibilityLabel("Reload Posts")
            } else if browser.grokPanelMode == .native && account.hasKey {
                Button { withAnimation(Motion.smooth) { browser.grok.clear() } } label: { Icon(.compose, size: 18) }
                    .iconButton(size: 32)
                    .tip("New chat")
                    .accessibilityLabel("New Chat")
                    .disabled(browser.grok.messages.isEmpty)
            } else if browser.grokPanelMode == .web {
                Button { browser.grokWebPanel.goHome() } label: { Icon(.house, size: 18) }
                    .iconButton(size: 32)
                    .tip("grok.com home")
                    .accessibilityLabel("grok.com Home")
            }

            Button {
                withAnimation(Motion.smooth) { browser.grokPanelVisible = false }
            } label: { Icon(.close, size: 16) }
                .iconButton(size: 32)
                .tip("Hide Grok", shortcut: "⌘J")
                .accessibilityLabel("Hide Grok")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 52)
    }

    /// x.ai's code tabs: words in pills, the selection gliding between them. Chat and grok.com
    /// are Grok; On X is what X is saying about the page; Agent is Grok doing a task in the tab.
    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(["chat", "web", "x", "agent"], id: \.self) { page in
                let selected = switch page {
                case "agent": browser.panelShowsAgent
                case "x": browser.panelShowsX && !browser.panelShowsAgent
                default: !browser.panelShowsX && !browser.panelShowsAgent
                    && browser.grokPanelMode == (page == "chat" ? .native : .web)
                }
                Button {
                    withAnimation(Motion.glide) {
                        switch page {
                        case "agent":
                            browser.panelShowsX = false
                            browser.panelShowsAgent = true
                        case "x":
                            browser.panelShowsAgent = false
                            browser.panelShowsX = true
                        case "chat": browser.grokPanelMode = .native
                        default: browser.grokPanelMode = .web
                        }
                    }
                } label: {
                    Text(page == "chat" ? "Chat" : page == "web" ? "grok.com" : page == "x" ? "On X" : "Agent")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background {
                            if selected {
                                Capsule().fill(Theme.selected)
                                    .matchedGeometryEffect(id: "thumb", in: segment)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .tip(page == "chat" ? "Grok with your API key" : page == "web" ? "grok.com with your Grok account"
                     : page == "x" ? "What X is saying about this page" : "Grok does a task in this tab")
            }
        }
    }
}

// MARK: - grok.com mode

struct GrokWebPanelHost: View {
    let panel: GrokWebPanel

    var body: some View {
        PlainWebViewHost(webView: panel.container)
            .onAppear { panel.loadIfNeeded() }
    }
}

// MARK: - Chat

struct GrokChatView: View {
    @Bindable var browser: BrowserModel
    @Bindable var session: GrokSession
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if session.messages.isEmpty {
                            GrokEmptyState(browser: browser)
                                .padding(.top, 28)
                        }
                        ForEach(session.messages) { message in
                            ChatMessageView(browser: browser, session: session, message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .modifier(active: MessageEntry(shown: false, trailing: message.role == .user),
                                                         identity: MessageEntry(shown: true, trailing: message.role == .user)),
                                    removal: .opacity))
                        }
                        Color.clear.frame(height: 4).id("bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .animation(Motion.overshoot(0.42), value: session.messages.count)
                }
                .scrollIndicators(.never)
                .scrollEdgeFade()
                .onChange(of: session.scrollTrigger) { _, _ in
                    withAnimation(Motion.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: session.messages.last?.text.count ?? 0) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            GrokComposer(browser: browser, session: session, focused: $composerFocused)
        }
        .onChange(of: browser.composerFocusRequest) { _, _ in
            browser.window?.makeFirstResponder(nil)
            DispatchQueue.main.async { composerFocused = true }
        }
        .onAppear {
            if session.messages.isEmpty {
                DispatchQueue.main.async { composerFocused = true }
            }
        }
    }
}

/// x.ai's chat entries: up 8 points from 97%, with a hair of overshoot.
private struct MessageEntry: ViewModifier {
    let shown: Bool
    let trailing: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.97, anchor: trailing ? .bottomTrailing : .bottomLeading)
            .offset(y: shown ? 0 : 8)
    }
}

private struct GrokEmptyState: View {
    @Bindable var browser: BrowserModel
    @State private var revealed = false

    private var onPage: Bool { !(browser.selectedTab?.isHome ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("What do you want to ")
                    Text("know?")
                        .overlay(alignment: .bottom) {
                            SpectrumLine(height: 2).offset(y: 4)
                        }
                }
                .font(.heading(22))
                .tracking(-0.44)
                .foregroundStyle(Theme.textPrimary)
                .reveal(revealed)
                Text("Grok answers with your own key and can read this page, your tabs, the web and X when you ask.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(revealed, delay: 0.06)
            }

            VStack(alignment: .leading, spacing: 8) {
                if onPage {
                    suggestion(String(localized: "Summarize this page"), icon: .lines, delay: 0.12) { browser.summarizeCurrentPage() }
                    suggestion(String(localized: "What is X saying about it?"), icon: .bubble, delay: 0.15) { browser.whatXSays() }
                    suggestion(String(localized: "Translate this page"), icon: .translate, delay: 0.18) {
                        if let tab = browser.selectedTab { browser.translator.toggle(tab) }
                    }
                }
                if browser.tabs.filter({ !$0.isHome }).count > 1 {
                    suggestion(String(localized: "Summarize all my tabs"), icon: .stack, delay: 0.21) { browser.summarizeAllTabs() }
                }
                suggestion(String(localized: "What's happening on X right now?"), icon: .bolt, delay: 0.24) {
                    browser.grok.ask(String(localized: "What are the biggest stories people are talking about on X right now? Give me a quick rundown with links."))
                }
            }

            Text("Tip: select text on any page and right-click to explain, translate or rewrite it with Grok.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(revealed, delay: 0.3)
        }
        .onAppear { revealed = true }
    }

    private func suggestion(_ title: String, icon: MQIcon, delay: Double, action: @escaping () -> Void) -> some View {
        SuggestionChip(title: title, icon: icon, action: action)
            .reveal(revealed, delay: delay, distance: 6)
    }
}

/// grok.com's suggestion chip: an outlined pill with a glyph that brightens on hover.
private struct SuggestionChip: View {
    let title: String
    let icon: MQIcon
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Icon(icon, size: 16)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 15)
            .frame(height: 36)
            .background(Capsule().fill(hovering ? Theme.hover : .clear))
            .overlay(Capsule().strokeBorder(hovering ? Theme.borderStrong : Theme.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

struct ChatMessageView: View {
    @Bindable var browser: BrowserModel
    @Bindable var session: GrokSession
    let message: ChatMessage
    @State private var copied = false

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: answer
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(message.text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.selected))
            if !message.attachments.isEmpty {
                HStack(spacing: 5) {
                    Icon(.attach, size: 12)
                    Text(message.attachments.count == 1
                         ? GrokSession.preview(message.attachments[0], limit: 40)
                         : String(localized: "\(message.attachments.count) pages"))
                        .lineLimit(1)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let status = message.statusLine, message.state == .streaming {
                ShimmerText(text: GrokStatusText.display(status), font: .system(size: 14), base: Theme.textSecondary.opacity(0.6))
                    .id(status)
                    .transition(.statusSwap)
                .transition(.blurFade())
            }

            if !message.text.isEmpty {
                MarkdownText(text: message.text, fontSize: 14, streaming: message.state == .streaming,
                             allowsTabLinks: !message.tabLinks.isEmpty || message.videoTab != nil) { url in
                    if url.scheme == MarkdownParser.seekLinkScheme {
                        // "maxq-seek://190": the video the answer is about, from 3:10.
                        if let seconds = Double(url.host ?? ""), let id = message.videoTab,
                           let tab = browser.allTabs.first(where: { $0.id == id }), let webView = tab.webView {
                            browser.select(tab)
                            Task { await VideoPages.seek(webView, to: seconds) }
                        }
                    } else if url.scheme == MarkdownParser.tabLinkScheme {
                        // "maxq-tab://2": the second tab sent with the question, if it's still open.
                        if let number = Int(url.host ?? ""), message.tabLinks.indices.contains(number - 1),
                           let tab = browser.allTabs.first(where: { $0.id == message.tabLinks[number - 1] }) {
                            browser.select(tab)
                        }
                    } else {
                        browser.openInNewTab(url)
                    }
                }
            }

            if case .failed(let error) = message.state {
                HStack(alignment: .top, spacing: 10) {
                    Icon(.warning, size: 16).foregroundStyle(Theme.warning)
                    Text(error)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 13))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.hover))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            }

            if !message.citations.isEmpty && message.state != .streaming {
                SourcesRow(citations: message.citations) { browser.openInNewTab($0) }
                    .transition(.blurFade())
            }

            if message.replaceTarget != nil && message.state == .done {
                HStack(spacing: 8) {
                    Button(message.applied ? "Replaced" : "Replace selection") { session.apply(message) }
                        .pill(.primary, size: .mini)
                        .disabled(message.applied)
                    Button("Copy") { copy() }
                        .pill(.outline, size: .mini)
                }
            }

            if message.state != .streaming {
                footer
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.standard(0.24), value: message.statusLine)
        .animation(Motion.standard(0.24), value: message.state)
    }

    /// grok.com's row of actions under an answer.
    private var footer: some View {
        HStack(spacing: 2) {
            if !message.text.isEmpty {
                Button { copy() } label: {
                    ZStack {
                        if copied {
                            Icon(.check, size: 15).transition(.glyphSwap)
                        } else {
                            Icon(.copy, size: 15).transition(.glyphSwap)
                        }
                    }
                }
                .iconButton(size: 28)
                .tip(copied ? "Copied" : "Copy")
                .accessibilityLabel("Copy Answer")
            }
            Text(footerText)
                .font(.mono(11, weight: .regular))
                .foregroundStyle(Theme.textQuaternary)
                .lineLimit(1)
                .padding(.leading, 6)
            Spacer()
        }
        .padding(.leading, -6)
    }

    private var footerText: String {
        var parts: [String] = []
        if message.state == .stopped { parts.append("stopped") }
        if let model = message.model { parts.append(UsageLine.modelName(model)) }
        if let cost = message.costUSD { parts.append(GrokAccount.friendlyCost(cost)) }
        return parts.joined(separator: " · ")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GrokSession.stripQuotes(message.text), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }
}

/// grok.com's sources: the count, then a row of site chips.
private struct SourcesRow: View {
    let citations: [GrokCitation]
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Sources", trailing: "\(citations.count)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(citations.prefix(12).enumerated()), id: \.element.id) { index, citation in
                        Button { open(citation.url) } label: {
                            HStack(spacing: 6) {
                                if let icon = FaviconStore.shared.icon(for: citation.url.host) {
                                    SiteIcon(image: icon, tone: FaviconStore.shared.tone(for: citation.url.host), size: 13, cornerRadius: 3)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.mono(10.5, weight: .medium))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Text(Self.label(citation))
                                    .lineLimit(1)
                            }
                        }
                        .pill(.outline, size: .mini)
                        .tip(verbatim: citation.url.absoluteString)
                        .onAppear { FaviconStore.shared.prefetchIcon(forSite: URL(string: "https://\(citation.url.host ?? "")") ?? citation.url) }
                    }
                }
            }
        }
    }

    static func label(_ citation: GrokCitation) -> String {
        var host = citation.url.host ?? citation.url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host == "x.com" || host == "twitter.com" {
            let parts = citation.url.pathComponents.filter { $0 != "/" }
            if let handle = parts.first, handle != "i", handle != "search", handle != "hashtag" { return "@\(handle)" }
            return String(localized: "Post on X")
        }
        return host
    }
}

struct GrokComposer: View {
    @Bindable var browser: BrowserModel
    @Bindable var session: GrokSession
    var focused: FocusState<Bool>.Binding

    private var onPage: Bool { !(browser.selectedTab?.isHome ?? true) }
    private var multipleTabs: Bool { browser.tabs.filter({ !$0.isHome }).count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if attachmentLabel != nil {
                attachmentChip
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .transition(.pop(anchor: .bottomLeading))
            }

            TextField(placeholder, text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...8)
                .focused(focused)
                .onSubmit { session.sendDraft() }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 10)

            HStack(spacing: 4) {
                attachMenu
                Button {
                    withAnimation(Motion.snappy) { session.searchEnabled.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Icon(.globe, size: 15)
                        Text("Web & X")
                    }
                }
                .pill(session.searchEnabled ? .secondary : .ghost, size: .mini)
                .tip(session.searchEnabled ? "Grok can search the web and X" : "Grok won't search")
                Spacer(minLength: 4)
                modelMenu
                sendButton
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous).fill(Theme.input))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous)
                .strokeBorder(focused.wrappedValue ? Theme.border : Theme.composerBorder, lineWidth: 1)
        )
        .elevation(.composer)
        .padding(12)
        .animation(Motion.standard(0.18), value: focused.wrappedValue)
        .animation(Motion.spring(0.4), value: attachmentLabel)
    }

    private var placeholder: String {
        if session.includeAllTabs && multipleTabs { return String(localized: "Ask about your open tabs") }
        if session.includePage && onPage { return String(localized: "Ask about this page") }
        return String(localized: "What do you want to know?")
    }

    private var attachmentLabel: String? {
        if session.includeAllTabs && multipleTabs { return String(localized: "All tabs · \(browser.tabs.filter { !$0.isHome }.count)") }
        if session.includePage && onPage, let tab = browser.selectedTab { return tab.displayTitle }
        return nil
    }

    private var attachmentChip: some View {
        HStack(spacing: 6) {
            Icon(session.includeAllTabs ? .stack : .doc, size: 14)
            Text(attachmentLabel ?? "")
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Button {
                withAnimation(Motion.snappy) {
                    session.includeAllTabs = false
                    session.includePage = false
                }
            } label: { Icon(.close, size: 11) }
                .iconButton(size: 20)
                .tip("Don't attach")
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(Capsule().fill(Theme.hover))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var attachMenu: some View {
        MenuButton(placement: .above(.leading)) { isOpen in
            // The plus turns into a cross while the menu is open.
            MorphIcon(isOpen ? .close : .plus, size: 18)
        } content: {
            MenuCard(width: 236) {
                MenuRow(icon: .doc, title: "Attach this page",
                        checked: session.includePage && !session.includeAllTabs, enabled: onPage) {
                    session.includePage.toggle()
                    if session.includePage { session.includeAllTabs = false }
                }
                MenuRow(icon: .stack, title: "Attach all tabs", checked: session.includeAllTabs, enabled: multipleTabs) {
                    session.includeAllTabs.toggle()
                }
            }
        }
        .iconButton(size: 32)
        .tip("Attach the page or your tabs")
        .accessibilityLabel("Attach")
    }

    private var modelMenu: some View {
        EffortMenuButton()
    }

    @ViewBuilder
    private var sendButton: some View {
        ZStack {
            if session.isResponding {
                Button { session.stop() } label: { Icon(.stop, size: 16) }
                    .stopButton(size: 34)
                    .tip("Stop")
                    .accessibilityLabel("Stop Answer")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Button { session.sendDraft() } label: { Icon(.arrowUp, size: 18, weight: 2.2) }
                    .sendButton(size: 34)
                    .disabled(!canSend)
                    .tip("Send", shortcut: "↩")
                    .accessibilityLabel("Send")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(Motion.pop, value: session.isResponding)
    }

    private var canSend: Bool {
        !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Key setup

struct GrokKeySetupView: View {
    @Bindable var browser: BrowserModel
    @State private var key = ""
    @State private var error: String?
    @State private var checking = false
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your key")
                        .font(.heading(22))
                        .tracking(-0.44)
                        .foregroundStyle(Theme.textPrimary)
                        .reveal(revealed)
                    Text("Chat, summaries, X search, translation and rewriting run on SpaceXAI's API with your own key. Requests go straight from this Mac to SpaceXAI. There's no Max Q server, and the key stays in your Keychain.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .reveal(revealed, delay: 0.06)
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 16) {
                    step(1, String(localized: "Create a key at console.x.ai. Usage is billed to your SpaceXAI account.")) {
                        Button {
                            if let url = URL(string: "https://console.x.ai") { browser.openInNewTab(url) }
                        } label: {
                            HStack(spacing: 5) { Text("Open console.x.ai"); Icon(.arrowUpRight, size: 13) }
                        }
                        .pill(.outline, size: .mini)
                    }
                    step(2, String(localized: "Paste it here.")) {
                        HStack(spacing: 8) {
                            SecureField("xai-…", text: $key)
                                .textFieldStyle(.plain)
                                .font(.mono(13, weight: .regular))
                                .onSubmit(save)
                            if checking {
                                ShimmerText(text: String(localized: "Checking"), font: .system(size: 12.5, weight: .medium))
                            }
                            Button(action: save) { Icon(.arrowUp, size: 16, weight: 2.2) }
                                .sendButton(size: 30)
                                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                                .accessibilityLabel("Connect")
                        }
                        .padding(.leading, 14)
                        .padding(.trailing, 4)
                        .frame(height: 38)
                        .background(Capsule().fill(Theme.input))
                        .overlay(Capsule().strokeBorder(Theme.composerBorder, lineWidth: 1))
                    }
                    if let error {
                        Text(error)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.warning)
                            .padding(.leading, 34)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.blurFade())
                    }
                }
                .reveal(revealed, delay: 0.12)

                Rectangle().fill(Theme.hairline).frame(height: 1)

                VStack(alignment: .leading, spacing: 10) {
                    Text("No API key?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Use grok.com in this panel with your Grok account instead. It's free with your account and needs no key.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Use grok.com") { withAnimation(Motion.smooth) { browser.grokPanelMode = .web } }
                        .pill(.secondary, size: .small)
                        .padding(.top, 2)
                }
                .reveal(revealed, delay: 0.18)
            }
            .padding(20)
        }
        .onAppear { revealed = true }
        .animation(Motion.standard(0.2), value: error)
    }

    private func step<Content: View>(_ number: Int, _ text: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", number))
                .font(.mono(11.5, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 22, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
    }

    private func save() {
        let candidate = key
        checking = true
        error = nil
        Task {
            let failure = await browser.grokAccount.setKey(candidate)
            checking = false
            if let failure {
                withAnimation(Motion.standard(0.2)) { error = failure }
            } else {
                key = ""
            }
        }
    }
}
