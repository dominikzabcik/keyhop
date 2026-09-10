// Renders Switchr's art: the app icon set, the disk image background, and the README banner.
// Run through scripts/render-art.sh, which turns the output into Assets/ and docs/.
import AppKit
import CoreGraphics
import CoreText

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ h: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}

enum Brand {
    static let top = hex(0x1B3329)
    static let bottom = hex(0x0A1510)
    static let bone = hex(0xEDE7D9)
    static let amber = hex(0xCF9F57)
    static let dim = hex(0x93A59B)
    static let groove = hex(0x000000, 0.34)
}

func canvas(_ width: Int, _ height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func gradient(_ a: CGColor, _ b: CGColor) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: [a, b] as CFArray, locations: [0, 1])!
}

/// Apple's continuous-corner rounded rectangle, the shape of a macOS app icon. Each corner is
/// the same curve, given as offsets (along the incoming edge, along the outgoing edge) in
/// units of the corner radius.
func continuousRect(_ rect: CGRect, radius r: CGFloat) -> CGPath {
    typealias P = (CGFloat, CGFloat)
    let corner: [(to: P, c1: P?, c2: P?)] = [
        ((0.66993427, 0.06549600), (1.08849323, 0), (0.86840689, 0)),
        ((0.63149399, 0.07491100), nil, nil),
        ((0.07491100, 0.63149399), (0.37282392, 0.16905899), (0.16905899, 0.37282392)),
        ((0.06549600, 0.66993427), nil, nil),
        ((0, 1.52866483), (0, 0.86840689), (0, 1.08849323)),
    ]
    // Maps a corner offset to a point, walking clockwise: top right, bottom right, bottom left, top left.
    let maps: [(P) -> CGPoint] = [
        { CGPoint(x: rect.maxX - $0.0 * r, y: rect.maxY - $0.1 * r) },
        { CGPoint(x: rect.maxX - $0.1 * r, y: rect.minY + $0.0 * r) },
        { CGPoint(x: rect.minX + $0.0 * r, y: rect.minY + $0.1 * r) },
        { CGPoint(x: rect.minX + $0.1 * r, y: rect.maxY - $0.0 * r) },
    ]
    let path = CGMutablePath()
    for (i, map) in maps.enumerated() {
        let start = map((1.52866483, 0))
        i == 0 ? path.move(to: start) : path.addLine(to: start)
        for segment in corner {
            if let c1 = segment.c1, let c2 = segment.c2 {
                path.addCurve(to: map(segment.to), control1: map(c1), control2: map(c2))
            } else {
                path.addLine(to: map(segment.to))
            }
        }
    }
    path.closeSubpath()
    return path
}

func capsule(_ r: CGRect) -> CGPath {
    let radius = min(r.width, r.height) / 2
    return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

let noise: CGImage = {
    let n = 256
    var pixels = [UInt8](repeating: 255, count: n * n * 4)
    for i in 0..<(n * n) {
        let v = UInt8.random(in: 0...255)
        pixels[i * 4] = v; pixels[i * 4 + 1] = v; pixels[i * 4 + 2] = v
    }
    let ctx = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}()

/// The Switchr surface: green-black enamel, a raking light from the upper left, fine grain.
func enamel(_ ctx: CGContext, clip: CGPath, bounds: CGRect, grainScale: CGFloat,
            top: CGColor = Brand.top, bottom: CGColor = Brand.bottom) {
    let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    ctx.saveGState()
    ctx.addPath(clip)
    ctx.clip()
    ctx.drawLinearGradient(gradient(top, bottom),
                           start: CGPoint(x: bounds.midX, y: bounds.maxY), end: CGPoint(x: bounds.midX, y: bounds.minY), options: extend)
    ctx.drawLinearGradient(gradient(hex(0xFFFFFF, 0.09), hex(0xFFFFFF, 0)),
                           start: CGPoint(x: bounds.minX + bounds.width * 0.2, y: bounds.maxY),
                           end: CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.45), options: extend)
    ctx.setBlendMode(.overlay)
    ctx.setAlpha(0.10)
    ctx.draw(noise, in: CGRect(x: 0, y: 0, width: 256 * grainScale, height: 256 * grainScale), byTiling: true)
    ctx.restoreGState()
}

/// A usage track: recessed groove with a fill segment, clipped so the caps stay round.
func track(_ ctx: CGContext, _ rect: CGRect, from: CGFloat, to: CGFloat, color: CGColor) {
    fill(ctx, capsule(rect), Brand.groove)
    ctx.saveGState()
    ctx.addPath(capsule(rect))
    ctx.clip()
    fill(ctx, capsule(CGRect(x: rect.minX + rect.width * from, y: rect.minY, width: rect.width * (to - from), height: rect.height)), color)
    ctx.restoreGState()
}

func text(_ ctx: CGContext, _ string: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, center: CGPoint, kern: CGFloat = 0) {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        .kern: kern,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX, y: center.y - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, ctx)
}

func writePNG(_ image: CGImage, _ path: String) {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

// MARK: Icon

func icon() -> CGImage {
    let ctx = canvas(1024, 1024)
    let bounds = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = continuousRect(bounds, radius: 185)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: hex(0x000000, 0.32))
    fill(ctx, body, Brand.bottom)
    ctx.restoreGState()
    enamel(ctx, clip: body, bounds: bounds, grainScale: 1)

    // Two accounts handing usage across: one fills from the left, the other from the right.
    let width: CGFloat = 600, height: CGFloat = 124, x = 512 - width / 2
    track(ctx, CGRect(x: x, y: 540, width: width, height: height), from: 0, to: 0.62, color: Brand.bone)
    track(ctx, CGRect(x: x, y: 360, width: width, height: height), from: 0.38, to: 1, color: Brand.amber)

    // Light catching the upper lip.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.clip(to: CGRect(x: 0, y: 640, width: 1024, height: 384))
    ctx.addPath(body)
    ctx.setStrokeColor(hex(0xFFFFFF, 0.13))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

// MARK: Disk image background (660 x 480 pt)

/// Finder colors icon labels black in light mode and white in dark mode, and a background image
/// can't tell which. This sage sits at about 18% luminance, where both reach roughly 4.5:1.
/// Finder on macOS 26 also keeps its toolbar and status bar, so everything sits in the top
/// 400 pt; on older systems the rest is just more surface.
func dmgBackground(scale k: CGFloat) -> CGImage {
    let size = CGSize(width: 660, height: 480)
    let ctx = canvas(Int(size.width * k), Int(size.height * k))
    ctx.scaleBy(x: k, y: k)
    let bounds = CGRect(origin: .zero, size: size)
    enamel(ctx, clip: CGPath(rect: bounds, transform: nil), bounds: bounds, grainScale: 1 / k,
           top: hex(0x6A8679), bottom: hex(0x58715F))

    // Finder y (from the top) -> Core Graphics y (from the bottom).
    func y(_ fromTop: CGFloat) -> CGFloat { size.height - fromTop }

    // Icons sit at 175 pt from the top; the track leads from Switchr to Applications.
    track(ctx, CGRect(x: 266, y: y(175) - 6, width: 128, height: 12), from: 0, to: 0.78, color: Brand.bone)

    text(ctx, "Drag Switchr into Applications", size: 16, weight: .semibold, color: Brand.bottom, center: CGPoint(x: 330, y: y(312)))
    text(ctx, "If macOS blocks the first launch: System Settings › Privacy & Security › Open Anyway",
         size: 11.5, weight: .regular, color: Brand.bottom, center: CGPoint(x: 330, y: y(338)))
    return ctx.makeImage()!
}

// MARK: README banner (1280 x 420 pt)

func banner(scale k: CGFloat) -> CGImage {
    let size = CGSize(width: 1280, height: 420)
    let ctx = canvas(Int(size.width * k), Int(size.height * k))
    ctx.scaleBy(x: k, y: k)
    let bounds = CGRect(origin: .zero, size: size)
    enamel(ctx, clip: CGPath(rect: bounds, transform: nil), bounds: bounds, grainScale: 1 / k)

    // The icon's two tracks at full width, bleeding off both edges, with the name set between them.
    let span = CGRect(x: -60, y: 0, width: size.width + 120, height: 44)
    track(ctx, span.offsetBy(dx: 0, dy: 300), from: 0, to: 0.62, color: Brand.bone)
    track(ctx, span.offsetBy(dx: 0, dy: 76), from: 0.38, to: 1, color: Brand.amber)
    text(ctx, "Switchr", size: 104, weight: .bold, color: Brand.bone, center: CGPoint(x: 640, y: 210), kern: 1)
    return ctx.makeImage()!
}

// MARK: Main

let out = CommandLine.arguments[1]
let iconset = "\(out)/AppIcon.iconset"
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let master = icon()
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let pixels = points * scale
        let ctx = canvas(pixels, pixels)
        ctx.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let suffix = scale == 2 ? "@2x" : ""
        writePNG(ctx.makeImage()!, "\(iconset)/icon_\(points)x\(points)\(suffix).png")
    }
}
writePNG(master, "\(out)/icon-1024.png")
writePNG(dmgBackground(scale: 1), "\(out)/dmg-background.png")
writePNG(dmgBackground(scale: 2), "\(out)/dmg-background@2x.png")
writePNG(banner(scale: 2), "\(out)/banner.png")
print("Rendered art into \(out)")
