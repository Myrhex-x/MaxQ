//
//  ImagesPage.swift
//  Max Q
//
//  The Images tab, behind More: pictures from across the web in justified rows, each at its own
//  shape, the rows filling the page's width exactly (the way a photo wall is set). A picture opens
//  in the page's photo viewer, growing out of its tile, with the page it's on and a way there.
//  Filters sit above the wall: size and layout, applied to the pictures already found.
//
//  The wall shows Brave's own copies, so looking through pictures doesn't contact every site
//  they're on; a picture opened full size loads from its site.
//

import SwiftUI

struct ImagesPage: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch
    let wide: Bool
    @State private var width: CGFloat = 0

    private var feed: VerticalFeed<ImageItem> { search.images }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ImageFilterBar(search: search)
                    .padding(.bottom, 16)
                switch feed.phase {
                case .idle, .loading:
                    ImageWallSkeleton(width: width)
                        .transition(.opacity)
                case .failed(let message):
                    VerticalFailure(message: message, retry: { feed.reload() },
                                    site: DuckDuckGoPages.images(search.query), browser: browser)
                case .needsKey:
                    SearchKeyPrompt(browser: browser, site: DuckDuckGoPages.images(search.query))
                case .ready:
                    if search.shownImages.isEmpty {
                        VerticalEmpty(text: String(localized: "No pictures for “\(search.query)”."),
                                      reset: search.imageFilters.isDefault ? nil : { search.setImageFilters(ImageFilters()) })
                    } else {
                        ImageWall(items: search.shownImages, width: width, animated: Date().timeIntervalSince(feed.arrived) < 1.5) {
                            if feed.canLoadMore { feed.loadMore() }
                        }
                        if feed.loadingMore {
                            HStack { Spacer(); TypingDots(); Spacer() }
                                .padding(.top, 22)
                        }
                        SourceFootnote(text: "This search on DuckDuckGo", link: "Open there") {
                            if let url = DuckDuckGoPages.images(search.query) { openFromResults(url, browser: browser) }
                        }
                        .padding(.top, 28)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .padding(.horizontal, wide ? 40 : 28)
            .padding(.top, 22)
            .padding(.bottom, 56)
            .frame(maxWidth: 1480)
            .frame(maxWidth: .infinity)
            .animation(Motion.standard(0.25), value: feed.phase)
        }
        .pageScroll()
    }
}

// MARK: - The wall

/// Justified rows: pictures keep their shapes, each row is scaled to fill the width exactly, and
/// the last row keeps the target height rather than stretching a few pictures across the page.
struct ImageWall: View {
    let items: [ImageItem]
    let width: CGFloat
    let animated: Bool
    let reachedEnd: () -> Void

    static let spacing: CGFloat = 8

    var body: some View {
        let rows = Self.rows(items, width: width, target: width > 900 ? 200 : 160, spacing: Self.spacing)
        let urls = items.map(\.image)
        let thumbnails = items.map(\.thumbnail)
        let details = items.map { LightboxDetail(title: $0.title, site: $0.site, page: $0.page, width: $0.width, height: $0.height) }
        LazyVStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: Self.spacing) {
                    ForEach(row, id: \.index) { cell in
                        ImageTile(item: items[cell.index])
                            .frame(width: cell.width, height: cell.height)
                            .opensInLightbox(urls, index: cell.index, aspects: items.map { Optional($0.aspect) },
                                             previews: thumbnails, details: details)
                            .riseIn(order: rowIndex, animated: animated)
                    }
                }
                .onAppear {
                    // Two rows from the end: the next pictures start loading.
                    if rowIndex >= rows.count - 2 { reachedEnd() }
                }
            }
        }
    }

    struct Cell { let index: Int; let width: CGFloat; let height: CGFloat }

    /// Splits the pictures into rows that fill `width` at about `target` points tall.
    static func rows(_ items: [ImageItem], width: CGFloat, target: CGFloat, spacing: CGFloat) -> [[Cell]] {
        guard width > 0 else { return [] }
        var rows: [[Cell]] = []
        var pending: [(index: Int, aspect: CGFloat)] = []
        var aspectSum: CGFloat = 0
        for (index, item) in items.enumerated() {
            // Panoramas and slivers are kept within reason, so no tile is a thread.
            let aspect = min(max(CGFloat(item.aspect), 0.5), 2.6)
            pending.append((index, aspect))
            aspectSum += aspect
            let gaps = spacing * CGFloat(pending.count - 1)
            if aspectSum * target + gaps >= width {
                let height = (width - gaps) / aspectSum
                rows.append(pending.map { Cell(index: $0.index, width: ($0.aspect * height).rounded(.down), height: height.rounded()) })
                pending = []
                aspectSum = 0
            }
        }
        if !pending.isEmpty {
            rows.append(pending.map { Cell(index: $0.index, width: ($0.aspect * target).rounded(.down), height: target) })
        }
        return rows
    }
}

private struct ImageTile: View {
    let item: ImageItem
    @State private var hovering = false
    @State private var failed = false
    @Environment(\.collectionName) private var collectionName

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Theme.hover)
            if !failed {
                FillImage(candidates: [item.thumbnail]) { failed = true }
                    .scaleEffect(hovering ? 1.03 : 1)
            } else {
                Icon(.image, size: 22)
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if hovering {
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                    .transition(.opacity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        ResultIcon(host: item.page.host ?? "", size: 11)
                        Text(item.site)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11.5))
                    .opacity(0.85)
                }
                .foregroundStyle(Color.white)
                .padding(10)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.3), value: hovering)
        .help(item.title)
        .accessibilityLabel(Text(item.title.isEmpty ? item.site : item.title))
        .contextMenu {
            Button("Copy Picture Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.image.absoluteString, forType: .string)
            }
            Button("Copy Page Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.page.absoluteString, forType: .string)
            }
            Divider()
            AddToCollectionMenu(item: {
                CollectionItem(kind: .image, title: item.title.isEmpty ? item.site : item.title, url: item.page,
                               image: item.image, source: item.site)
            }, suggestedName: collectionName.isEmpty ? item.site : collectionName)
        }
        .draggable(item.page)
    }
}

private struct ImageWallSkeleton: View {
    let width: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.hover)
                            .frame(maxWidth: .infinity)
                            .frame(height: width > 900 ? 200 : 160)
                            .opacity(1 - Double(row) * 0.25)
                            .pulsing(delay: Double(row * 5 + column) * 0.05)
                    }
                }
            }
        }
    }
}

// MARK: - Filters

/// The filters above the wall, each a pill that opens its choices; a filter in use stands out.
private struct ImageFilterBar: View {
    let search: GrokSearch

    private var filters: ImageFilters { search.imageFilters }

    var body: some View {
        HStack(spacing: 6) {
            ChoiceMenu(options: ImageFilters.Size.allCases, selected: filters.size, label: \.title) {
                var next = filters; next.size = $0; search.setImageFilters(next)
            }
            ChoiceMenu(options: ImageFilters.Layout.allCases, selected: filters.layout, label: \.title) {
                var next = filters; next.layout = $0; search.setImageFilters(next)
            }
            if !filters.isDefault {
                Button("Clear") { withAnimation(Motion.smooth) { search.setImageFilters(ImageFilters()) } }
                    .pill(.ghost, size: .mini)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Spacer(minLength: 0)
        }
        .animation(Motion.smooth, value: filters)
    }
}

/// A filter as a pill: its current choice, and the choices in a menu. The first option is "any",
/// and the pill stands out once something else is picked.
struct ChoiceMenu<Value: Hashable & Identifiable>: View {
    var icon: MQIcon? = nil
    let options: [Value]
    let selected: Value
    let label: (Value) -> String
    let choose: (Value) -> Void

    init(icon: MQIcon? = nil, options: [Value], selected: Value, label: @escaping (Value) -> String,
         choose: @escaping (Value) -> Void) {
        self.icon = icon
        self.options = options
        self.selected = selected
        self.label = label
        self.choose = choose
    }

    private var isDefault: Bool { selected == options.first }

    var body: some View {
        MenuButton(placement: .below(.leading)) { isOpen in
            HStack(spacing: 5) {
                if let icon { Icon(icon, size: 15) }
                Text(label(selected))
                    .contentTransition(.interpolate)
                    .lineLimit(1)
                MorphChevron(open: isOpen, size: 12)
            }
            .foregroundStyle(isDefault ? Theme.textSecondary : Theme.textPrimary)
        } content: {
            MenuCard(width: 200) {
                ForEach(options) { option in
                    MenuRow(verbatim: label(option), checked: option == selected) {
                        withAnimation(Motion.smooth) { choose(option) }
                    }
                }
            }
        }
        .pill(isDefault ? .ghost : .secondary, size: .mini)
        .animation(Motion.smooth, value: selected)
    }
}
