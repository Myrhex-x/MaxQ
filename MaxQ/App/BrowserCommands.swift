//
//  BrowserCommands.swift
//  Max Q
//
//  Menu bar commands. They act on the focused window's BrowserModel.
//

import AppKit
import SwiftUI

struct BrowserFocusKey: FocusedValueKey {
    typealias Value = BrowserModel
}

extension FocusedValues {
    var browser: BrowserModel? {
        get { self[BrowserFocusKey.self] }
        set { self[BrowserFocusKey.self] = newValue }
    }
}

struct BrowserCommands: Commands {
    @FocusedValue(\.browser) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { browser?.newTab() }
                .keyboardShortcut("t")
            Button("New Window") { openWindow(id: "browser") }
                .keyboardShortcut("n")
            Button("New Private Window") { openWindow(id: "private") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Open Location") { browser?.requestAddressFocus() }
                .keyboardShortcut("l")
            Button("Reopen Closed Tab") { browser?.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!(browser?.canReopenClosedTab ?? false))
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") {
                if let browser { browser.closeCurrentTab() } else { NSApp.keyWindow?.performClose(nil) }
            }
            .keyboardShortcut("w")
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find on Page") { browser?.showFindBar() }
                .keyboardShortcut("f")
            Button("Find Next") { browser?.find() }
                .keyboardShortcut("g")
            Button("Find Previous") { browser?.find(backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandGroup(before: .sidebar) {
            Button(browser?.sidebarVisible == false ? "Show Tab Sidebar" : "Hide Tab Sidebar") {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { browser?.sidebarVisible.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Button(browser?.grokPanelVisible == true ? "Hide Grok" : "Show Grok") {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { browser?.toggleGrokPanel() }
            }
            .keyboardShortcut("j")
            Divider()
            Button(browser?.selectedTab?.reader == nil ? "Show Reader" : "Hide Reader") { browser?.toggleReader() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Reload Page") { browser?.selectedTab?.reload() }
                .keyboardShortcut("r")
            Button("Stop Loading") { browser?.selectedTab?.stopLoading() }
                .keyboardShortcut(".")
            Divider()
            Button("Zoom In") { browser?.zoom(0.1) }
                .keyboardShortcut("+")
            Button("Zoom Out") { browser?.zoom(-0.1) }
                .keyboardShortcut("-")
            Button("Actual Size") { browser?.zoom(nil) }
                .keyboardShortcut("0")
            Divider()
        }

        CommandMenu("History") {
            Button("Back") { browser?.selectedTab?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(browser?.selectedTab?.canGoBack ?? false))
            Button("Forward") { browser?.selectedTab?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(browser?.selectedTab?.canGoForward ?? false))
        }

        CommandGroup(after: .newItem) {
            Button("Command Bar") { browser?.commandBar.toggle() }
                .keyboardShortcut("k")
        }

        CommandMenu("Grok") {
            Button("Ask Grok") {
                browser?.grokPanelVisible = true
                browser?.requestComposerFocus()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Check Selection with Grok") { browser?.checkSelection() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Summarize This Video") { browser?.askAboutVideo() }
            Button("Research with Grok…") { browser?.startResearch(browser?.selectedTab?.nativeSearch ?? "") }
            Button("Let Grok Do It…") { browser?.showAgent() }
            Button("Imagine…") { browser?.openNative(.imagine, inNewTab: true) }
            Button("Summarize Page") { browser?.summarizeCurrentPage() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Summarize All Tabs") { browser?.summarizeAllTabs() }
            Button("What Is X Saying About This Page?") { browser?.whatXSays() }
                .keyboardShortcut("x", modifiers: [.command, .option])
            Button("Translate Page") {
                if let browser, let tab = browser.selectedTab { browser.translator.toggle(tab) }
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("Share Page on X") { browser?.shareToX() }
            Button("Send Page to Grok Bot") { browser?.sendToBot() }
            Button("Open Grok Bot") { browser?.openGrokBot() }
            Divider()
            Button("New Grok Chat") { browser?.grok.clear() }
        }

        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show Next Tab") { browser?.selectNextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Show Previous Tab") { browser?.selectPreviousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            ForEach(1..<10) { number in
                Button(number == 9 ? "Last Tab" : "Tab \(number)") { browser?.select(index: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))))
            }
        }
    }
}
