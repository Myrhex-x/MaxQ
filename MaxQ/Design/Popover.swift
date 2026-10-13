//
//  Popover.swift
//  Max Q
//
//  SpaceXAI-style menus and tooltips. Each one floats in its own borderless panel above the
//  window, so it is never clipped by a page, a scroll view or the sidebar, and grows from the
//  control that opened it the way grok.com's menus do: from 95%, fading in, over 200 ms on
//  (0.23, 1, 0.32, 1). Tooltips are grok.com's small dark labels, with a shortcut when there is one.
//

import AppKit
import SwiftUI

// MARK: - Anchoring

/// Remembers the AppKit view behind a SwiftUI control, so a popover can find it on screen.
final class ScreenAnchor {
    fileprivate weak var view: NSView?

    var window: NSWindow? { view?.window }
    /// The view itself, for AppKit pickers that anchor to a view.
    var anchorView: NSView? { view }

    var screenRect: NSRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

private struct AnchorReader: NSViewRepresentable {
    let anchor: ScreenAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

extension View {
    /// Lets popovers and tooltips find this view on screen.
    func screenAnchor(_ anchor: ScreenAnchor) -> some View {
        background(AnchorReader(anchor: anchor).allowsHitTesting(false))
    }
}

enum PopoverPlacement {
    case below(HorizontalAlignment)
    case above(HorizontalAlignment)
    case trailing

    fileprivate var unitAnchor: UnitPoint {
        switch self {
        case .below(let alignment): UnitPoint(x: alignment.unitX, y: 0)
        case .above(let alignment): UnitPoint(x: alignment.unitX, y: 1)
        case .trailing: .leading
        }
    }
}

private extension HorizontalAlignment {
    var unitX: CGFloat {
        switch self {
        case .leading: 0
        case .trailing: 1
        default: 0.5
        }
    }
}

// MARK: - Panels

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// The content's size changed (a check filling in as Grok writes).
    var onResize: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard let onResize else { return }
        DispatchQueue.main.async { onResize() }
    }
}

@Observable
final class PopoverPresentation {
    var shown = false
    var colorScheme: ColorScheme?
}

struct PopoverDismissAction {
    let action: () -> Void
    func callAsFunction() { action() }
}

extension EnvironmentValues {
    /// Closes the popover this view is in.
    @Entry var dismissPopover = PopoverDismissAction(action: {})
}

private struct PopoverRoot<Content: View>: View {
    let presentation: PopoverPresentation
    let anchor: UnitPoint
    let margin: CGFloat
    let content: Content

    var body: some View {
        content
            .scaleEffect(presentation.shown ? 1 : 0.95, anchor: anchor)
            .opacity(presentation.shown ? 1 : 0)
            .padding(margin)
            .environment(\.colorScheme, presentation.colorScheme ?? .dark)
    }
}

private extension NSWindow {
    var colorScheme: ColorScheme {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

/// One open menu.
final class PopoverController {
    /// The open menu. Held strongly: nothing else keeps a controller alive while its panel is up.
    private(set) static var active: PopoverController?
    /// The anchor of the menu an outside click just closed, so a click on its own button closes
    /// it instead of reopening it.
    private static var lastClosed: (anchor: ObjectIdentifier, time: Date)?

    private let panel: NSPanel
    private let presentation = PopoverPresentation()
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private weak var parent: NSWindow?
    private let anchorID: ObjectIdentifier
    private var onDismiss: (() -> Void)?
    private var closing = false
    private var appearanceObservation: NSKeyValueObservation?

    private static let margin: CGFloat = 28
    private static let gap: CGFloat = 6

    /// Opens `content` against `anchor`, or closes the menu already open there.
    @discardableResult
    static func toggle<Content: View>(anchor: ScreenAnchor, placement: PopoverPlacement,
                                      onDismiss: (() -> Void)? = nil,
                                      @ViewBuilder content: () -> Content) -> PopoverController? {
        let id = ObjectIdentifier(anchor)
        if let active, active.anchorID == id {
            active.dismiss()
            return nil
        }
        if let last = lastClosed, last.anchor == id, Date().timeIntervalSince(last.time) < 0.25 {
            return nil
        }
        active?.dismiss(animated: false)
        guard let rect = anchor.screenRect, let window = anchor.window else { return nil }
        let controller = PopoverController(anchorID: id, parent: window)
        controller.onDismiss = onDismiss
        controller.present(content(), at: rect, placement: placement)
        active = controller
        return controller
    }

    /// Opens `content` against a spot on screen rather than a control (a citation number in a
    /// paragraph), closing whatever menu is open.
    @discardableResult
    static func show<Content: View>(at screenRect: NSRect, in window: NSWindow, placement: PopoverPlacement,
                                    @ViewBuilder content: () -> Content) -> PopoverController {
        active?.dismiss(animated: false)
        let controller = PopoverController(anchorID: ObjectIdentifier(window), parent: window)
        controller.present(content(), at: screenRect, placement: placement)
        active = controller
        return controller
    }

    static func dismissActive() { active?.dismiss() }

    private init(anchorID: ObjectIdentifier, parent: NSWindow) {
        self.anchorID = anchorID
        self.parent = parent
        panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    private func present<Content: View>(_ content: Content, at anchorRect: NSRect, placement: PopoverPlacement) {
        presentation.colorScheme = parent?.colorScheme
        panel.appearance = parent?.effectiveAppearance
        // Follow the window if its appearance changes while the menu is open (the theme switch).
        appearanceObservation = parent?.observe(\.effectiveAppearance, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.appearance = window.effectiveAppearance
                withAnimation(Motion.standard(0.2)) { self.presentation.colorScheme = window.colorScheme }
            }
        }
        let root = PopoverRoot(presentation: presentation, anchor: placement.unitAnchor, margin: Self.margin,
                               content: content.environment(\.dismissPopover, PopoverDismissAction { [weak self] in self?.dismiss() }))
        let hosting = FirstMouseHostingView(rootView: root)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setFrame(frame(for: size, anchor: anchorRect, placement: placement), display: false)
        // Content that grows while it's open (an answer being written) takes the panel with it,
        // from the edge facing its anchor.
        hosting.onResize = { [weak self, weak hosting] in
            guard let self, let hosting, !self.closing else { return }
            let size = hosting.fittingSize
            guard size != self.panel.frame.size else { return }
            self.panel.setFrame(self.frame(for: size, anchor: anchorRect, placement: placement), display: true)
        }
        parent?.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        DispatchQueue.main.async { [presentation] in
            withAnimation(Motion.menu) { presentation.shown = true }
        }
        installMonitors()
    }

    private func frame(for size: NSSize, anchor: NSRect, placement: PopoverPlacement) -> NSRect {
        let margin = Self.margin
        var origin = NSPoint.zero
        switch placement {
        case .below(let alignment), .above(let alignment):
            let contentWidth = size.width - 2 * margin
            let contentX: CGFloat = switch alignment {
            case .leading: anchor.minX
            case .trailing: anchor.maxX - contentWidth
            default: anchor.midX - contentWidth / 2
            }
            origin.x = contentX - margin
            if case .below = placement {
                origin.y = anchor.minY - Self.gap - size.height + margin
            } else {
                origin.y = anchor.maxY + Self.gap - margin
            }
        case .trailing:
            origin.x = anchor.maxX + Self.gap - margin
            origin.y = anchor.midY - size.height / 2
        }
        var frame = NSRect(origin: origin, size: size)
        if let visible = (parent?.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX - margin + 4), visible.maxX - frame.width + margin - 4)
            frame.origin.y = min(max(frame.minY, visible.minY - margin + 4), visible.maxY - frame.height + margin - 4)
        }
        return frame
    }

    private func installMonitors() {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel {
                Self.lastClosed = (self.anchorID, Date())
                self.dismiss()
            }
            return event
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.dismiss()
                return nil
            }
            return event
        }) {
            monitors.append(monitor)
        }
        #if DEBUG
        // Screen checks drive a copy of the app from the background: its menus stay open while
        // another app is in front (`-MaxQKeepMenusOpen YES`).
        if UserDefaults.standard.bool(forKey: "MaxQKeepMenusOpen") { return }
        #endif
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) {
            monitors.append(monitor)
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }
    }

    func dismiss(animated: Bool = true) {
        guard !closing else { return }
        closing = true
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        appearanceObservation = nil
        if Self.active === self { Self.active = nil }
        onDismiss?()
        let panel = panel
        let parent = parent
        guard animated else {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            return
        }
        withAnimation(Motion.accelerate(0.14)) { presentation.shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
}

// MARK: - Menu buttons

/// A button that opens a SpaceXAI-style dropdown. The label gets whether the menu is open, so it
/// can show an open state (grok.com's model button fills and turns its chevron up).
struct MenuButton<Label: View, Content: View>: View {
    var placement: PopoverPlacement = .below(.leading)
    @ViewBuilder var label: (_ isOpen: Bool) -> Label
    @ViewBuilder var content: () -> Content

    @State private var anchor = ScreenAnchor()
    @State private var isOpen = false

    var body: some View {
        Button {
            let controller = PopoverController.toggle(anchor: anchor, placement: placement,
                                                      onDismiss: { isOpen = false }, content: content)
            isOpen = controller != nil
        } label: {
            label(isOpen)
        }
        .screenAnchor(anchor)
    }
}

/// The menu's card: Grokipedia's elevated surface, a hairline and the menu shadow.
struct MenuCard<Content: View>: View {
    var width: CGFloat? = 240
    @ViewBuilder var content: Content

    var body: some View {
        // The width it was drawn at, or wider when a row's title needs it (French runs about a
        // fifth longer than English), up to half as wide again. Details and notes wrap instead.
        MenuWidthLayout(minWidth: width ?? 0, maxWidth: width.map { $0 * 1.5 } ?? .infinity) {
            VStack(alignment: .leading, spacing: 1) {
                content
            }
            .padding(6)
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .elevation(.menu)
    }
}

/// Lays a menu's content out at its ideal width, kept between two bounds, then hands the rows that
/// width so their highlights reach both edges of the card.
private struct MenuWidthLayout: Layout {
    let minWidth: CGFloat
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = min(max(content.sizeThatFits(.unspecified).width, minWidth), maxWidth)
        let height = content.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

extension View {
    /// Text that wraps at whatever width its menu has, without asking for more: a detail, a note.
    func menuWrapping() -> some View {
        fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// One choice in a menu: glyph, title, optional detail, shortcut or check.
struct MenuRow: View {
    var icon: MQIcon? = nil
    var image: NSImage? = nil
    let title: Text
    var detail: Text? = nil
    var shortcut: String? = nil
    var checked = false
    var destructive = false
    var enabled = true
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.dismissPopover) private var dismiss

    /// A row in Max Q's own words (translated).
    init(icon: MQIcon? = nil, image: NSImage? = nil, title: LocalizedStringKey, detail: LocalizedStringKey? = nil,
         shortcut: String? = nil, checked: Bool = false, destructive: Bool = false, enabled: Bool = true,
         action: @escaping () -> Void) {
        self.init(icon: icon, image: image, text: Text(title), detail: detail.map { Text($0) }, shortcut: shortcut,
                  checked: checked, destructive: destructive, enabled: enabled, action: action)
    }

    /// A row whose words are already what to show (a name, a model, a page's title).
    init(icon: MQIcon? = nil, image: NSImage? = nil, verbatim title: String, detail: String? = nil,
         shortcut: String? = nil, checked: Bool = false, destructive: Bool = false, enabled: Bool = true,
         action: @escaping () -> Void) {
        self.init(icon: icon, image: image, text: Text(verbatim: title), detail: detail.map { Text(verbatim: $0) },
                  shortcut: shortcut, checked: checked, destructive: destructive, enabled: enabled, action: action)
    }

    private init(icon: MQIcon?, image: NSImage?, text: Text, detail: Text?, shortcut: String?, checked: Bool,
                 destructive: Bool, enabled: Bool, action: @escaping () -> Void) {
        self.icon = icon
        self.image = image
        self.title = text
        self.detail = detail
        self.shortcut = shortcut
        self.checked = checked
        self.destructive = destructive
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button {
            dismiss()
            action()
        } label: {
            HStack(spacing: 10) {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .frame(width: 18)
                } else if let icon {
                    Icon(icon, size: 18)
                        .foregroundStyle(destructive ? Theme.danger : (hovering ? Theme.textPrimary : Theme.textSecondary))
                }
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(.system(size: 14))
                        .foregroundStyle(destructive ? Theme.danger : Theme.textPrimary)
                        .lineLimit(1)
                    if let detail {
                        detail
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                            .menuWrapping()
                    }
                }
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textQuaternary)
                }
                if checked {
                    Icon(.check, size: 16)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, detail == nil ? 0 : 7)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering && enabled ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(Motion.standard(0.12), value: hovering)
    }
}

struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6)
    }
}

struct MenuSectionTitle: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

// MARK: - Tooltips

/// grok.com's tooltip: a small dark label under the control, with its shortcut.
private struct TooltipLabel: View {
    let text: Text
    let shortcut: String?

    var body: some View {
        HStack(spacing: 8) {
            text
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.onTooltip)
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.onTooltip.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.tooltip))
        .elevation(.raised)
    }
}

final class TooltipController {
    static let shared = TooltipController()

    private var panel: NSPanel?
    private let presentation = PopoverPresentation()
    private var lastHidden = Date.distantPast
    private var pending: Task<Void, Never>?
    private var owner: ObjectIdentifier?

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideNow() }
        }
    }

    /// Tooltips wait a beat, but follow at once while the pointer moves between controls.
    func schedule(_ text: Text, shortcut: String?, anchor: ScreenAnchor, placement: PopoverPlacement) {
        pending?.cancel()
        let warm = Date().timeIntervalSince(lastHidden) < 0.5 || panel?.isVisible == true
        let id = ObjectIdentifier(anchor)
        pending = Task { @MainActor [weak self] in
            if !warm { try? await Task.sleep(for: .milliseconds(650)) }
            guard !Task.isCancelled, let self else { return }
            self.show(text, shortcut: shortcut, anchor: anchor, placement: placement, id: id)
        }
    }

    func hide(for anchor: ScreenAnchor) {
        pending?.cancel()
        guard owner == ObjectIdentifier(anchor) else { return }
        hideNow()
    }

    func hideNow() {
        pending?.cancel()
        guard let panel, panel.isVisible else { return }
        owner = nil
        lastHidden = Date()
        withAnimation(Motion.accelerate(0.1)) { presentation.shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { [weak self] in
            guard let self, self.owner == nil else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func show(_ text: Text, shortcut: String?, anchor: ScreenAnchor, placement: PopoverPlacement, id: ObjectIdentifier) {
        guard PopoverController.active == nil, NSApp.isActive, let rect = anchor.screenRect, let window = anchor.window,
              window.isKeyWindow else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        owner = id
        let margin: CGFloat = 12
        presentation.colorScheme = window.colorScheme
        panel.appearance = window.effectiveAppearance
        let hosting = NSHostingView(rootView: PopoverRoot(presentation: presentation, anchor: placement.unitAnchor,
                                                          margin: margin,
                                                          content: TooltipLabel(text: text, shortcut: shortcut)))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        var origin: NSPoint
        switch placement {
        case .trailing:
            origin = NSPoint(x: rect.maxX + 8 - margin, y: rect.midY - size.height / 2)
        case .above:
            origin = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 6 - margin)
        case .below:
            origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - 6 - size.height + margin)
        }
        if let visible = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX - margin + 4), visible.maxX - size.width + margin - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        let wasVisible = panel.isVisible
        panel.orderFront(nil)
        if wasVisible {
            presentation.shown = true
        } else {
            presentation.shown = false
            DispatchQueue.main.async { [presentation] in
                withAnimation(Motion.outQuint(0.15)) { presentation.shown = true }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        return panel
    }
}

private struct TooltipModifier: ViewModifier {
    let text: Text
    let shortcut: String?
    let placement: PopoverPlacement

    @State private var anchor = ScreenAnchor()

    func body(content: Content) -> some View {
        content
            .screenAnchor(anchor)
            .onHover { inside in
                if inside {
                    TooltipController.shared.schedule(text, shortcut: shortcut, anchor: anchor, placement: placement)
                } else {
                    TooltipController.shared.hide(for: anchor)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { TooltipController.shared.hideNow() })
            .onDisappear { TooltipController.shared.hide(for: anchor) }
            .accessibilityHint(shortcut.map { text + Text(verbatim: ", \($0)") } ?? text)
    }
}

extension View {
    /// A grok.com-style tooltip, shown after a short rest and at once while moving between
    /// controls that have one.
    func tip(_ text: LocalizedStringKey, shortcut: String? = nil, placement: PopoverPlacement = .below(.center)) -> some View {
        modifier(TooltipModifier(text: Text(text), shortcut: shortcut, placement: placement))
    }

    /// A tooltip whose words are already what to show (a page's title, a figure).
    func tip(verbatim text: String, shortcut: String? = nil, placement: PopoverPlacement = .below(.center)) -> some View {
        modifier(TooltipModifier(text: Text(verbatim: text), shortcut: shortcut, placement: placement))
    }
}
