//
//  ImportView.swift
//  Max Q
//
//  Bringing bookmarks and history over, as a tray of a few steps (each its own height, the way
//  Family's trays show that something moved on): pick the browser, give Max Q its folder, see
//  what came over. The header holds the title and one icon: close on the first step, back after.
//

import AppKit
import SwiftUI

struct ImportView: View {
    enum Step: Equatable {
        case choose
        case permission(ImportSource)
        case reading(ImportSource)
        case done(ImportSource, bookmarks: Int, history: Int)
        case failed(ImportSource)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .choose

    /// Browsers on this Mac Max Q can import from.
    private var installed: [(source: ImportSource, app: URL)] {
        ImportSource.all.compactMap { source in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID).map { (source, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch step {
                case .choose: chooser
                case .permission(let source): permission(source)
                case .reading(let source): reading(source)
                case let .done(source, bookmarks, history): done(source, bookmarks: bookmarks, history: history)
                case .failed(let source): failed(source)
                }
            }
            .transition(.asymmetric(insertion: .blurFade(radius: 3).combined(with: .offset(x: 12)),
                                    removal: .opacity))
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(width: 440)
        .background(Theme.surface)
        .animation(Motion.smooth, value: step)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(title)
                .font(.heading(17))
                .tracking(-0.3)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.interpolate)
            Spacer()
            // A tray's one icon: close on the first step, back after it, the cross turning into
            // the arrow as the step changes.
            Button {
                if goesBack { step = .choose } else { dismiss() }
            } label: {
                MorphIcon(goesBack ? .arrowLeft : .close, size: 15)
            }
            .iconButton(size: 30)
            .tip(goesBack ? "Back" : "Close")
            .accessibilityLabel(goesBack ? "Back" : "Close")
        }
        .padding(.bottom, 12)
    }

    private var goesBack: Bool {
        switch step {
        case .permission, .failed: true
        default: false
        }
    }

    private var title: String {
        switch step {
        case .choose: String(localized: "Bring your browsing over")
        case .permission(let source), .reading(let source), .failed(let source): String(localized: "From \(source.name)")
        case .done: String(localized: "All set")
        }
    }

    // MARK: - Steps

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bookmarks and history, read here on this Mac. Bookmarks come back as you type in the address bar and in ⌘K. Passwords stay where they are.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 2) {
                ForEach(installed, id: \.source.id) { item in
                    SourceRow(name: item.source.name, detail: item.source.isSafari ? String(localized: "From its export") : String(localized: "Bookmarks and history"),
                              icon: NSWorkspace.shared.icon(forFile: item.app.path)) {
                        step = .permission(item.source)
                    }
                }
                SourceRow(name: String(localized: "A bookmarks file"), detail: String(localized: "The HTML file any browser exports"), icon: nil) {
                    choose(ImportSource(id: "file", name: String(localized: "a bookmarks file"), bundleID: "", folder: "Downloads"), files: true)
                }
            }
            .padding(.horizontal, -8)
        }
    }

    private func permission(_ source: ImportSource) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(source.isSafari
                 ? "In Safari, choose File, then Export Browsing Data to File, with bookmarks and history. Then choose the exported folder here."
                 : "Max Q can only read a folder you choose. Click below and \(source.name)'s folder is already open: just click Import.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Button(source.isSafari ? "Choose the export" : "Choose \(source.name)'s folder") {
                choose(source, files: source.isSafari)
            }
            .pill(.primary, size: .regular)
        }
    }

    private func reading(_ source: ImportSource) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            ShimmerText(text: String(localized: "Reading \(source.name)"), font: .system(size: 14, weight: .medium))
        }
        .padding(.vertical, 10)
    }

    private func done(_ source: ImportSource, bookmarks: Int, history: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 26) {
                figure(bookmarks, label: bookmarks == 1 ? String(localized: "bookmark") : String(localized: "bookmarks"))
                figure(history, label: history == 1 ? String(localized: "page of history") : String(localized: "pages of history"))
            }
            Text("From \(source.name). They come up as you type in the address bar and in ⌘K.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { dismiss() }
                .pill(.primary, size: .regular)
        }
    }

    private func figure(_ value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(.hero(34))
                .tracking(-0.6)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func failed(_ source: ImportSource) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(source.isSafari
                 ? "Max Q didn't find bookmarks or history there. Choose the folder Safari exported (or the files in it)."
                 : "Max Q didn't find bookmarks or history there. Choose \(source.name)'s own folder: it's already open in the panel.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { choose(source, files: source.isSafari || source.id == "file") }
                .pill(.primary, size: .regular)
        }
    }

    // MARK: - Doing it

    private func choose(_ source: ImportSource, files: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = files
        panel.allowsMultipleSelection = files
        panel.prompt = String(localized: "Import")
        panel.message = source.id == "file" ? String(localized: "Choose the bookmarks file to import.")
            : files ? String(localized: "Choose the export to import.")
            : String(localized: "Choose \(source.name)'s folder to import its bookmarks and history.")
        panel.directoryURL = BrowserImporter.realHome.appendingPathComponent(source.folder, isDirectory: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        step = .reading(source)
        Task.detached(priority: .userInitiated) {
            var result = ImportResult()
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                let found = BrowserImporter.read(url)
                result.bookmarks += found.bookmarks
                result.history += found.history
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            let read = result
            await MainActor.run {
                guard !read.isEmpty else {
                    step = .failed(source)
                    return
                }
                let bookmarks = BookmarkStore.shared.add(read.bookmarks)
                let history = HistoryStore.shared.merge(read.history)
                step = .done(source, bookmarks: bookmarks, history: history)
            }
        }
    }
}

/// A browser to import from: its own icon, its name, what comes over.
private struct SourceRow: View {
    let name: String
    let detail: String
    let icon: NSImage?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Icon(.doc, size: 20).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Icon(.chevronRight, size: 14)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textQuaternary)
                    .offset(x: hovering ? 2 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}
