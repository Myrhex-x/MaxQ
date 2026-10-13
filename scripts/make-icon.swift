// Renders the Max Q app icon at every macOS size into the asset catalog.
//
//   swift scripts/make-icon.swift
//
// The icon: a black, softly lit squircle with a faint starfield, the ascent trajectory and the
// single bright "max Q" point. Same geometry as MaxQMark.swift. Monochrome on purpose.

import AppKit
import CoreGraphics

let outputDir = URL(fileURLWithPath: "MaxQ/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

// Cubic Bezier from MaxQGeometry, in unit space (y down).
let p0 = CGPoint(x: 0.16, y: 0.90), c1 = CGPoint(x: 0.20, y: 0.50)
let c2 = CGPoint(x: 0.44, y: 0.22), p3 = CGPoint(x: 0.90, y: 0.15)
let markerT: CGFloat = 0.40

func bezier(_ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                   y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS icon grid: the squircle sits inside an 824/1024 box, centered.
    let inset = s * (100.0 / 1024.0)
    let box = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = box.width * 0.225
    let squircle = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Base: near-black with a soft light pool high up (the home page's ambient light).
    let base = CGGradient(colorsSpace: colorSpace,
                          colors: [CGColor(gray: 0.13, alpha: 1), CGColor(gray: 0.015, alpha: 1)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(base, startCenter: CGPoint(x: box.midX, y: box.minY + box.height * 0.72),
                           startRadius: 0, endCenter: CGPoint(x: box.midX, y: box.minY + box.height * 0.6),
                           endRadius: box.width * 0.85, options: [.drawsAfterEndLocation])

    // Starfield (deterministic).
    if size >= 64 {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rand() -> CGFloat {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return CGFloat(seed % 10_000) / 10_000
        }
        for _ in 0..<70 {
            let x = box.minX + rand() * box.width
            let y = box.minY + rand() * box.height
            let r = s * (0.0015 + rand() * 0.0028)
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.12 + rand() * 0.38))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    // Map unit space (y down) into the box (CG y up).
    func map(_ p: CGPoint) -> CGPoint {
        let pad = box.width * 0.16
        let inner = box.insetBy(dx: pad, dy: pad)
        return CGPoint(x: inner.minX + p.x * inner.width, y: inner.maxY - p.y * inner.height)
    }

    // Trajectory: thin at the bottom, fading in toward the top.
    let path = CGMutablePath()
    path.move(to: map(p0))
    path.addCurve(to: map(p3), control1: map(c1), control2: map(c2))
    let lineWidth = max(1.5, s * 0.022)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let stroke = CGGradient(colorsSpace: colorSpace,
                            colors: [CGColor(gray: 1, alpha: 0.0), CGColor(gray: 1, alpha: 0.95)] as CFArray,
                            locations: [0, 1])!
    ctx.drawLinearGradient(stroke, start: map(CGPoint(x: p0.x, y: 1.0)), end: map(CGPoint(x: p3.x, y: 0.0)), options: [])
    ctx.restoreGState()

    // The max Q point: glow, pressure ring, bright core.
    let center = map(bezier(markerT))
    let core = s * 0.036
    let glow = CGGradient(colorsSpace: colorSpace,
                          colors: [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0.0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: core * 4.2, options: [])
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.24))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokeEllipse(in: CGRect(x: center.x - core * 2.3, y: center.y - core * 2.3, width: core * 4.6, height: core * 4.6))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))

    // Rim light along the top edge of the tile.
    ctx.addPath(squircle)
    ctx.setLineWidth(s * 0.006)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
    ctx.strokePath()
    ctx.restoreGState()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (size, scale) in sizes {
    let pixels = size * scale
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try! render(size: pixels).write(to: outputDir.appendingPathComponent(name))
    print("wrote \(name) (\(pixels)px)")
}
try! render(size: 1024).write(to: URL(fileURLWithPath: "docs/icon-1024.png"))
print("wrote docs/icon-1024.png")
