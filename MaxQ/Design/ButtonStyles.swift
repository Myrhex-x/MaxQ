//
//  ButtonStyles.swift
//  Max Q
//
//  SpaceXAI's controls, measured from x.ai and grok.com:
//    - Pills: 14 pt medium labels; white with near-black text for the main action, x.ai's dark
//      #202020 for the second, outlined like accounts.x.ai's sign-in choices, or ghost.
//      Heights 44 (hero), 40, 36, 32 and 28.
//    - Icon buttons: grok.com's round ghost buttons, grey glyphs that brighten on a 10% veil.
//    - Send: Grok's blue circle (dimmed until there is something to send); while Grok answers it
//      turns into a white circle with a stop square, as in SpaceXAI's chat.
//  Hovers take 120 ms; presses dip to 97%.
//

import SwiftUI

enum PillKind { case primary, secondary, ghost, outline }

enum PillSize {
    case hero, large, regular, small, mini

    var height: CGFloat {
        switch self { case .hero: 44; case .large: 40; case .regular: 36; case .small: 32; case .mini: 28 }
    }
    var font: Font {
        switch self {
        case .hero, .large, .regular: .system(size: 14, weight: .medium)
        case .small: .system(size: 13, weight: .medium)
        case .mini: .system(size: 12, weight: .medium)
        }
    }
    var padding: CGFloat {
        switch self { case .hero: 20; case .large: 18; case .regular: 16; case .small: 14; case .mini: 11 }
    }
}

struct PillButtonStyle: ButtonStyle {
    var kind: PillKind = .secondary
    var size: PillSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, size: size)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let kind: PillKind
        let size: PillSize
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(size.font)
                .lineLimit(1)
                .padding(.horizontal, size.padding)
                .frame(height: size.height)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
                .foregroundStyle(foreground)
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hovering)
                .animation(Motion.snappy, value: configuration.isPressed)
        }

        private var active: Bool { isEnabled && (hovering || configuration.isPressed) }

        private var fill: Color {
            switch kind {
            case .primary: active ? Theme.inkHover : Theme.ink
            case .secondary: active ? Theme.pillHover : Theme.pill
            case .ghost, .outline: configuration.isPressed ? Theme.selected : (active ? Theme.hover : .clear)
            }
        }

        private var stroke: Color {
            switch kind {
            case .outline: active ? Theme.borderStrong : Theme.border
            default: .clear
            }
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.onInk
            case .ghost: active ? Theme.textPrimary : Theme.textSecondary
            default: Theme.textPrimary
            }
        }
    }
}

/// grok.com's round ghost icon button.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 32
    /// Draw a resting fill (a selected or toggled-on state).
    var isActive = false
    /// A hairline ring at rest.
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, size: size, isActive: isActive, outlined: outlined)
    }

    private struct IconBody: View {
        let configuration: Configuration
        let size: CGFloat
        let isActive: Bool
        let outlined: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: size * 0.42, weight: .medium))
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(outlined ? Theme.border : .clear, lineWidth: 1))
                .foregroundStyle(foreground)
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hovering)
                .animation(Motion.snappy, value: configuration.isPressed)
        }

        private var fill: Color {
            guard isEnabled else { return .clear }
            if configuration.isPressed { return Theme.pressed }
            if hovering { return Theme.selected }
            return isActive ? Theme.hover : .clear
        }

        private var foreground: Color {
            guard isEnabled else { return Theme.textQuaternary }
            return hovering || isActive || configuration.isPressed ? Theme.textPrimary : Theme.textSecondary
        }
    }
}

/// Grok's round blue send button: full blue when there's something to send, dimmed until then.
struct SendButtonStyle: ButtonStyle {
    var size: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        SendBody(configuration: configuration, size: size)
    }

    private struct SendBody: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.onAccent)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.accent))
                .overlay(Circle().fill(Color.white.opacity(isEnabled && hovering ? 0.14 : 0)))
                .opacity(isEnabled ? 1 : 0.38)
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hovering)
                .animation(Motion.hover, value: isEnabled)
                .animation(Motion.snappy, value: configuration.isPressed)
        }
    }
}

/// The white circle with a stop square that stands in for send while Grok is answering.
struct StopButtonStyle: ButtonStyle {
    var size: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.onInk)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.ink))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Shorthands

extension View {
    func pill(_ kind: PillKind = .secondary, size: PillSize = .regular) -> some View {
        buttonStyle(PillButtonStyle(kind: kind, size: size))
    }
    func sendButton(size: CGFloat = 36) -> some View {
        buttonStyle(SendButtonStyle(size: size))
    }
    func stopButton(size: CGFloat = 36) -> some View {
        buttonStyle(StopButtonStyle(size: size))
    }
    func iconButton(size: CGFloat = 32, active: Bool = false, outlined: Bool = false) -> some View {
        buttonStyle(IconButtonStyle(size: size, isActive: active, outlined: outlined))
    }
    /// Older name for `iconButton`.
    func roundIcon(size: CGFloat = 32, outlined: Bool = false, active: Bool = false) -> some View {
        buttonStyle(IconButtonStyle(size: size, isActive: active, outlined: outlined))
    }
}
