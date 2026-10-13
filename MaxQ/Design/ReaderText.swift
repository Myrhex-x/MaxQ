//
//  ReaderText.swift
//  Max Q
//
//  Long reading text, set in AppKit's own text view so it reads and behaves like text in a good
//  reader: it can be selected and copied, its layout never shifts when it's clicked, links show
//  the pointing hand, and a click on a link reports exactly where the link sits on screen (so a
//  citation's card can grow out of the very number that was clicked).
//

import AppKit
import SwiftUI

struct ReaderText: NSViewRepresentable {
    let text: NSAttributedString
    /// The pointer rests on a link (or left it: nil), with the link's rectangle on screen.
    var onHover: ((URL?, NSRect) -> Void)? = nil
    /// A link was clicked: where it goes, and the link's own rectangle on screen.
    let onLink: (URL, NSRect) -> Void

    func makeNSView(context: Context) -> ReaderTextView {
        let view = ReaderTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isRichText = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.delegate = context.coordinator
        view.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        view.setText(text)
        return view
    }

    func updateNSView(_ view: ReaderTextView, context: Context) {
        context.coordinator.onLink = onLink
        view.onHover = onHover
        if view.textStorage?.isEqual(to: text) != true {
            view.setText(text)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ReaderTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 660)
        return CGSize(width: width, height: view.height(forWidth: width))
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLink: onLink) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onLink: (URL, NSRect) -> Void

        init(onLink: @escaping (URL, NSRect) -> Void) { self.onLink = onLink }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard let url else { return false }
            onLink(url, Self.screenRect(of: charIndex, in: textView))
            return true
        }

        /// The rectangle of the link around `charIndex`, on screen.
        static func screenRect(of charIndex: Int, in textView: NSTextView) -> NSRect {
            guard let storage = textView.textStorage, let layout = textView.layoutManager,
                  let container = textView.textContainer, let window = textView.window,
                  charIndex < storage.length else { return .zero }
            var range = NSRange(location: charIndex, length: 1)
            _ = storage.attribute(.link, at: charIndex, longestEffectiveRange: &range,
                                  in: NSRange(location: 0, length: storage.length))
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            let inWindow = textView.convert(rect, to: nil)
            return window.convertToScreen(inWindow)
        }
    }
}

final class ReaderTextView: NSTextView {
    private var measured: (width: CGFloat, height: CGFloat)?
    /// Told when the pointer comes to rest on a link, and when it leaves it.
    var onHover: ((URL?, NSRect) -> Void)?
    private var hoveredLink: URL?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        guard onHover != nil else { return }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let onHover, let storage = textStorage, storage.length > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        var link: URL?
        var rect = NSRect.zero
        for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
            let value = storage.attribute(.link, at: candidate, effectiveRange: nil)
            if let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)) {
                let found = ReaderText.Coordinator.screenRect(of: candidate, in: self)
                // Only while the pointer is actually over the link's words.
                if let window, NSPointInRect(window.convertPoint(toScreen: event.locationInWindow), found.insetBy(dx: -2, dy: -2)) {
                    link = url
                    rect = found
                    break
                }
            }
        }
        guard link != hoveredLink else { return }
        hoveredLink = link
        onHover(link, rect)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if hoveredLink != nil {
            hoveredLink = nil
            onHover?(nil, .zero)
        }
    }

    func setText(_ text: NSAttributedString) {
        textStorage?.setAttributedString(text)
        measured = nil
    }

    /// The height the text takes at `width`.
    func height(forWidth width: CGFloat) -> CGFloat {
        if let measured, measured.width == width { return measured.height }
        guard let layout = layoutManager, let container = textContainer else { return 0 }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).height)
        measured = (width, height)
        return height
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // The page around the text scrolls; the text itself never does.
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    // A click that only places the caret leaves the keyboard to the page (J and K keep working).
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if selectedRange().length == 0, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }
}
