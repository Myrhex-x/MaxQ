//
//  QuickAsk.swift
//  Max Q
//
//  Grok anywhere: a keyboard shortcut that works in every app opens a small Max Q bar over
//  whatever is on screen. Type, then Return searches with Max Q, ⌘Return asks Grok right in the
//  bar (the answer streams in under the field, and opens as a whole results page with Return),
//  and an address opens as a page. Escape, or a click elsewhere, puts it away.
//
//  The shortcut is a Carbon hot key: it needs no accessibility permission and sees no other keys.
//  Off, ⇧⌘Space (the default, clear of the system's and of Grok's own app), ⌥Space or ⌃⌥Space.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The keyboard shortcut that opens the bar from any app.
enum GlobalShortcut: String, CaseIterable, Identifiable {
    case off, commandShiftSpace, optionSpace, controlOptionSpace
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: String(localized: "Off")
        case .commandShiftSpace: "⇧⌘Space"
        case .optionSpace: "⌥Space"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .off: 0
        case .commandShiftSpace: UInt32(cmdKey | shiftKey)
        case .optionSpace: UInt32(optionKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        }
    }
}

@MainActor
final class QuickAskController {
    static let shared = QuickAskController()

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var panel: QuickAskPanel?
    private let model = QuickAskModel()

    /// Registers the shortcut chosen in Settings (or none).
    func apply(_ shortcut: GlobalShortcut) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        guard shortcut != .off else { return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { QuickAskController.shared.toggle() } }
                return noErr
            }, 1, &type, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4D515131), id: 1) // "MQQ1"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_Space), shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &reference)
        if status == noErr { hotKey = reference }
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show(with text: String = "") {
        let panel = panel ?? makePanel()
        self.panel = panel
        if !text.isEmpty { model.text = text }
        model.focusRequest += 1
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - visible.height * 0.28 - size.height))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        model.reset()
    }

    private func makePanel() -> QuickAskPanel {
        let panel = QuickAskPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 74),
                                  styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.onResignKey = { [weak self] in self?.close() }
        let hosting = QuickAskHostingView(rootView: QuickAskView(model: model) { [weak self] in self?.close() })
        hosting.onResize = { [weak panel, weak hosting] in
            guard let panel, let hosting else { return }
            let size = hosting.fittingSize
            var frame = panel.frame
            // Grow downward from the field, which stays where it is.
            frame.origin.y += frame.height - size.height
            frame.size = NSSize(width: 680, height: size.height)
            panel.setFrame(frame, display: true, animate: false)
        }
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        return panel
    }
}

final class QuickAskPanel: NSPanel {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

private final class QuickAskHostingView<Content: View>: NSHostingView<Content> {
    var onResize: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onResize?() }
    }
}

// MARK: - The bar

@MainActor
@Observable
final class QuickAskModel {
    var text = ""
    var focusRequest = 0
    /// Grok's answer, when one was asked for in the bar.
    private(set) var answer = ""
    private(set) var asking = false
    private(set) var status: String?
    private(set) var question = ""
    private(set) var cost: Double?
    @ObservationIgnored private var task: Task<Void, Never>?

    func reset() {
        task?.cancel()
        text = ""
        answer = ""
        asking = false
        status = nil
        question = ""
        cost = nil
    }

    /// Asks Grok, answering right in the bar.
    func ask() {
        let asked = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, let client = GrokAccount.shared.client else { return }
        task?.cancel()
        question = asked
        answer = ""
        cost = nil
        asking = true
        status = String(localized: "Searching")
        let account = GrokAccount.shared
        let effort = AppSettings.shared.grokEffort
        let model = account.model(for: effort)
        let request = GrokRequest(model: model, instructions: GrokSearch.instructions(searchesX: false),
                                  input: [GrokMessage(role: .user, content: asked)], tools: [.webSearch()],
                                  maxTurns: effort.searchTurns, maxOutputTokens: 700,
                                  reasoningEffort: account.reasoningEffort(effort, model: model), purpose: .answer)
        task = Task { [weak self] in
            var raw = ""
            do {
                for try await event in client.stream(request) {
                    guard let self, !Task.isCancelled else { return }
                    switch event {
                    case .textDelta(let delta):
                        raw += delta
                        self.answer = GrokSearch.splitFollowUps(raw).body
                        self.status = nil
                    case .status(let line):
                        if self.answer.isEmpty { self.status = line }
                    case .completed(let result):
                        if raw.isEmpty { raw = result.text }
                        self.answer = GrokSearch.splitFollowUps(raw, finished: true).body
                        if let cost = result.usage?.costUSD {
                            self.cost = cost
                            account.recordCost(cost)
                        }
                    case .citation:
                        break
                    }
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.answer = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self?.asking = false
            self?.status = nil
        }
    }
}

struct QuickAskView: View {
    @Bindable var model: QuickAskModel
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                MaxQMark(size: 22, glow: false)
                TextField("Search, ask Grok, or type an address", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onSubmit { submit(askingGrok: NSApp.currentEvent?.modifierFlags.contains(.command) ?? false) }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
                if !model.text.isEmpty {
                    HStack(spacing: 6) {
                        KeyHint("↩")
                        Text(isAddress ? "Open" : "Search")
                        KeyHint("⌘↩")
                        Text("Ask Grok")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            if !model.question.isEmpty {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: 10) {
                    if model.answer.isEmpty {
                        ShimmerText(text: GrokStatusText.display(model.status ?? String(localized: "Thinking")),
                                    font: .system(size: 14, weight: .medium))
                    } else {
                        ScrollView(.vertical) {
                            MarkdownText(text: model.answer, fontSize: 14.5, streaming: model.asking) { url in
                                open(url)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 340)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        if let cost = model.cost {
                            Text(GrokAccount.formatCost(cost))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Button("Open in Max Q") { openResults(model.question) }
                            .pill(.secondary, size: .mini)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 680)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(Motion.smooth, value: model.question.isEmpty)
        .animation(Motion.smooth, value: model.text.isEmpty)
        .onChange(of: model.focusRequest, initial: true) { _, _ in
            DispatchQueue.main.async { focused = true }
        }
    }

    private var isAddress: Bool {
        if case .url = AddressInput.classify(model.text) { return true }
        return false
    }

    private func submit(askingGrok: Bool) {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if askingGrok {
            if GrokAccount.shared.hasKey {
                model.ask()
            } else {
                // Without a key, grok.com in Max Q's panel.
                withBrowser { $0.askGrokOnWeb(text) }
            }
            return
        }
        switch AddressInput.classify(text) {
        case .url(let url): withBrowser { $0.openInNewTab(url) }
        default: openResults(text)
        }
    }

    private func openResults(_ query: String) {
        withBrowser { $0.openMaxQSearch(query, on: .all, inNewTab: true) }
    }

    private func open(_ url: URL) {
        withBrowser { $0.openInNewTab(url) }
    }

    /// Max Q's last window, brought to the front, or a new one.
    private func withBrowser(_ action: @escaping (BrowserModel) -> Void) {
        close()
        NSApp.activate()
        if let browser = BrowserRegistry.lastNormal {
            browser.window?.makeKeyAndOrderFront(nil)
            action(browser)
        } else {
            BrowserCommandRouter.openWindow?("browser")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let browser = BrowserRegistry.lastNormal { action(browser) }
            }
        }
    }
}

// MARK: - Services

/// Max Q in the Services menu of every app: search for the selected words, or ask Grok about them.
final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    @objc func searchWithMaxQ(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NSApp.activate()
                if let browser = BrowserRegistry.lastNormal {
                    browser.window?.makeKeyAndOrderFront(nil)
                    if case .url(let url) = AddressInput.classify(text) {
                        browser.openInNewTab(url)
                    } else {
                        browser.openMaxQSearch(String(text.prefix(300)), on: .all, inNewTab: true)
                    }
                }
            }
        }
    }

    @objc func askGrokInMaxQ(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // The bar, with the words in it, ready to ask.
                QuickAskController.shared.show(with: String(localized: "What should I know about this: \"\(GrokSession.preview(text, limit: 400))\""))
            }
        }
    }
}
