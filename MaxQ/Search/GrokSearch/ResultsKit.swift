//
//  ResultsKit.swift
//  Max Q
//
//  The pieces Max Q's results pages share, so All, Grokipedia and Posts on X read as one page seen
//  three ways: module headers, rows that rise into place one after another, the veil a keyboard
//  pick glides with, the control that sits beside the tabs (All's time filter, Posts on X's Top
//  and Latest), and the photo viewer, where a picture grows out of the spot it was clicked in
//  (Benji Taylor's rule that a transition shows where things come from).
//

import AppKit
import SwiftUI

// MARK: - Module header

/// A module's title on a results page ("Posts on X", "Videos"), and a way to see more of it.
struct ModuleHeader: View {
    let title: LocalizedStringKey
    var detail: String? = nil
    /// The module is still filling in.
    var live = false
    var more: LocalizedStringKey? = nil
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(Theme.textPrimary)
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
            }
            if live {
                LiveDot(color: Theme.textSecondary, size: 5)
                    .transition(.opacity)
            }
            Spacer(minLength: 8)
            if let more {
                ArrowLink(title: more, action: action)
            }
        }
        .animation(Motion.smooth, value: live)
    }
}

// MARK: - Rows

/// Rows rise 8 points into place 60 ms apart as they arrive (Grokipedia's list entrance), and are
/// simply there when the page comes back.
private struct RiseIn: ViewModifier {
    let order: Int
    let animated: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard animated, !reduceMotion else { shown = true; return }
                withAnimation(Motion.spring(0.4).delay(Double(min(order, 9)) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func riseIn(order: Int, animated: Bool = true) -> some View {
        modifier(RiseIn(order: order, animated: animated))
    }

    /// The hairline under a row.
    func rowHairline() -> some View {
        overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

extension View {
    /// A row that scrolls sideways inside the reading column: it stays within the column, and its
    /// far edge fades so the next card shows there's more.
    func rowEdgeFade(_ width: CGFloat = 28) -> some View {
        mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
            }
        }
    }
}

/// The veil behind the row J and K are on, gliding from row to row.
struct PickVeil: View {
    let namespace: Namespace.ID

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.hover)
            .padding(.horizontal, -14)
            .padding(.vertical, 4)
            .matchedGeometryEffect(id: "picked", in: namespace)
    }
}

// MARK: - Beside the tabs

/// All's time filter: how recent the web results must be.
struct TimeFilterMenu: View {
    let search: GrokSearch

    var body: some View {
        MenuButton(placement: .below(.trailing)) { isOpen in
            HStack(spacing: 5) {
                Icon(.clock, size: 15)
                Text(search.time.title)
                    .contentTransition(.interpolate)
                MorphChevron(open: isOpen, size: 12)
            }
            .foregroundStyle(search.time == .any ? Theme.textSecondary : Theme.textPrimary)
        } content: {
            MenuCard(width: 190) {
                ForEach(SearchTime.allCases) { time in
                    MenuRow(verbatim: time.title, checked: search.time == time) {
                        withAnimation(Motion.smooth) { search.setTime(time) }
                    }
                }
            }
        }
        .pill(search.time == .any ? .ghost : .secondary, size: .mini)
        .tip("Show results from a period")
        .accessibilityLabel(Text("Time: \(search.time.title)"))
        .animation(Motion.smooth, value: search.time)
    }
}

// MARK: - Photo viewer

/// A picture opened from a results page.
struct LightboxItem: Equatable {
    var images: [URL]
    var index: Int
    var captions: [String] = []
    var referer: String? = nil
    /// Where the picture was on the page, to grow out of and go back to.
    var source: CGRect
    /// Width over height of each picture, when known, so it opens at its own shape.
    var aspects: [Double?] = []
    /// Small copies to show at once while the full pictures load (the Images tab's).
    var previews: [URL] = []
    /// Where each picture comes from, for the bar under it (the Images tab's).
    var details: [LightboxDetail] = []
}

/// A picture found on the web: its title, the page it's on, and its size.
struct LightboxDetail: Equatable {
    let title: String
    let site: String
    let page: URL
    var width: Int = 0
    var height: Int = 0
}

@MainActor
@Observable
final class Lightbox {
    private(set) var item: LightboxItem?
    private(set) var open = false

    func show(_ item: LightboxItem) {
        self.item = item
        open = false
        DispatchQueue.main.async {
            withAnimation(Motion.spring(0.45)) { self.open = true }
        }
    }

    func close() {
        withAnimation(Motion.spring(0.32)) { open = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
            guard let self, !self.open else { return }
            self.item = nil
        }
    }

    func step(_ delta: Int) {
        guard var item, !item.images.isEmpty else { return }
        item.index = (item.index + delta + item.images.count) % item.images.count
        withAnimation(Motion.smooth) { self.item = item }
    }
}

extension EnvironmentValues {
    /// The page's photo viewer, for pictures to open in.
    @Entry var lightbox: Lightbox? = nil
}

/// The page's coordinate space, which the photo viewer measures pictures in.
let resultsPageSpace = "resultsPage"

/// Makes a picture open in the page's photo viewer, growing from where it is.
private struct LightboxSource: ViewModifier {
    let images: [URL]
    let index: Int
    var captions: [String] = []
    var aspects: [Double?] = []
    var referer: String?
    var previews: [URL] = []
    var details: [LightboxDetail] = []
    @Environment(\.lightbox) private var lightbox
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(resultsPageSpace)) } action: { frame = $0 }
            .contentShape(Rectangle())
            .onTapGesture {
                lightbox?.show(LightboxItem(images: images, index: index, captions: captions, referer: referer,
                                            source: frame, aspects: aspects, previews: previews, details: details))
            }
            .accessibilityAddTraits(.isButton)
    }
}

extension View {
    func opensInLightbox(_ images: [URL], index: Int = 0, captions: [String] = [], aspects: [Double?] = [],
                         referer: String? = nil, previews: [URL] = [], details: [LightboxDetail] = []) -> some View {
        modifier(LightboxSource(images: images, index: index, captions: captions, aspects: aspects, referer: referer,
                                previews: previews, details: details))
    }

    /// A placeholder's slow pulse while the real thing loads.
    func pulsing(delay: Double = 0) -> some View {
        modifier(Pulse(delay: delay))
    }
}

private struct Pulse: ViewModifier {
    let delay: Double
    @State private var bright = false

    func body(content: Content) -> some View {
        content
            .opacity(bright ? 1 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(delay)) { bright = true }
            }
    }
}

/// The viewer: the page dims to near black and the picture moves from its spot to the middle,
/// at its own shape; the caption sits under it. Click anywhere, or Escape, to put it back.
struct LightboxOverlay: View {
    @Bindable var lightbox: Lightbox
    let size: CGSize
    /// Opens a picture's page (the Images tab's "Visit page").
    var open: (URL) -> Void = { _ in }
    @State private var loaded: [URL: CGSize] = [:]
    @State private var keyMonitor: Any?

    var body: some View {
        if let item = lightbox.item, item.images.indices.contains(item.index) {
            let url = item.images[item.index]
            let detail = item.details.indices.contains(item.index) ? item.details[item.index] : nil
            let caption = item.captions.indices.contains(item.index) ? item.captions[item.index] : ""
            let target = targetFrame(for: url, item: item, caption: detail == nil ? caption : "detail")
            let frame = lightbox.open ? target : item.source
            ZStack(alignment: .topLeading) {
                Color.black.opacity(lightbox.open ? 0.88 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { lightbox.close() }

                ZStack {
                    // The small copy at once, the full picture over it once it's in.
                    if item.previews.indices.contains(item.index) {
                        RemoteImage(candidates: [item.previews[item.index]], contentMode: lightbox.open ? .fit : .fill,
                                    showsPlaceholder: false)
                    }
                    RemoteImage(candidates: [url], referer: item.referer, contentMode: lightbox.open ? .fit : .fill,
                                showsPlaceholder: false)
                }
                    .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                    .clipShape(RoundedRectangle(cornerRadius: lightbox.open ? 6 : 12, style: .continuous))
                    .offset(x: frame.minX, y: frame.minY)
                    .onTapGesture { lightbox.close() }
                    .id(url)

                if let detail {
                    LightboxDetailBar(detail: detail, image: url) { open($0); lightbox.close() }
                        .frame(width: min(size.width - 80, 680))
                        .position(x: size.width / 2, y: target.maxY + 38)
                        .opacity(lightbox.open ? 1 : 0)
                }

                if !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(width: min(size.width - 80, 620))
                        .position(x: size.width / 2, y: target.maxY + 30)
                        .opacity(lightbox.open ? 1 : 0)
                        .allowsHitTesting(false)
                }

                if item.images.count > 1 {
                    HStack {
                        stepButton(.chevronLeft) { lightbox.step(-1) }
                        Spacer()
                        stepButton(.chevronRight) { lightbox.step(1) }
                    }
                    .padding(.horizontal, 18)
                    .frame(width: size.width, height: size.height)
                    .opacity(lightbox.open ? 1 : 0)
                }

                Button { lightbox.close() } label: { Icon(.close, size: 18) }
                    .buttonStyle(LightboxButtonStyle())
                    .padding(16)
                    .frame(width: size.width, alignment: .trailing)
                    .opacity(lightbox.open ? 1 : 0)
                    .accessibilityLabel("Close")
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onAppear(perform: watchKeys)
            .onDisappear(perform: stopWatchingKeys)
            .task(id: url) {
                if let image = await RemoteImageCache.shared.image(from: [url], referer: item.referer) {
                    loaded[url] = image.size
                }
            }
        }
    }

    private func stepButton(_ icon: MQIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) { Icon(icon, size: 20) }
            .buttonStyle(LightboxButtonStyle())
    }

    /// The picture's frame in the middle of the page, as large as fits with room for the caption.
    private func targetFrame(for url: URL, item: LightboxItem, caption: String) -> CGRect {
        let aspect: Double = {
            if let size = loaded[url], size.height > 0 { return size.width / size.height }
            if item.aspects.indices.contains(item.index), let known = item.aspects[item.index], known > 0 { return known }
            return item.source.height > 0 ? item.source.width / item.source.height : 1.5
        }()
        let room = CGSize(width: max(size.width - 140, 100), height: max(size.height - (caption.isEmpty ? 90 : 150), 100))
        var width = room.width
        var height = width / aspect
        if height > room.height {
            height = room.height
            width = height * aspect
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2 - (caption.isEmpty ? 0 : 22),
                      width: width, height: height)
    }

    private func watchKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard lightbox.item != nil else { return event }
            switch event.keyCode {
            case 53: lightbox.close(); return nil          // Escape
            case 123: lightbox.step(-1); return nil        // ←
            case 124: lightbox.step(1); return nil         // →
            default: return event
            }
        }
    }

    private func stopWatchingKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// Under a picture found on the web: its title, the site and size, and the way to its page.
private struct LightboxDetailBar: View {
    let detail: LightboxDetail
    let image: URL
    let open: (URL) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(detail.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ResultIcon(host: detail.page.host ?? "", size: 12)
                    Text(detail.site)
                    if detail.width > 0, detail.height > 0 {
                        Text("·")
                        Text(verbatim: "\(detail.width) × \(detail.height)")
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                open(image)
            } label: {
                Text("Open picture")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            Button {
                open(detail.page)
            } label: {
                HStack(spacing: 5) {
                    Text("Visit page")
                    Icon(.arrowUpRight, size: 12)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Round white-on-dark buttons over the photo viewer, as x.com's media viewer has.
private struct LightboxButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.24 : 0.14)))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

// MARK: - Footnotes

/// The quiet line at the foot of a page: where its content came from, and a way there.
struct SourceFootnote: View {
    let text: LocalizedStringKey
    var link: LocalizedStringKey? = nil
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
            if let link {
                Text("·").foregroundStyle(Theme.textQuaternary)
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(link)
                        Icon(.arrowUpRight, size: 11)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Media boxes

/// A box at a picture's shape: as wide as it's offered, unless that would make it taller than
/// `maxHeight`, in which case it narrows to keep the shape. Sizes itself outright, so a picture in a
/// scrolling page (where the height on offer is open) always gets the frame it should.
struct AspectBox: Layout {
    /// Width over height.
    let aspect: CGFloat
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ratio = max(aspect, 0.1)
        var width = proposal.width ?? maxHeight * ratio
        if width == .infinity { width = maxHeight * ratio }
        var height = width / ratio
        if height > maxHeight {
            height = maxHeight
            width = height * ratio
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

extension URL {
    /// The same page however it's written: without "www.", a trailing slash, the query or the
    /// fragment, so a citation and a result can be matched.
    var citationKey: String {
        var host = self.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = self.path
        while path.hasSuffix("/") { path.removeLast() }
        return host + path.lowercased()
    }
}
