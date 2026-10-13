//
//  CollectionViews.swift
//  Max Q
//
//  Collections on screen: the sidebar section (drop a link or a quote on a collection to add it),
//  the "Add to Collection" menu that rows and pages offer, and the collection's own page, a board
//  of what was saved with Grok's brief above it.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The menu

/// "Add to Collection": the collections, most recent first, and a new one named for the context.
struct AddToCollectionMenu: View {
    let item: () -> CollectionItem
    /// What a new collection is called (the search, the page's title).
    let suggestedName: String
    @State private var store = CollectionStore.shared

    var body: some View {
        Menu("Add to Collection") {
            ForEach(store.collections.prefix(12)) { collection in
                Button(collection.name) { store.add(item(), to: collection.id) }
            }
            if !store.collections.isEmpty { Divider() }
            Button(String(localized: "New Collection “\(suggestedName)”")) {
                store.addToNew(item(), named: suggestedName)
            }
        }
    }
}

// MARK: - Sidebar

/// The sidebar's Collections section. A link or text dropped on a collection goes into it.
struct CollectionsSection: View {
    @Bindable var browser: BrowserModel
    @State private var store = CollectionStore.shared
    @AppStorage("sidebarCollectionsOpen") private var open = true

    var body: some View {
        if !browser.isPrivate, !store.collections.isEmpty || !ResearchStore.shared.reports.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Button { withAnimation(Motion.smooth) { open.toggle() } } label: {
                    HStack(spacing: 6) {
                        SectionLabel("Saved")
                        MorphChevron(open: open, size: 10)
                            .foregroundStyle(Theme.textQuaternary)
                        Spacer(minLength: 0)
                        Button { newCollection() } label: { Icon(.plus, size: 13) }
                            .iconButton(size: 22)
                            .tip("New collection")
                            .accessibilityLabel("New Collection")
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    ForEach(store.collections) { collection in
                        CollectionRow(collection: collection, selected: browser.selectedTab?.nativePage == .collection(collection.id)) {
                            browser.openNative(.collection(collection.id))
                        }
                    }
                    ForEach(ResearchStore.shared.reports.prefix(5)) { report in
                        ResearchRow(report: report, selected: browser.selectedTab?.nativePage == .research(report.id)) {
                            browser.openNative(.research(report.id))
                        }
                    }
                }
            }
            .padding(.bottom, 12)
            .animation(Motion.smooth, value: store.collections.map(\.id))
        }
    }

    private func newCollection() {
        let id = store.create(String(localized: "New collection"))
        browser.openNative(.collection(id), inNewTab: true)
    }
}

private struct CollectionRow: View {
    let collection: SavedCollection
    let selected: Bool
    let open: () -> Void
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Icon(.stack, size: 17)
                    .foregroundStyle(hovering || selected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 20, height: 20)
                Text(collection.name)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(collection.items.count)")
                    .font(.mono(11, weight: .regular))
                    .foregroundStyle(Theme.textQuaternary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(targeted ? Theme.pressed : (selected ? Theme.selected : (hovering ? Theme.hover : .clear))))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(targeted ? Theme.focus : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.hover, value: targeted)
        .dropDestination(for: String.self) { values, _ in
            CollectionDrop.add(values, to: collection.id)
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("Open") { open() }
            Button("Delete Collection") { CollectionStore.shared.delete(collection.id) }
        }
    }
}

private struct ResearchRow: View {
    let report: ResearchReport
    let selected: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Group {
                    if report.isRunning { TypingDots(size: 3.5) } else { Icon(.lines, size: 17) }
                }
                .foregroundStyle(hovering || selected ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 20, height: 20)
                Text(report.title.isEmpty ? report.question : report.title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(selected ? Theme.selected : (hovering ? Theme.hover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .help(String(localized: "Research · \(report.created.formatted(date: .abbreviated, time: .omitted))"))
        .contextMenu {
            Button("Open") { open() }
            Button("Delete Research") { ResearchStore.shared.delete(report.id) }
        }
    }
}

/// What can be dropped on a collection: links (a page) and text (a quote).
@MainActor
enum CollectionDrop {
    static func add(_ values: [String], to id: UUID) -> Bool {
        var added = false
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http", !trimmed.contains(" ") {
                CollectionStore.shared.add(CollectionItem(kind: .page, title: url.host ?? trimmed, url: url, source: url.host), to: id)
            } else {
                CollectionStore.shared.add(CollectionItem(kind: .quote, title: String(trimmed.prefix(80)), text: trimmed), to: id)
            }
            added = true
        }
        return added
    }
}

// MARK: - The page

struct CollectionPage: View {
    @Bindable var browser: BrowserModel
    let id: UUID
    @State private var store = CollectionStore.shared
    @State private var name = ""
    @State private var targeted = false
    @FocusState private var naming: Bool

    private var collection: SavedCollection? { store.collection(id) }

    var body: some View {
        Group {
            if let collection {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        header(collection)
                            .padding(.bottom, 26)
                        if let brief = collection.brief, !brief.isEmpty || store.writing == collection.id {
                            BriefBlock(collection: collection, writing: store.writing == collection.id) { open($0) }
                                .padding(.bottom, 30)
                        }
                        if collection.items.isEmpty {
                            empty
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 16, alignment: .top)],
                                      alignment: .leading, spacing: 16) {
                                ForEach(collection.items) { item in
                                    ItemCard(item: item) {
                                        if let url = item.link { open(url) }
                                    } remove: {
                                        withAnimation(Motion.smooth) { store.remove(item.id, from: collection.id) }
                                    }
                                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                                }
                            }
                            .animation(Motion.smooth, value: collection.items.map(\.id))
                        }
                    }
                    .frame(maxWidth: 1080, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    .padding(.bottom, 80)
                    .frame(maxWidth: .infinity)
                }
                .scrollEdgeFade()
                .overlay {
                    if targeted {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.focus, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
                .dropDestination(for: String.self) { values, _ in
                    CollectionDrop.add(values, to: id)
                } isTargeted: { targeted = $0 }
                .onAppear { name = collection.name }
            } else {
                Text("This collection isn't on this Mac anymore.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface)
    }

    private func header(_ collection: SavedCollection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Icon(.stack, size: 13)
                Text("Collection")
                Text("·").foregroundStyle(Theme.textQuaternary)
                Text(String(localized: "\(collection.items.count) items"))
                Text("·").foregroundStyle(Theme.textQuaternary)
                Text(String(localized: "Updated \(ResultDate.label(collection.updated, isDay: false))"))
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.serif(38, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .focused($naming)
                .onSubmit { store.rename(collection.id, to: name) }
                .onChange(of: naming) { _, focused in if !focused { store.rename(collection.id, to: name) } }
            HStack(spacing: 6) {
                if store.writing == collection.id {
                    Button("Stop") { store.stopBrief() }
                        .pill(.secondary, size: .small)
                } else {
                    Button {
                        guard GrokAccount.shared.hasKey else {
                            browser.showToast(String(localized: "A brief needs your SpaceXAI API key."))
                            browser.requestGrokKey()
                            return
                        }
                        store.writeBrief(collection.id)
                    } label: {
                        HStack(spacing: 6) {
                            Icon(.compose, size: 15)
                            Text(collection.brief == nil ? "Write a brief" : "Write it again")
                        }
                    }
                    .pill(.primary, size: .small)
                    .disabled(collection.items.isEmpty)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.markdown(collection.id), forType: .string)
                    browser.showToast(String(localized: "Collection copied as Markdown."))
                } label: {
                    HStack(spacing: 6) {
                        Icon(.copy, size: 15)
                        Text("Copy as Markdown")
                    }
                }
                .pill(.ghost, size: .small)
                Spacer(minLength: 8)
                Button { delete(collection) } label: { Icon(.trash, size: 15) }
                    .iconButton(size: 30)
                    .tip("Delete the collection")
                    .accessibilityLabel("Delete the Collection")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Icon(.stack, size: 26)
                .foregroundStyle(Theme.textQuaternary)
            Text("Nothing here yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Right-click a result, a post, a story or a picture and choose Add to Collection, or drag a link or selected text here.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func open(_ url: URL) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        browser.openInNewTab(url, select: !flags.contains(.command))
    }

    private func delete(_ collection: SavedCollection) {
        guard let window = browser.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete “\(collection.name)”?")
        alert.informativeText = String(localized: "Its \(collection.items.count) items and its brief are removed from this Mac.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            store.delete(collection.id)
            browser.closeCurrentTab()
        }
    }
}

/// Grok's brief, above the items.
private struct BriefBlock: View {
    let collection: SavedCollection
    let writing: Bool
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Icon(.compose, size: 14)
                Text("Brief by Grok")
                    .font(.system(size: 13, weight: .semibold))
                if writing { LiveDot(color: Theme.textSecondary, size: 5) }
                Spacer(minLength: 0)
                if let cost = collection.briefCost, !writing {
                    Text(GrokAccount.formatCost(cost))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .foregroundStyle(Theme.textSecondary)
            if let brief = collection.brief, !brief.isEmpty {
                MarkdownText(text: brief, fontSize: 15, streaming: writing, lineSpacing: 5, blockSpacing: 10, onOpenLink: open)
                    .foregroundStyle(Theme.textReading)
            } else {
                ShimmerText(text: String(localized: "Reading the collection"), font: .system(size: 14, weight: .medium))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// One saved item, set for its kind: a quote in the serif, a picture large, a post with its author.
private struct ItemCard: View {
    let item: CollectionItem
    let open: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                if let picture = item.picture {
                    AspectBox(aspect: item.kind == .image ? 4 / 3 : 16 / 9, maxHeight: 260) {
                        FillImage(candidates: [picture])
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                HStack(spacing: 6) {
                    Icon(icon, size: 12)
                    if let source = item.source { Text(source).lineLimit(1) }
                    Text("·").foregroundStyle(Theme.textQuaternary)
                    Text(ResultDate.label(item.added, isDay: false)).lineLimit(1)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                if item.kind == .quote, let text = item.text {
                    Text("“\(text)”")
                        .font(.serif(16, weight: .regular))
                        .foregroundStyle(Theme.textReading)
                        .lineLimit(8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(hovering ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let text = item.text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(hovering ? Theme.border : Theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: remove) { Icon(.close, size: 12) }
                    .iconButton(size: 24)
                    .background(Circle().fill(Theme.elevated))
                    .padding(8)
                    .tip("Remove from the collection")
                    .accessibilityLabel("Remove from the Collection")
                    .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }

    private var icon: MQIcon {
        switch item.kind {
        case .page, .result: .globe
        case .post: .bubble
        case .quote: .quote
        case .image: .image
        case .news: .doc
        case .video: .play
        case .note: .compose
        }
    }
}

extension EnvironmentValues {
    /// What a new collection made from this page is called (the results page's search).
    @Entry var collectionName: String = ""
}
