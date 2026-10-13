//
//  GrokipediaCardView.swift
//  Max Q
//
//  The Grokipedia pad beside search results, set the way Grokipedia v0.3 sets its own pages: the
//  article as a book floating in the light (it drifts, leans and breathes like the featured book
//  on Grokipedia's front page), a large book-serif title, the opening in Grokipedia's reading grey,
//  "Read the article", the infobox with hairline rows, and the contents as Grokipedia's numbered
//  list, whose numbers step aside and whose chevrons slide in on hover. Always credited and linked.
//

import SwiftUI

struct GrokipediaCardView: View {
    let card: GrokipediaCard
    var onOpen: (URL) -> Void
    var onAskGrok: (String) -> Void
    var onClose: () -> Void
    /// Reads the whole article (the results page's Grokipedia tab); nil opens grokipedia.com.
    var onRead: (() -> Void)? = nil
    /// Opens the article at a section; nil opens it on grokipedia.com.
    var onSection: ((String) -> Void)? = nil

    @State private var expanded = false
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)

            GrokipediaBook(title: card.title, images: card.imageCandidates)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .reveal(revealed)

            titleBlock
                .padding(.top, 14)
                .reveal(revealed, delay: 0.06)

            summary
                .padding(.top, 16)
                .reveal(revealed, delay: 0.1)

            if !card.facts.isEmpty || card.article?.infobox != nil {
                GrokipediaInfoboxCard(card: card, infobox: card.article?.infobox, rows: 6)
                    .padding(.top, 24)
                    .reveal(revealed, delay: 0.14)
            }

            if !card.sections.isEmpty {
                contents
                    .padding(.top, 26)
                    .reveal(revealed, delay: 0.18)
            }

            actions
                .padding(.top, 24)
                .reveal(revealed, delay: 0.22)

            Text("From Grokipedia, linked back to the article. Some articles are licensed CC BY-SA 4.0.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textQuaternary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .onAppear { revealed = true }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 8) {
            Icon(.book, size: 16)
                .foregroundStyle(Theme.textTertiary)
            Text("Grokipedia")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if let kind = card.kind {
                Text(kind.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            }
            Spacer(minLength: 0)
            Button(action: onClose) { Icon(.close, size: 14) }
                .iconButton(size: 28)
                .tip("Hide Grokipedia for this search")
                .accessibilityLabel("Hide Grokipedia")
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.title)
                .font(.serif(32, weight: .medium))
                .tracking(-0.58)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            FactCheckLine(card: card, size: 12.5, detailed: false)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.summary)
                .font(.system(size: 14.5))
                .lineSpacing(5)
                .foregroundStyle(Theme.textReading)
                .lineLimit(expanded ? nil : 7)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 16) {
                ArrowLink(title: onRead == nil ? "Read the article" : "Read the whole article") {
                    if let onRead { onRead() } else { onOpen(card.articleURL) }
                }
                if card.summary.count > 420 {
                    Button {
                        withAnimation(Motion.smooth) { expanded.toggle() }
                    } label: {
                        MorphLabel(text: expanded ? String(localized: "Show less") : String(localized: "Show more"), font: .system(size: 13.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    /// Grokipedia's numbered list.
    private var contents: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Contents")
            VStack(spacing: 0) {
                ForEach(Array(card.sections.prefix(8).enumerated()), id: \.element.id) { index, section in
                    NumberedRow(number: index + 1, title: section.title) {
                        if let onSection {
                            onSection(section.id)
                        } else if var components = URLComponents(url: card.articleURL, resolvingAgainstBaseURL: false) {
                            components.fragment = section.id
                            onOpen(components.url ?? card.articleURL)
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { onAskGrok(card.title) } label: {
                HStack(spacing: 6) {
                    Icon(.bubble, size: 15)
                    Text("Ask Grok")
                }
            }
            .pill(.secondary, size: .small)

            if let site = card.officialSite, let host = card.officialSiteLabel {
                Button { onOpen(site) } label: {
                    HStack(spacing: 5) {
                        Text(host).lineLimit(1)
                        Icon(.arrowUpRight, size: 13)
                    }
                }
                .pill(.outline, size: .small)
                .tip("Official site")
            }
        }
    }
}

// MARK: - Pieces

/// Grokipedia's "Read the article ›": the chevron slides along on hover.
struct ArrowLink: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Icon(.chevronRight, size: 13)
                    .offset(x: hovering ? 3 : 0)
            }
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.42), value: hovering)
    }
}

/// A row of Grokipedia's numbered list: on hover the figure and title step 3 points right and
/// brighten, and the chevron slides in from 6 points back.
struct NumberedRow: View {
    let number: Int
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", number))
                    .font(.mono(11.5, weight: .regular))
                    .monospacedDigit()
                    .frame(width: 20, alignment: .leading)
                Text(title)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Icon(.chevronRight, size: 13)
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(hovering ? 1 : 0)
                    .offset(x: hovering ? 0 : -6)
            }
            .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
            .offset(x: hovering ? 3 : 0)
            .frame(height: 36)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.spring(0.42), value: hovering)
    }
}

/// The article as a book, the way Grokipedia's front page shows its featured article: a cover
/// with a spine and a block of pages, turned a little toward the reader, drifting and leaning in
/// an eight-second breath above a soft contact shadow.
struct GrokipediaBook: View {
    let title: String
    var images: [URL] = []
    var width: CGFloat = 132
    var height: CGFloat = 190

    @State private var drift = false
    @State private var imageFailed = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Grokipedia's covers come in deep, inky colors; each title gets its own.
    private var tint: Color {
        let palette: [UInt32] = [0x12352B, 0x14233F, 0x3B1519, 0x2A1838, 0x0F3138, 0x232A33, 0x3A2A12, 0x1E2F1A]
        let hash = title.unicodeScalars.reduce(UInt32(5381)) { ($0 << 5) &+ $0 &+ $1.value }
        return Theme.hex(palette[Int(hash % UInt32(palette.count))])
    }

    var body: some View {
        ZStack {
            // Contact and ambient shadows, breathing with the drift.
            Ellipse()
                .fill(Color.black.opacity(scheme == .dark ? 0.55 : 0.22))
                .frame(width: width * 0.86, height: 12)
                .blur(radius: 7)
                .scaleEffect(x: drift ? 1.01 : 1, y: drift ? 1.06 : 1)
                .opacity(drift ? 0.73 : 1)
                .offset(x: 6, y: height / 2 + 12)
            Ellipse()
                .fill(Color.black.opacity(scheme == .dark ? 0.35 : 0.12))
                .frame(width: width * 1.25, height: 34)
                .blur(radius: 18)
                .scaleEffect(x: drift ? 1.025 : 1, y: drift ? 1.07 : 1)
                .offset(x: 10, y: height / 2 + 10)

            book
                .rotation3DEffect(.degrees(drift ? -14.5 : -18), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.45)
                .rotationEffect(.degrees(drift ? -0.6 : 0))
                .offset(y: drift ? -8 : 0)
        }
        .frame(width: width + 40, height: height + 40)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
    }

    private var book: some View {
        let cover = UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 5, topTrailingRadius: 5, style: .continuous)
        return ZStack {
            // The block of pages, peeking out past the cover's edge.
            cover
                .fill(LinearGradient(colors: [Color(white: 0.93), Color(white: 0.82)], startPoint: .leading, endPoint: .trailing))
                .overlay(
                    VStack(spacing: 1.5) {
                        ForEach(0..<40, id: \.self) { _ in Rectangle().fill(Color.black.opacity(0.05)).frame(height: 0.5) }
                    }
                    .clipShape(cover)
                )
                .frame(width: width - 4, height: height - 6)
                .offset(x: 5, y: 1)

            ZStack(alignment: .bottomLeading) {
                tint
                if !images.isEmpty && !imageFailed {
                    RemoteImage(candidates: images, referer: "https://grokipedia.com/", showsPlaceholder: false) {
                        imageFailed = true
                    }
                    .frame(width: width, height: height)
                    .saturation(0.35)
                    .colorMultiply(Color(white: 0.92))
                    .blendMode(.luminosity)
                    .opacity(0.9)
                } else {
                    rings
                }
                // Tone the art into the cover color and shade the foot for the title.
                LinearGradient(colors: [tint.opacity(0.15), tint.opacity(0.55), .black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
                // The title scales with the cover, so a small book still reads "Mars", not "Mar s".
                Text(title)
                    .font(.serif(max(8, width * 0.13), weight: .medium))
                    .tracking(-width * 0.0023)
                    .foregroundStyle(Color(white: 0.97))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(.leading, width * 0.136)
                    .padding(.trailing, width * 0.09)
                    .padding(.bottom, width * 0.12)
                // The spine's hinge.
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.05)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 9)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                    Spacer(minLength: 0)
                }
                // Light across the cloth.
                LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.09), .white.opacity(0.0)],
                               startPoint: UnitPoint(x: drift ? 0.3 : 0.8, y: 0), endPoint: UnitPoint(x: drift ? 0.9 : 1.4, y: 1))
                    .blendMode(.screen)
            }
            .frame(width: width, height: height)
            .clipShape(cover)
            .overlay(cover.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
        .frame(width: width + 6, height: height)
    }

    /// Concentric rings, for covers without a picture.
    private var rings: some View {
        ZStack {
            ForEach(1..<9, id: \.self) { ring in
                Circle()
                    .strokeBorder(Color.white.opacity(0.05 + 0.006 * Double(ring)), lineWidth: 0.7)
                    .frame(width: CGFloat(ring) * 26, height: CGFloat(ring) * 26)
            }
        }
        .offset(y: -height * 0.12)
        .frame(width: width, height: height)
        .clipped()
    }
}

extension OfficialEntityDatabase.EntityKind {
    var label: String {
        switch self {
        case .company: String(localized: "Company")
        case .person: String(localized: "Person")
        case .organization: String(localized: "Organization")
        case .product: String(localized: "Product")
        case .place: String(localized: "Place")
        case .website: String(localized: "Website")
        }
    }
}

/// While the pad loads: a book-shaped hollow and lines, under grok.com's shimmer.
struct GrokipediaCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Icon(.book, size: 16)
                    .foregroundStyle(Theme.textTertiary)
                ShimmerText(text: String(localized: "Reading Grokipedia"), font: .system(size: 13, weight: .medium))
            }
            .frame(height: 28)
            .padding(.bottom, 14)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.hover)
                .frame(width: 132, height: 190)
                .rotation3DEffect(.degrees(-18), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 38)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.hover).frame(width: 180, height: 26)
                    .padding(.bottom, 8)
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.hover)
                        .frame(height: 10)
                        .frame(maxWidth: index == 4 ? 150 : .infinity, alignment: .leading)
                }
            }
        }
        .transition(.opacity)
    }
}

/// The small control over narrow pages, in Grokipedia's chip style.
struct GrokipediaChip: View {
    let title: String
    var loading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Icon(.book, size: 15)
                if loading {
                    ShimmerText(text: title, font: .system(size: 13, weight: .medium), base: Theme.textSecondary)
                } else {
                    Text(title).lineLimit(1)
                }
            }
        }
        .pill(.secondary, size: .small)
        .elevation(.menu)
    }
}
