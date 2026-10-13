//
//  Motion.swift
//  Max Q
//
//  Max Q's motion, built from the curves and timings SpaceXAI's sites actually use (read from
//  their stylesheets and running animations):
//    - Grokipedia's "spring" ease (0.22, 1, 0.36, 1) for things that rise into place, 400 ms.
//    - grok.com's menus: 200 ms on (0.23, 1, 0.32, 1), scaling up from 95%.
//    - The underline wipe and blur-ins: (0.16, 1, 0.3, 1).
//    - Hovers: 100 to 150 ms on (0.4, 0, 0.2, 1).
//    - x.ai's chat entries: a touch of overshoot, (0.2, 0.9, 0.3, 1.15).
//  Interactive changes (a selection moving, a panel opening) use springs, so they stay fluid
//  when interrupted.
//

import SwiftUI

enum Motion {
    // MARK: Curves

    /// Grokipedia's `--ease-spring`: fast out, long gentle settle.
    static func spring(_ duration: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    /// grok.com's menu and toast curve.
    static func outQuint(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    /// x.ai's and grok.com's underline wipe and blur-in curve.
    static func expo(_ duration: Double) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: duration) }
    /// Grokipedia's `--ease-standard`, for color and opacity.
    static func standard(_ duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
    /// Grokipedia's `--ease-decelerate` (its search dropdown).
    static func decelerate(_ duration: Double) -> Animation { .timingCurve(0, 0, 0, 1, duration: duration) }
    /// Grokipedia's `--ease-accelerate` (things leaving).
    static func accelerate(_ duration: Double) -> Animation { .timingCurve(0.3, 0, 1, 1, duration: duration) }
    /// x.ai's chat entries, which overshoot a hair.
    static func overshoot(_ duration: Double) -> Animation { .timingCurve(0.2, 0.9, 0.3, 1.15, duration: duration) }

    // MARK: Named uses

    /// Hover and press feedback.
    static let hover = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.12)
    static let quick = hover
    /// Menus, popovers, tooltips.
    static let menu = outQuint(0.2)
    /// Content rising into place.
    static let rise = spring(0.4)
    /// Headlines (x.ai's hero words).
    static let reveal = spring(0.65)

    // grok.com's springs (stiffness and damping, mass 1), as its code sets them.

    /// A selection or segment thumb gliding to its new place (grok.com: 500 / 35).
    static let glide = Animation.interpolatingSpring(mass: 1, stiffness: 500, damping: 35)
    /// Small elements: chips, presses (grok.com: 1000 / 52).
    static let snappy = Animation.interpolatingSpring(mass: 1, stiffness: 1000, damping: 52)
    /// The chevron folding between down and up (grok.com: 400 / 30).
    static let chevron = Animation.interpolatingSpring(mass: 1, stiffness: 400, damping: 30)
    /// Panels and layout (grok.com: 700 / 50).
    static let smooth = Animation.interpolatingSpring(mass: 1, stiffness: 700, damping: 50)
    /// A small, bouncy confirmation (a check landing).
    static let pop = Animation.spring(response: 0.34, dampingFraction: 0.58)
    /// Things growing out of the control that opened them (grok.com's reaction pill: 0.3 s expo).
    static let grow = expo(0.3)
    /// Whole pages sliding to the next tab: critically damped, so a page lands without bouncing
    /// and a quick second click simply redirects it.
    static let page = Animation.interpolatingSpring(mass: 1, stiffness: 340, damping: 37)
}

// MARK: - Transitions

/// Grokipedia's `rise`: fade in while lifting 8 points.
private struct RiseModifier: ViewModifier {
    let shown: Bool
    var distance: CGFloat = 8
    var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : scale)
            .offset(y: shown ? 0 : distance)
    }
}

/// grok.com's menus: scale up from 95% at their anchor, fading in.
private struct PopModifier: ViewModifier {
    let shown: Bool
    let anchor: UnitPoint
    var scale: CGFloat = 0.95

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : scale, anchor: anchor)
    }
}

/// x.ai's blur-in: 4 points of blur clearing as it fades in.
private struct BlurFadeModifier: ViewModifier {
    let shown: Bool
    var radius: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : radius)
    }
}

extension AnyTransition {
    /// Rises 8 points into place; leaves by fading.
    static var rise: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: RiseModifier(shown: false), identity: RiseModifier(shown: true)),
            removal: .opacity
        )
    }

    /// Grokipedia's card enter (up 8, from 98%) and exit (up 16, fading).
    static var card: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: RiseModifier(shown: false, distance: 8, scale: 0.98),
                                 identity: RiseModifier(shown: true, distance: 8, scale: 0.98)),
            removal: .modifier(active: RiseModifier(shown: false, distance: -16),
                               identity: RiseModifier(shown: true, distance: -16))
        )
    }

    /// A menu or popover growing from its anchor.
    static func pop(anchor: UnitPoint, scale: CGFloat = 0.95) -> AnyTransition {
        .modifier(active: PopModifier(shown: false, anchor: anchor, scale: scale),
                  identity: PopModifier(shown: true, anchor: anchor, scale: scale))
    }

    /// Fading in out of a slight blur.
    static func blurFade(radius: CGFloat = 4) -> AnyTransition {
        .modifier(active: BlurFadeModifier(shown: false, radius: radius), identity: BlurFadeModifier(shown: true, radius: radius))
    }

    /// grok.com's glyph swap (copy to check): out of 85% and 3 points of blur, 200 ms.
    static var glyphSwap: AnyTransition {
        AnyTransition.modifier(active: GlyphSwapModifier(shown: false), identity: GlyphSwapModifier(shown: true))
            .animation(Motion.outQuint(0.2))
    }

    /// grok.com's status label: the new one rises 3 points in 160 ms, the old one fades in 90 ms.
    static var statusSwap: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.modifier(active: RiseModifier(shown: false, distance: 3), identity: RiseModifier(shown: true, distance: 3))
                .animation(Motion.spring(0.16)),
            removal: AnyTransition.opacity.animation(.linear(duration: 0.09))
        )
    }

    /// grok.com's collapsed-sidebar icons: 8 points low and blurred, settling in 300 ms.
    static var settle: AnyTransition {
        AnyTransition.modifier(active: SettleModifier(shown: false), identity: SettleModifier(shown: true))
            .animation(Motion.spring(0.3))
    }

    /// Grokipedia's icon swap: the old glyph turns away as the new one turns in.
    static var iconSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: IconSwapModifier(progress: -1), identity: IconSwapModifier(progress: 0)),
            removal: .modifier(active: IconSwapModifier(progress: 1), identity: IconSwapModifier(progress: 0))
        )
    }
}

private struct GlyphSwapModifier: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.85)
            .blur(radius: shown ? 0 : 3)
    }
}

private struct SettleModifier: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .blur(radius: shown ? 0 : 4)
    }
}

private struct IconSwapModifier: ViewModifier {
    /// -1 arriving, 0 shown, 1 leaving.
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - abs(progress))
            .scaleEffect(1 - abs(progress) * 0.5)
            .rotationEffect(.degrees(progress * 45))
    }
}

// MARK: - Staggered entrances

/// Shows content with a Grokipedia rise once `revealed` turns true, after `delay`.
private struct RevealModifier: ViewModifier {
    let revealed: Bool
    var delay: Double = 0
    var distance: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: reduceMotion || revealed ? 0 : distance)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.rise.delay(delay), value: revealed)
    }
}

extension View {
    /// Staggered entrance: the Grokipedia home page rises its parts 60 ms apart.
    func reveal(_ revealed: Bool, delay: Double = 0, distance: CGFloat = 8) -> some View {
        modifier(RevealModifier(revealed: revealed, delay: delay, distance: distance))
    }
}

// MARK: - Press feedback

/// Dips a control slightly while pressed.
struct PressScale: ViewModifier {
    let pressed: Bool
    var amount: CGFloat = 0.97

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? amount : 1)
            .animation(Motion.snappy, value: pressed)
    }
}
