//
//  Theme.swift
//  Max Q
//
//  Design tokens, taken from SpaceXAI's own products and measured from their live pages
//  (grok.com, x.ai, grokipedia.com): grok.com's warm near-black and paper white, its surface and
//  border ladders, x.ai's white pills, Grokipedia's reading greys, Grok's blue send button and the
//  spectrum line both sites draw under their headlines. Values are inspiration only: no fonts,
//  logos or artwork of theirs ship with Max Q.
//

import AppKit
import CoreText
import SwiftUI

enum Theme {
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        }))
    }

    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: alpha)
    }

    /// HSL, as SpaceXAI's stylesheets write their palettes.
    static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double, _ alpha: Double = 1) -> Color {
        let s = saturation / 100, l = lightness / 100
        let c = (1 - abs(2 * l - 1)) * s
        let h = hue / 60
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        return Color(.sRGB, red: r + m, green: g + m, blue: b + m, opacity: alpha)
    }

    // MARK: Surfaces (back to front)

    /// The window: the sidebar and toolbar sit straight on it.
    static let canvas = dynamic(light: hex(0xEFEEEB), dark: hex(0x0B0A09))
    /// Pages and panels (grok.com's page color).
    static let surface = dynamic(light: hex(0xF9F8F7), dark: hex(0x131211))
    /// Cards and bubbles on a surface.
    static let raised = dynamic(light: hex(0xFFFFFF), dark: hex(0x1B1A18))
    /// Inputs and the composer (grok.com's composer).
    static let input = dynamic(light: hex(0xFFFFFF), dark: hex(0x201F1D))
    /// Menus and popovers.
    static let elevated = dynamic(light: hex(0xFFFFFF), dark: hex(0x222120))
    /// Tooltips.
    static let tooltip = dynamic(light: hex(0x1B1A18), dark: hex(0x2E2D2B))
    static let onTooltip = dynamic(light: hex(0xF4F3F2), dark: hex(0xF4F3F2))

    /// Veils for hover, selection and press (grok.com's ghost button fills).
    static let hover = dynamic(light: hex(0x0F0D0A, 0.045), dark: hex(0xFCFCFC, 0.06))
    static let selected = dynamic(light: hex(0x0F0D0A, 0.075), dark: hex(0xFCFCFC, 0.09))
    static let pressed = dynamic(light: hex(0x0F0D0A, 0.11), dark: hex(0xFCFCFC, 0.13))

    // MARK: Text (grok.com's fg ladder)

    static let textPrimary = dynamic(light: hex(0x050505), dark: hex(0xFCFCFC))
    static let textSecondary = dynamic(light: hsl(0, 0, 39), dark: hsl(0, 0, 62))
    static let textTertiary = dynamic(light: hsl(0, 0, 52), dark: hsl(0, 0, 52))
    static let textQuaternary = dynamic(light: hsl(0, 0, 66), dark: hsl(0, 0, 37))
    /// Long-form reading text (Grokipedia's body color).
    static let textReading = dynamic(light: hsl(0, 0, 13), dark: hsl(0, 0, 88))

    /// grok.com's citation chips and sources pill.
    static let chip = dynamic(light: hex(0xF5F3F2), dark: hex(0x181716))
    static let chipBorder = dynamic(light: hex(0x0F0D0A, 0.04), dark: hex(0xFCFCFC, 0.06))

    // MARK: Lines (grok.com's border ladder)

    static let hairline = dynamic(light: hex(0x0F0D0A, 0.07), dark: hex(0xFCFCFC, 0.07))
    static let border = dynamic(light: hex(0x0F0D0A, 0.10), dark: hex(0xFCFCFC, 0.11))
    static let borderStrong = dynamic(light: hex(0x0F0D0A, 0.15), dark: hex(0xFCFCFC, 0.16))
    static let focus = dynamic(light: hex(0x0F0D0A, 0.24), dark: hex(0xFCFCFC, 0.22))
    /// The composer's resting border (measured on grok.com).
    static let composerBorder = dynamic(light: hex(0xE6E5E3), dark: hex(0xFCFCFC, 0.06))

    // MARK: Ink (x.ai's white pill in dark mode, black in light)

    static let ink = dynamic(light: hex(0x0A0A0A), dark: hex(0xFFFFFF))
    static let onInk = dynamic(light: hex(0xFCFCFC), dark: hex(0x0A0A0A))
    static let inkHover = dynamic(light: hex(0x2B2B2B), dark: hsl(0, 0, 87))
    /// x.ai's dark secondary pill.
    static let pill = dynamic(light: hex(0x0F0D0A, 0.06), dark: hex(0x202020))
    static let pillHover = dynamic(light: hex(0x0F0D0A, 0.09), dark: hex(0x2A2A2A))

    // MARK: Accents

    /// Grok's send blue: the one bright accent, for "go" (send, ask, live state).
    static let accent = dynamic(light: hex(0x0890FF), dark: hex(0x299FFF))
    /// Glyphs on the accent (black arrow in dark mode, white in light, as grok.com draws it).
    static let onAccent = dynamic(light: hex(0xFCFCFC), dark: hex(0x050505))
    /// grok.com's link blue.
    static let link = dynamic(light: hsl(227, 56, 50), dark: hsl(227, 85, 75))
    /// The "New" orange on x.ai's badges.
    static let solar = hex(0xFF6308)
    static let success = dynamic(light: hsl(136, 100, 29), dark: hsl(122, 61, 72))
    static let warning = dynamic(light: hsl(45, 100, 29), dark: hsl(48, 98, 62))
    static let danger = dynamic(light: hsl(355, 63, 44), dark: hsl(357, 82, 71))

    /// The spectrum both grok.com and x.ai sweep through the line under a headline word.
    static let spectrum: [Color] = [hex(0x6366F1), hex(0xA855F7), hex(0xEC4899), hex(0xF97316), hex(0xEAB308)]

    // MARK: Private windows (grok.com's incognito purple)

    static let privateCanvas = dynamic(light: hsl(243, 60, 93), dark: hsl(245, 40, 5))
    static let privateSurface = dynamic(light: hsl(243, 100, 97), dark: hsl(245, 33, 8))
    static let privateRaised = dynamic(light: hex(0xFFFFFF), dark: hsl(245, 31, 14))
    static let privateTint = dynamic(light: hsl(245, 47, 51), dark: hsl(245, 74, 74))

    // MARK: Shape

    enum Radius {
        static let small: CGFloat = 8
        /// Rows and list items (rounded-xl).
        static let row: CGFloat = 12
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let panel: CGFloat = 16
        /// Menus and the search dropdown (Grokipedia's 20).
        static let menu: CGFloat = 20
        static let composer: CGFloat = 24
    }

    // MARK: Elevation (Grokipedia's shadow tokens)

    static func shadow(_ scheme: ColorScheme, strength: Double = 1) -> Color {
        Color.black.opacity((scheme == .dark ? 0.4 : 0.08) * strength)
    }
}

// MARK: - Elevation

enum Elevation {
    case composer, menu, raised

    fileprivate var layers: [(dark: Double, light: Double, radius: CGFloat, y: CGFloat)] {
        switch self {
        case .composer: [(0.20, 0.03, 3, 2), (0.18, 0.03, 6, 8)]
        case .menu: [(0.35, 0.05, 3, 2), (0.40, 0.08, 16, 12)]
        case .raised: [(0.30, 0.04, 4, 2), (0.0, 0.04, 4, 2)]
        }
    }
}

private struct ElevationModifier: ViewModifier {
    let elevation: Elevation
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let layers = elevation.layers
        content
            .shadow(color: .black.opacity(scheme == .dark ? layers[0].dark : layers[0].light), radius: layers[0].radius, y: layers[0].y)
            .shadow(color: .black.opacity(scheme == .dark ? layers[1].dark : layers[1].light), radius: layers[1].radius, y: layers[1].y)
    }
}

extension View {
    func elevation(_ elevation: Elevation) -> some View { modifier(ElevationModifier(elevation: elevation)) }
}

// MARK: - Typography

enum MQFonts {
    /// Registers the fonts bundled with Max Q (Geist Mono, SIL Open Font License).
    static func register() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static let monoFamily = "Geist Mono"
    /// Checked once, after `register()` has run at launch.
    static let hasMono: Bool = NSFontManager.shared.availableMembers(ofFontFamily: monoFamily) != nil
}

extension Font {
    /// Large display type: x.ai sets its headlines medium-light with tight tracking. Pair with
    /// `.displayTracking`.
    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    /// SF Pro at an exact weight on its variable axis. x.ai sets its hero at 450 and grok.com its
    /// headings at 550, between the named weights (regular 0, medium 0.23, semibold 0.3).
    static func variable(_ size: CGFloat, weight: CGFloat) -> Font {
        Font(NSFont.systemFont(ofSize: size, weight: NSFont.Weight(rawValue: weight)) as CTFont)
    }

    /// x.ai's headline weight (450 on their variable face; SF Pro's regular reads the same).
    static func hero(_ size: CGFloat) -> Font { variable(size, weight: 0.02) }
    /// The 550 of grok.com's headings.
    static func heading(_ size: CGFloat) -> Font { variable(size, weight: 0.27) }

    /// UI text sizes (grok.com: 13 meta, 14 chrome, 15 UI).
    static let mqTitle = Font.system(size: 15, weight: .semibold)
    static let mqBody = Font.system(size: 14)
    static let mqLabel = Font.system(size: 13, weight: .medium)
    static let mqCaption = Font.system(size: 12)
    static let mqMicro = Font.system(size: 11)

    /// Geist Mono, x.ai's and grok.com's monospace: figures, keys, codes.
    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        if MQFonts.hasMono {
            return .custom(MQFonts.monoFamily, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    /// Editorial serif for Grokipedia titles (Grokipedia sets them in a contemporary book serif).
    static func serif(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension View {
    /// Tight display tracking, as on x.ai (-1%) and grok.com (-2%) headlines.
    func displayTracking(_ size: CGFloat, percent: CGFloat = 1.6) -> some View {
        tracking(-size * percent / 100)
    }
}

/// A quiet sentence-case label naming a section ("Tabs", "Featured"), as on Grokipedia and x.ai.
struct SectionLabel: View {
    let text: LocalizedStringKey
    var trailing: String? = nil

    init(_ text: LocalizedStringKey, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            if let trailing {
                Text(trailing)
                    .font(.mono(11, weight: .regular))
                    .foregroundStyle(Theme.textQuaternary)
                    .contentTransition(.numericText())
            }
        }
    }
}

/// A keyboard shortcut drawn as a quiet key cap.
struct KeyHint: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.hover))
    }
}
