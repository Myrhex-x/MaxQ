//
//  ImaginePage.swift
//  Max Q
//
//  The Imagine page: grok.com's composer for a prompt, the shape, how many pictures and which
//  model, with the price before anything is made; then everything made so far, newest first, each
//  prompt with its pictures. A picture opens in the photo viewer; its menu copies it, saves it, or
//  shows it in the Finder.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImaginePage: View {
    @Bindable var browser: BrowserModel
    @State private var store = ImagineStore.shared
    @State private var prompt = ""
    @State private var aspect: ImagineAspect = .square
    @State private var count = 2
    @State private var quality = false
    @State private var lightbox = Lightbox()
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        title
                            .padding(.bottom, 20)
                        composer
                            .padding(.bottom, 34)
                        if !GrokAccount.shared.hasKey {
                            keyless
                        }
                        LazyVStack(alignment: .leading, spacing: 34) {
                            ForEach(store.generations) { generation in
                                GenerationView(generation: generation) { prompt = generation.prompt; aspect = generation.aspect }
                                    .transition(.rise)
                            }
                        }
                        .animation(Motion.smooth, value: store.generations.map(\.id))
                    }
                    .frame(maxWidth: 980, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    .padding(.bottom, 80)
                    .frame(maxWidth: .infinity)
                }
                .scrollEdgeFade()
                LightboxOverlay(lightbox: lightbox, size: proxy.size)
            }
            .coordinateSpace(.named(resultsPageSpace))
            .environment(\.lightbox, lightbox)
        }
        .background(Theme.surface)
        .task {
            if let draft = store.draft {
                prompt = draft
                store.draft = nil
            }
            focused = true
            await store.loadModels()
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Imagine")
                .font(.heading(30))
                .tracking(-0.6)
                .foregroundStyle(Theme.textPrimary)
            Text("Pictures made by Grok's image models from your words, on your key. Each one is saved on this Mac.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// grok.com's composer: the prompt, then the choices and the price beside the button.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Describe a picture", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(2...6)
                .focused($focused)
                .onSubmit(generate)
            HStack(spacing: 6) {
                ChoiceMenu(options: ImagineAspect.allCases, selected: aspect, label: \.title) { aspect = $0 }
                ChoiceMenu(options: [1, 2, 4].map(Count.init), selected: Count(value: count), label: \.title) { count = $0.value }
                if store.qualityModel != nil {
                    ChoiceMenu(options: [false, true].map(Quality.init), selected: Quality(on: quality), label: \.title) { quality = $0.on }
                }
                Spacer(minLength: 8)
                Text(priceLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
                Button(action: generate) {
                    HStack(spacing: 6) {
                        Icon(.image, size: 15)
                        Text("Imagine")
                    }
                }
                .pill(.primary, size: .small)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !GrokAccount.shared.hasKey)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous).fill(Theme.input))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous).strokeBorder(Theme.composerBorder, lineWidth: 1))
        .elevation(.raised)
    }

    private var keyless: some View {
        HStack(spacing: 12) {
            Text("Imagine runs on your SpaceXAI API key. Without one, grok.com's Imagine works in your Grok account.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Open grok.com") {
                if let url = URL(string: "https://grok.com/imagine") { browser.openInNewTab(url) }
            }
            .pill(.secondary, size: .small)
        }
        .padding(.bottom, 30)
    }

    private var priceLine: String {
        let model = quality ? (store.qualityModel ?? store.standardModel) : store.standardModel
        let total = store.price(of: model) * Double(count)
        return String(localized: "\(count) pictures · \(GrokAccount.friendlyCost(total, approximate: false))")
    }

    private func generate() {
        guard GrokAccount.shared.hasKey else {
            browser.requestGrokKey()
            return
        }
        guard !GrokAccount.shared.limitReached else {
            browser.showToast(String(localized: "This month's Grok limit is reached."))
            return
        }
        store.generate(prompt, count: count, aspect: aspect, quality: quality)
    }

    private struct Count: Hashable, Identifiable {
        let value: Int
        var id: Int { value }
        var title: String { value == 1 ? String(localized: "1 picture") : String(localized: "\(value) pictures") }
    }

    private struct Quality: Hashable, Identifiable {
        let on: Bool
        var id: Bool { on }
        var title: String { on ? String(localized: "Higher quality") : String(localized: "Standard") }
    }
}

/// One prompt and what it made.
private struct GenerationView: View {
    let generation: ImagineGeneration
    let reuse: () -> Void
    private var store: ImagineStore { ImagineStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(generation.prompt)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                Spacer(minLength: 8)
                MenuButton(placement: .below(.trailing)) { _ in
                    Icon(.more, size: 16)
                } content: {
                    MenuCard(width: 210) {
                        MenuRow(icon: .compose, title: "Use this prompt", action: reuse)
                        MenuRow(icon: .trash, title: "Delete", destructive: true) {
                            withAnimation(Motion.smooth) { store.delete(generation.id) }
                        }
                    }
                }
                .iconButton(size: 28)
            }
            Text(meta)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            if generation.running {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<2, id: \.self) { _ in
                        AspectBox(aspect: generation.aspect.ratio, maxHeight: 420) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.hover)
                                .overlay(ShimmerText(text: String(localized: "Imagining"), font: .system(size: 13, weight: .medium)))
                        }
                        .pulsing()
                    }
                }
            } else if let failure = generation.failure {
                Text(failure)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                let urls = generation.files.map(store.url(of:))
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        PictureTile(url: url, aspect: generation.aspect.ratio)
                            .opensInLightbox(urls, index: index, captions: urls.map { _ in generation.prompt },
                                             aspects: urls.map { _ in generation.aspect.ratio })
                    }
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: generation.aspect.ratio >= 1.3 ? 300 : 200, maximum: 460), spacing: 10)]
    }

    private var meta: String {
        var parts = [generation.created.formatted(date: .abbreviated, time: .shortened)]
        if !generation.files.isEmpty { parts.append(generation.files.count == 1 ? String(localized: "1 picture") : String(localized: "\(generation.files.count) pictures")) }
        if let cost = generation.cost { parts.append(GrokAccount.formatCost(cost)) }
        return parts.joined(separator: " · ")
    }
}

private struct PictureTile: View {
    let url: URL
    let aspect: Double
    @State private var hovering = false

    var body: some View {
        AspectBox(aspect: aspect, maxHeight: 520) {
            RemoteImage(candidates: [url], contentMode: .fill)
                .scaleEffect(hovering ? 1.015 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.3), value: hovering)
        .contextMenu {
            Button("Copy Picture") {
                guard let image = NSImage(contentsOf: url) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
            Button("Save Picture As…") { save() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        .draggable(url)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(GrokCredit.created) \(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).\(url.pathExtension)"
        panel.begin { response in
            guard response == .OK, let target = panel.url else { return }
            try? FileManager.default.copyItem(at: url, to: target)
        }
    }
}
