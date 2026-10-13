//
//  SiteIcon.swift
//  Max Q
//
//  A site's own icon, with a small backing plate when the icon is a dark glyph on a dark canvas
//  (or a light glyph on a light one) so it never disappears.
//

import SwiftUI

struct SiteIcon: View {
    let image: NSImage
    let tone: IconTone
    var size: CGFloat
    var cornerRadius: CGFloat? = nil

    @Environment(\.colorScheme) private var scheme

    private var plate: Color? {
        switch (tone, scheme) {
        case (.darkGlyph, .dark): Color.white.opacity(0.92)
        case (.lightGlyph, .light): Color.black.opacity(0.85)
        default: nil
        }
    }

    var body: some View {
        let radius = cornerRadius ?? size * 0.22
        if let plate {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(size * 0.14)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(plate))
        } else {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}
