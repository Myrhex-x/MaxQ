//
//  ContentArea.swift
//  Max Q
//
//  The page card: the new-tab page or the selected tab's web view. On a search, a row of
//  verticals sits above the results (the web, Grokipedia, X, or Grok), the way X lets one search
//  run across its tabs, and the native Grokipedia pad stands beside web results. Floating over the
//  page: find, load errors and toasts.
//

import AppKit
import SwiftUI
import WebKit

struct ContentArea: View {
    @Bindable var browser: BrowserModel
    var addressFocus: FocusState<Bool>.Binding

    /// Narrow windows show the Grokipedia pad over the page, on demand.
    @State private var cardOverlayOpen = false

    /// The pad's column only appears when the page keeps about 700 points, what search engines'
    /// result pages need without scrolling sideways.
    private static let minimumWidthForCardColumn: CGFloat = 1_060
    private static let cardColumnWidth: CGFloat = 352

    var body: some View {
        ZStack {
            (browser.activeSplit == nil ? Theme.surface : (browser.isPrivate ? Theme.privateCanvas : Theme.canvas))
            GeometryReader { proxy in
                let panes = visibleTabs
                let split = browser.activeSplit
                let usable = proxy.size.width - (split == nil ? 0 : Self.splitGap)
                let leadingWidth = (usable * (split?.ratio ?? 1)).rounded()
                // One pane or two, each kept by its tab's identity, so a page stays put (web view
                // and all) when a split opens or closes beside it.
                HStack(spacing: split == nil ? 0 : Self.splitGap) {
                    ForEach(panes) { tab in
                        pane(tab)
                            .modifier(SplitCard(inSplit: split != nil, focused: browser.selectedTabID == tab.id) {
                                browser.focusPane(tab)
                            })
                            .frame(width: split == nil ? proxy.size.width : (tab.id == split?.leading ? leadingWidth : usable - leadingWidth))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if split != nil {
                        SplitDivider(browser: browser, usable: usable)
                            .frame(width: Self.splitGap, height: proxy.size.height)
                            .offset(x: leadingWidth)
                    }
                }
            }
        }
        .animation(Motion.smooth, value: browser.activeSplit?.leading)
        .animation(Motion.smooth, value: browser.activeSplit?.trailing)
        .overlay(alignment: .topTrailing) {
            if browser.findBarVisible {
                FindBar(browser: browser)
                    .padding(12)
                    .transition(.pop(anchor: .topTrailing, scale: 0.95))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = browser.toast {
                ToastView(toast: toast) { browser.toast = nil }
                    .padding(.bottom, 20)
                    .transition(.asymmetric(insertion: .modifier(active: ToastEntrance(shown: false), identity: ToastEntrance(shown: true)),
                                            removal: .opacity.combined(with: .scale(scale: 0.96))))
                    .id(toast.id)
            }
        }
        .animation(Motion.outQuint(0.4), value: browser.toast?.id)
        .animation(Motion.menu, value: browser.findBarVisible)
        .onChange(of: browser.selectedTabID) { _, _ in cardOverlayOpen = false }
    }

    static let splitGap: CGFloat = 8

    /// The tabs on screen: the selected one, or both halves of its split.
    private var visibleTabs: [BrowserTab] {
        if let split = browser.activeSplit,
           let leading = browser.allTabs.first(where: { $0.id == split.leading }),
           let trailing = browser.allTabs.first(where: { $0.id == split.trailing }) {
            return [leading, trailing]
        }
        return browser.selectedTab.map { [$0] } ?? []
    }

    /// A tab's page: the new-tab page, or the web view with what goes with it.
    @ViewBuilder
    private func pane(_ tab: BrowserTab) -> some View {
        if tab.isHome {
            HomeView(browser: browser, tab: tab, addressFocus: addressFocus)
                .transition(.opacity)
        } else {
            page(tab)
        }
    }

    @ViewBuilder
    private func page(_ tab: BrowserTab) -> some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= Self.minimumWidthForCardColumn
            VStack(spacing: 0) {
                if tab.searchQuery != nil, tab.nativeSearch == nil {
                    SearchVerticalBar(browser: browser, tab: tab)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                HStack(spacing: 0) {
                    ZStack {
                        WebViewHost(tab: tab, version: tab.webViewVersion)
                        if let query = tab.nativeSearch {
                            // Grok's own results page, drawn over the tab's empty maxq:// page.
                            GrokSearchPage(browser: browser, tab: tab, query: query, opening: tab.nativeSearchTab)
                                .transition(.opacity)
                        } else if let page = tab.nativePage {
                            NativePageView(browser: browser, page: page)
                                .transition(.opacity)
                        } else if let reader = tab.reader {
                            WebReaderView(browser: browser, tab: tab, phase: reader)
                                .transition(.opacity.combined(with: .scale(scale: 0.995)))
                        }
                        if let error = tab.loadError {
                            LoadErrorView(error: error) { tab.retry() }
                                .transition(.opacity)
                        }
                    }
                    .overlay { AgentWorkingOverlay(agent: browser.agent, tab: tab) }
                    if wide, tab.nativeSearch == nil, tab.nativePage == nil, showsCardColumn(for: tab) {
                        cardColumn
                            .frame(width: Self.cardColumnWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if tab.nativeSearch == nil, tab.nativePage == nil {
                        cardAccessory(tab: tab, wide: wide)
                            .padding(12)
                    }
                }
            }
            .animation(Motion.smooth, value: cardState)
            .animation(Motion.smooth, value: tab.searchQuery != nil)
            .animation(Motion.standard(0.18), value: tab.nativeSearch)
        }
    }

    // MARK: Grokipedia

    private var cardState: GrokipediaPanelModel.State { browser.grokipedia.state }

    private func showsCardColumn(for tab: BrowserTab) -> Bool {
        guard tab.searchQuery != nil, tab.searchVertical == .web else { return false }
        switch cardState {
        case .loading, .ready: return true
        default: return false
        }
    }

    private var cardColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch cardState {
                case .loading:
                    GrokipediaCardSkeleton()
                case .ready(let card):
                    cardView(card)
                        .id(card.articleURL)
                        .transition(.card)
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollEdgeFade()
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }

    private func cardView(_ card: GrokipediaCard) -> some View {
        GrokipediaCardView(
            card: card,
            onOpen: { browser.openInNewTab($0) },
            onAskGrok: { title in
                cardOverlayOpen = false
                browser.askGrok(String(localized: "Tell me about \(title)."))
            },
            onClose: {
                cardOverlayOpen = false
                browser.grokipedia.dismiss(card.query)
            }
        )
    }

    /// Over the page: "look this up" when the pad isn't automatic, or the pad itself on demand
    /// when the window is too narrow for its column.
    @ViewBuilder
    private func cardAccessory(tab: BrowserTab, wide: Bool) -> some View {
        if let query = tab.searchQuery, tab.searchVertical == .web, browser.settings.grokipediaMode != .off {
            switch cardState {
            case .idle where !browser.grokipedia.isDismissed(query)
                && KnowledgeQueryDetector.classify(query) != .none:
                GrokipediaChip(title: String(localized: "Look up on Grokipedia")) { browser.grokipedia.request(query) }
                    .transition(.pop(anchor: .topTrailing))
            case .ready(let card) where !wide:
                // The chip grows into the pad (and shrinks back into it), the way grok.com's
                // panels grow out of the control that opens them.
                GrowingPad(title: card.title, open: $cardOverlayOpen) { cardView(card) }
            case .loading where !wide:
                GrokipediaChip(title: String(localized: "Reading Grokipedia"), loading: true) {}
                    .disabled(true)
            default:
                EmptyView()
            }
        }
    }
}

/// A chip that grows into the Grokipedia pad: one shape whose size and corners animate from the
/// chip's capsule to the pad's card over 0.3 s on the expo curve, the pad's content fading in a
/// beat after its shape.
private struct GrowingPad<Content: View>: View {
    let title: String
    @Binding var open: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: open ? Theme.Radius.menu : 18, style: .continuous)
        ZStack(alignment: .topTrailing) {
            if open {
                ScrollView(.vertical, showsIndicators: false) {
                    content.padding(20)
                }
                .scrollEdgeFade()
                .frame(width: 360)
                .frame(maxHeight: 640)
                .transition(.opacity.animation(Motion.standard(0.22).delay(0.06)))
            } else {
                Button {
                    open = true
                } label: {
                    HStack(spacing: 7) {
                        Icon(.book, size: 15)
                        Text(title).lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.animation(.linear(duration: 0.08)))
            }
        }
        .background(shape.fill(open ? Theme.elevated : Theme.pill))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
        .animation(Motion.grow, value: open)
    }
}

// MARK: - Search verticals

/// The row above search results: the same search on the web, in Grokipedia or on X, or put to
/// Grok. The selection glides like grok.com's segmented controls.
private struct SearchVerticalBar: View {
    @Bindable var browser: BrowserModel
    @Bindable var tab: BrowserTab
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SearchVertical.allCases) { vertical in
                verticalButton(vertical)
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18).padding(.horizontal, 6)
            Button {
                if let query = tab.searchQuery { browser.askGrok(query) }
            } label: {
                HStack(spacing: 6) {
                    Icon(.bubble, size: 15)
                    Text("Ask Grok")
                }
            }
            .pill(.ghost, size: .mini)
            .tip("Put this question to Grok", shortcut: "⌘↩")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func verticalButton(_ vertical: SearchVertical) -> some View {
        let selected = tab.searchVertical == vertical
        return Button {
            withAnimation(Motion.glide) { browser.switchVertical(to: vertical) }
        } label: {
            HStack(spacing: 6) {
                VerticalIcon(vertical: vertical)
                    .opacity(selected ? 1 : 0.75)
                Text(vertical == .web ? AppSettings.shared.searchEngine.name : vertical.title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .background {
                if selected {
                    Capsule().fill(Theme.selected)
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct VerticalIcon: View {
    let vertical: SearchVertical

    var body: some View {
        Group {
            if vertical == .web {
                EngineIcon(engine: AppSettings.shared.searchEngine, size: 14)
            } else if let site = vertical.iconSite, let image = FaviconStore.shared.icon(for: site.host) {
                SiteIcon(image: image, tone: FaviconStore.shared.tone(for: site.host), size: 14, cornerRadius: 3)
            } else {
                Icon(vertical == .grokipedia ? .book : .bubble, size: 15)
            }
        }
        .frame(width: 16, height: 16)
        .onAppear { if let site = vertical.iconSite { FaviconStore.shared.prefetchIcon(forSite: site) } }
    }
}

// MARK: - Web view hosting

/// Hosts the selected tab's WKWebView. One container view; the tab's web view is swapped in
/// whenever the selection (or the tab's web view) changes.
struct WebViewHost: NSViewRepresentable {
    let tab: BrowserTab
    let version: Int

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let webView = tab.webView else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

/// Hosts a view owned elsewhere (the grok.com panel's web views).
struct PlainWebViewHost: NSViewRepresentable {
    let webView: NSView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

// MARK: - Over the page

struct LoadErrorView: View {
    let error: TabLoadError
    let retry: () -> Void
    @State private var revealed = false

    var body: some View {
        ZStack {
            Theme.surface
            VStack(spacing: 0) {
                Icon(.warning, size: 28, weight: 1.75)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 20)
                    .reveal(revealed)
                FlipText(text: error.title, font: .system(size: 28, weight: .semibold), size: 28)
                    .tracking(-0.56)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
                Text(error.message)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(revealed, delay: 0.12)
                if let url = error.url {
                    Text(AddressSuggestion.displayURL(url))
                        .font(.mono(12, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 440)
                        .padding(.top, 10)
                        .reveal(revealed, delay: 0.16)
                }
                Button("Try again", action: retry)
                    .pill(.primary, size: .large)
                    .padding(.top, 26)
                    .reveal(revealed, delay: 0.22)
            }
            .padding(32)
        }
        .onAppear { revealed = true }
    }
}

/// grok.com-style find bar: a floating pill with the field and round buttons.
struct FindBar: View {
    @Bindable var browser: BrowserModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Icon(.search, size: 16)
                .foregroundStyle(Theme.textTertiary)
                .padding(.trailing, 4)
            TextField("Find on page", text: $browser.findText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .frame(width: 200)
                .focused($focused)
                .onSubmit { browser.find() }
                .onChange(of: browser.findText) { _, _ in browser.find() }
                .onKeyPress(.escape) {
                    browser.closeFindBar()
                    return .handled
                }
            Button { browser.find(backwards: true) } label: { Icon(.chevronUp, size: 16) }
                .iconButton(size: 28)
                .tip("Previous", shortcut: "⇧⌘G")
                .accessibilityLabel("Previous Match")
            Button { browser.find() } label: { Icon(.chevronDown, size: 16) }
                .iconButton(size: 28)
                .tip("Next", shortcut: "⌘G")
                .accessibilityLabel("Next Match")
            Button { browser.closeFindBar() } label: { Icon(.close, size: 14) }
                .iconButton(size: 28)
                .tip("Done", shortcut: "esc")
                .accessibilityLabel("Close Find")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 42)
        .background(Capsule().fill(Theme.elevated))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
        .onAppear {
            browser.window?.makeFirstResponder(nil)
            DispatchQueue.main.async { focused = true }
        }
    }
}

/// Sonner-style toast (the toasts on x.com, grok.com and x.ai): a rounded card rising from the
/// bottom edge.
struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title) {
                    action()
                    dismiss()
                }
                .pill(.primary, size: .mini)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, toast.actionTitle == nil ? 18 : 8)
        .frame(minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
        .frame(maxWidth: 560)
        .onTapGesture { if toast.action == nil { dismiss() } }
    }
}

private struct ToastEntrance: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .scaleEffect(shown ? 1 : 0.96)
    }
}

/// A pane of a split: a card of its own on the window. The pane with the keyboard keeps a firmer
/// edge and the other rests a touch darker; a click in it moves the keyboard there. Outside a
/// split it adds nothing (the window draws the page's card).
private struct SplitCard: ViewModifier {
    let inSplit: Bool
    let focused: Bool
    let focus: () -> Void

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: inSplit ? 12 : 0, style: .continuous)
        content
            .background(Theme.surface)
            .clipShape(shape)
            .overlay(shape.strokeBorder(inSplit ? (focused ? Theme.borderStrong : Theme.hairline) : .clear, lineWidth: 1)
                .allowsHitTesting(false))
            .overlay {
                if inSplit, !focused {
                    shape.fill(Color.black.opacity(0.06)).allowsHitTesting(false)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { if inSplit { focus() } })
            .animation(Motion.standard(0.18), value: focused)
    }
}

/// The gap between a split's panes: a grip that appears under the pointer; dragging it moves the
/// line between the pages, double-clicking it puts it back in the middle.
private struct SplitDivider: View {
    @Bindable var browser: BrowserModel
    let usable: CGFloat
    @State private var dragStart: CGFloat?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(hovering || dragStart != nil ? Theme.focus : Theme.border)
                .frame(width: 3, height: hovering || dragStart != nil ? 44 : 28)
                .opacity(hovering || dragStart != nil ? 1 : 0.6)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStart ?? (browser.split?.ratio ?? 0.5)
                    if dragStart == nil { dragStart = start }
                    browser.split?.ratio = min(max(start + value.translation.width / max(usable, 1), 0.22), 0.78)
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture(count: 2) {
            withAnimation(Motion.smooth) { browser.split?.ratio = 0.5 }
        }
        .animation(Motion.snappy, value: hovering)
        .animation(Motion.snappy, value: dragStart != nil)
        .accessibilityLabel("Resize the panes")
    }
}

/// One of Max Q's own pages other than search, by kind.
private struct NativePageView: View {
    @Bindable var browser: BrowserModel
    let page: NativePage

    var body: some View {
        switch page {
        case .research(let id): ResearchPage(browser: browser, id: id)
        case .collection(let id): CollectionPage(browser: browser, id: id)
        case .imagine: ImaginePage(browser: browser)
        }
    }
}
