//
//  WebReaderView.swift
//  Max Q
//
//  Reader, over the page: the article set like a Grokipedia article (the site, the byline and
//  when, the title in the serif, the picture, the text at the reading size), the contents beside it
//  on wide windows, and the reader's own tools: Listen, Translate (on this Mac), a larger or
//  smaller size, and questions to Grok about the article. "Original page" (or ⇧⌘R) takes it away.
//

import AppKit
import SwiftUI
import Translation

/// Where Reader is in a tab.
enum ReaderPhase: Equatable {
    case loading
    case ready(ReaderDocument)
    case failed(String)
}

struct WebReaderView: View {
    @Bindable var browser: BrowserModel
    @Bindable var tab: BrowserTab
    let phase: ReaderPhase

    var body: some View {
        ZStack {
            Theme.surface
            switch phase {
            case .loading:
                VStack(spacing: 14) {
                    ShimmerText(text: String(localized: "Making the page readable"), font: .system(size: 15, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            case .failed(let message):
                VStack(spacing: 14) {
                    Text(message)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("Original page") { browser.toggleReader() }
                        .pill(.secondary, size: .regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let document):
                ReaderArticle(browser: browser, document: document)
                    .id(document.url)
                    .transition(.opacity)
            }
        }
        .animation(Motion.standard(0.25), value: phase)
    }
}

private struct ReaderArticle: View {
    @Bindable var browser: BrowserModel
    let document: ReaderDocument
    @State private var tracker = ReaderTracker()
    @State private var lightbox = Lightbox()
    @AppStorage("readerTextSize") private var textSize = 17.0
    @State private var translation: TranslationSession.Configuration?
    @State private var translated: [String: String] = [:]
    @State private var translating = false
    private var speaker: ArticleSpeaker { ArticleSpeaker.shared }

    private var article: GrokipediaArticle {
        guard !translated.isEmpty else { return document.article }
        var copy = document.article
        copy.blocks = copy.blocks.map { block in
            switch block {
            case .heading(let heading):
                guard let text = translated[block.id] else { return block }
                return .heading(GrokipediaHeading(id: heading.id, level: heading.level, text: text))
            case .paragraph(let id, _):
                guard let text = translated[block.id] else { return block }
                return .paragraph(id: id, runs: [GrokipediaRun(text: text)])
            case .quote(let id, _):
                guard let text = translated[block.id] else { return block }
                return .quote(id: id, runs: [GrokipediaRun(text: text)])
            default:
                return block
            }
        }
        return copy
    }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 1_060
            ZStack(alignment: .topLeading) {
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 56) {
                            VStack(alignment: .leading, spacing: 0) {
                                opening
                                    .padding(.bottom, 28)
                                ArticleBody(browser: browser, article: article, tracker: tracker, articleURL: document.url)
                                    .environment(\.readerTextSize, textSize)
                                Text(String(localized: "From \(document.site). Reader shows the article's text; the page itself is a click away."))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textQuaternary)
                                    .padding(.top, 30)
                                    .padding(.bottom, 90)
                            }
                            .frame(maxWidth: 680, alignment: .leading)
                            if wide, !document.article.outline.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    Color.clear.frame(height: 0)
                                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(readerSpace)).minY } action: {
                                            tracker.railTop = $0
                                        }
                                    ContentsRail(outline: article.outline, hasSources: false, tracker: tracker) { id in
                                        withAnimation(Motion.page) { reader.scrollTo("h-\(id)", anchor: .top) }
                                    }
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tracker.railHeight = $0 }
                                    .modifier(RailOffset(tracker: tracker))
                                }
                                .frame(width: 250)
                                .padding(.top, 120)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                        .coordinateSpace(.named(readerSpace))
                    }
                    .scrollEdgeFade()
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, top in
                        tracker.visibleTop = top
                    }
                    .onScrollGeometryChange(for: CGSize.self) { CGSize(width: $0.containerSize.height, height: $0.contentSize.height) } action: { _, size in
                        tracker.viewportHeight = size.width
                        tracker.contentHeight = size.height
                    }
                    .overlay(alignment: .bottom) {
                        ArticleAskBar(context: ArticleContext.make(title: document.title, url: document.url, article: document.article),
                                      browser: browser) { id in
                            withAnimation(Motion.page) { reader.scrollTo("h-\(id)", anchor: .top) }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                LightboxOverlay(lightbox: lightbox, size: proxy.size) { url in browser.openInNewTab(url) }
            }
            .coordinateSpace(.named(resultsPageSpace))
            .environment(\.lightbox, lightbox)
        }
        .environment(\.readerLink) { url, _ in
            LinkPreviewPresenter.shared.hide()
            openFromResults(url, browser: browser)
        }
        .environment(\.readerLinkHover) { url, rect in
            guard AppSettings.shared.linkPreviews else { return }
            LinkPreviewPresenter.shared.hover(url, at: rect, in: browser.window) { target in
                LinkPreviewPresenter.shared.hide()
                openFromResults(target, browser: browser)
            }
        }
        .translationTask(translation) { session in
            await translate(with: session)
        }
        .onDisappear {
            LinkPreviewPresenter.shared.hide()
            if speaker.isReading(document.url) { speaker.stop() }
        }
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                ResultIcon(host: document.url.host ?? "", size: 14)
                Text(document.site)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let byline = document.byline {
                    Text("·").foregroundStyle(Theme.textQuaternary)
                    Text(byline).lineLimit(1)
                }
                if let date = document.published {
                    Text("·").foregroundStyle(Theme.textQuaternary)
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                }
                Text("·").foregroundStyle(Theme.textQuaternary)
                Text(String(localized: "\(document.article.readingMinutes) min read"))
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.textTertiary)
            Text(document.title)
                .font(.serif(40, weight: .medium))
                .tracking(-40 * 0.02)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            tools
            if let image = document.leadImage, !document.article.blocks.contains(where: { if case .figure(_, let url, _, _) = $0 { url == image } else { false } }) {
                AspectBox(aspect: 16 / 9, maxHeight: 420) {
                    FillImage(candidates: [image])
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 6)
            }
        }
    }

    /// Listen, Translate, the text size and the way back to the page.
    private var tools: some View {
        HStack(spacing: 6) {
            Button {
                speaker.toggle(url: document.url, title: document.title, article: document.article, language: document.language)
            } label: {
                HStack(spacing: 6) {
                    Icon(.speaker, size: 15)
                    Text(speaker.isReading(document.url) ? (speaker.paused ? "Resume" : "Pause") : "Listen")
                }
            }
            .pill(.secondary, size: .small)
            if showsTranslate {
                Button {
                    if translated.isEmpty {
                        translating = true
                        let source = document.language.map { Locale.Language(identifier: $0) }
                        translation = TranslationSession.Configuration(source: source, target: Locale.current.language)
                    } else {
                        withAnimation(Motion.smooth) { translated = [:] }
                        translation = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Icon(.translate, size: 15)
                        Text(translated.isEmpty ? (translating ? "Translating…" : "Translate") : "Show original")
                    }
                }
                .pill(.secondary, size: .small)
                .disabled(translating)
            }
            Spacer(minLength: 8)
            Button { textSize = max(14, textSize - 1) } label: { Text("A").font(.system(size: 12, weight: .semibold)) }
                .iconButton(size: 28)
                .tip("Smaller text")
                .accessibilityLabel("Smaller Text")
            Button { textSize = min(24, textSize + 1) } label: { Text("A").font(.system(size: 17, weight: .semibold)) }
                .iconButton(size: 28)
                .tip("Larger text")
                .accessibilityLabel("Larger Text")
            Button("Original page") { browser.toggleReader() }
                .pill(.ghost, size: .small)
                .tip("Back to the page", shortcut: "⇧⌘R")
        }
    }

    /// The page is in another language than the Mac's.
    private var showsTranslate: Bool {
        guard let language = document.language else { return false }
        return language != (Locale.current.language.languageCode?.identifier ?? "en")
    }

    /// Translates the headings and paragraphs on this Mac, in one go.
    private func translate(with session: TranslationSession) async {
        var requests: [TranslationSession.Request] = []
        for block in document.article.blocks {
            switch block {
            case .heading(let heading):
                requests.append(TranslationSession.Request(sourceText: heading.text, clientIdentifier: block.id))
            case .paragraph(_, let runs), .quote(_, let runs):
                requests.append(TranslationSession.Request(sourceText: runs.map(\.text).joined(), clientIdentifier: block.id))
            default:
                break
            }
        }
        guard let responses = try? await session.translations(from: requests) else {
            translating = false
            browser.showToast(String(localized: "The translation didn't finish."))
            return
        }
        var result: [String: String] = [:]
        for response in responses {
            if let id = response.clientIdentifier { result[id] = response.targetText }
        }
        withAnimation(Motion.smooth) { translated = result }
        translating = false
    }
}

extension EnvironmentValues {
    /// Reader's text size (Grokipedia's reading size when unset).
    @Entry var readerTextSize: CGFloat = 15.5
}
