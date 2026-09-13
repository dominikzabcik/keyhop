// Renders Keyhop's art in the dashboard's design: the app icon at every size (the macOS icon set,
// Linux PNGs and a Windows .ico), the disk image background and the README banner.
// Run through scripts/render-art.sh, which puts the output into Assets/, docs/ and packaging/.
import AppKit
import CoreGraphics
import CoreText

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func gray(_ value: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [value, value, value, alpha])!
}

/// The dashboard's neutrals.
enum Brand {
    static let surfaceTop = gray(0.125)
    static let surfaceBottom = gray(0.075)
    static let ink = gray(0.92)
    static let unlit = gray(1, 0.2)
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

/// Near-black with a faint light from the top. Fine grain keeps the gradient from banding.
func surface(_ ctx: CGContext, clip: CGPath, bounds: CGRect, grainScale: CGFloat, grain: Bool = true,
             top: CGColor = Brand.surfaceTop, bottom: CGColor = Brand.surfaceBottom) {
    let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    ctx.saveGState()
    ctx.addPath(clip)
    ctx.clip()
    ctx.drawLinearGradient(gradient(top, bottom),
                           start: CGPoint(x: bounds.midX, y: bounds.maxY), end: CGPoint(x: bounds.midX, y: bounds.minY), options: extend)
    if grain {
        ctx.setBlendMode(.overlay)
        ctx.setAlpha(0.07)
        ctx.draw(noise, in: CGRect(x: 0, y: 0, width: 256 * grainScale, height: 256 * grainScale), byTiling: true)
    }
    ctx.restoreGState()
}

/// Keyhop's K on its 24-unit grid: a solid stem, the joint that makes it a letter, and two arms with
/// the upper one hopped clear. `levels` (0...1 each) fills the arms, so the menu bar can show the two
/// nearest limits in the same shape. The logo itself keeps both arms solid.
func pixelMark(_ ctx: CGContext, center: CGPoint, width: CGFloat, levels: [CGFloat] = [1, 1]) {
    let unit = width / 24
    func place(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
        // The grid is read top-down; Core Graphics counts up, so y flips here.
        let rect = CGRect(x: center.x - 12 * unit + x * unit, y: center.y + 12 * unit - (y + h) * unit,
                          width: w * unit, height: h * unit)
        return CGPath(roundedRect: rect, cornerWidth: unit * 1.5, cornerHeight: unit * 1.5, transform: nil)
    }
    fill(ctx, place(2.5, 2.5, 6, 19.5), Brand.ink)
    fill(ctx, place(9.6, 9.2, 6, 6), Brand.ink)
    for (index, arm) in [place(16, 1, 6, 6), place(16, 17, 6, 6)].enumerated() {
        let lit = min(max(levels[index], 0), 1)
        fill(ctx, arm, Brand.unlit)
        if lit > 0 { fill(ctx, arm, Brand.ink.copy(alpha: lit)!) }
    }
}

func line(_ string: String, size: CGFloat, weight: NSFont.Weight, color: CGColor) -> CTLine {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
}

/// Draws a line of text centered on its glyphs, not its line box.
func draw(_ ctx: CGContext, _ line: CTLine, center: CGPoint) {
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX, y: center.y - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, ctx)
}

func png(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

func writePNG(_ image: CGImage, _ path: String) {
    try! png(image).write(to: URL(fileURLWithPath: path))
}

// MARK: Icon

func icon(pixels n: Int) -> CGImage {
    if n <= 32 { return smallIcon(pixels: n) }
    let ctx = canvas(n, n)
    ctx.scaleBy(x: CGFloat(n) / 1024, y: CGFloat(n) / 1024)
    let bounds = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = continuousRect(bounds, radius: bounds.width * 0.2245)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: gray(0, 0.32))
    fill(ctx, body, Brand.surfaceBottom)
    ctx.restoreGState()
    surface(ctx, clip: body, bounds: bounds, grainScale: 1024 / CGFloat(n), grain: n >= 128)
    pixelMark(ctx, center: CGPoint(x: 512, y: 512), width: 540)

    // Light catching the upper lip.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.clip(to: CGRect(x: 0, y: 640, width: 1024, height: 384))
    ctx.addPath(body)
    ctx.setStrokeColor(gray(1, 0.1))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

/// List, toolbar and tray sizes, drawn on whole pixels so the squares stay crisp: the shape fills
/// the square and the mark fills more of the shape.
func smallIcon(pixels n: Int) -> CGImage {
    let ctx = canvas(n, n)
    let size = CGFloat(n)
    let inset: CGFloat = n >= 24 ? 1 : 0
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let body = continuousRect(bounds.insetBy(dx: inset, dy: inset), radius: size * 0.22)
    surface(ctx, clip: body, bounds: bounds, grainScale: 1, grain: false)

    // Whole pixels on a three-row grid: stem, joint, and two arms, so even 16 pixels keeps the K.
    let arm = max(2, Int((Double(n) * 0.25).rounded()))
    let gap = max(1, Int((Double(n) * 0.055).rounded()))
    let height = arm * 3
    let left = (n - (arm * 3 + gap * 2)) / 2
    let top = (n - height) / 2
    let radius = CGFloat(arm) * 0.28
    func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: n - y - h, width: w, height: h), cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    fill(ctx, box(left, top, arm, height), Brand.ink)
    fill(ctx, box(left + arm + gap, top + arm, arm, arm), Brand.ink)
    fill(ctx, box(left + (arm + gap) * 2, top, arm, arm), Brand.ink)
    fill(ctx, box(left + (arm + gap) * 2, top + arm * 2, arm, arm), Brand.ink)
    return ctx.makeImage()!
}

/// A Windows icon file holding PNG images, which Windows reads since Vista.
func writeICO(sizes: [Int], _ path: String) {
    var data = Data()
    func u16(_ v: Int) { data.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
    func u32(_ v: Int) { u16(v & 0xFFFF); u16((v >> 16) & 0xFFFF) }
    let images = sizes.map { ($0, png(icon(pixels: $0))) }
    u16(0); u16(1); u16(images.count)
    var offset = 6 + 16 * images.count
    for (size, image) in images {
        data.append(contentsOf: [UInt8(size >= 256 ? 0 : size), UInt8(size >= 256 ? 0 : size), 0, 0])
        u16(1); u16(32); u32(image.count); u32(offset)
        offset += image.count
    }
    for (_, image) in images { data.append(image) }
    try! data.write(to: URL(fileURLWithPath: path))
}

// MARK: Disk image background (660 x 480 pt)

/// Finder colors icon labels black in light mode and white in dark mode, and a background image
/// can't tell which. This gray sits near 18% luminance, where both read. Finder on macOS 26 also
/// keeps its toolbar and status bar, so everything sits in the top 400 pt; on older systems the
/// rest is just more surface.
func dmgBackground(scale k: CGFloat) -> CGImage {
    let size = CGSize(width: 660, height: 480)
    let ctx = canvas(Int(size.width * k), Int(size.height * k))
    ctx.scaleBy(x: k, y: k)
    let bounds = CGRect(origin: .zero, size: size)
    surface(ctx, clip: CGPath(rect: bounds, transform: nil), bounds: bounds, grainScale: 1 / k, top: gray(0.47), bottom: gray(0.43))

    // Finder y (from the top) -> Core Graphics y (from the bottom).
    func y(_ fromTop: CGFloat) -> CGFloat { size.height - fromTop }

    // Icons sit at 175 pt from the top; between them the mark's squares light up toward Applications.
    let side: CGFloat = 12, gap: CGFloat = 8
    let rowWidth = side * 4 + gap * 3
    for (i, alpha) in [0.25, 0.45, 0.7, 1.0].enumerated() {
        let rect = CGRect(x: 330 - rowWidth / 2 + CGFloat(i) * (side + gap), y: y(175) - side / 2, width: side, height: side)
        fill(ctx, CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil), gray(0.08, alpha))
    }

    draw(ctx, line("Drag Keyhop into Applications", size: 16, weight: .semibold, color: gray(0.06)), center: CGPoint(x: 330, y: y(312)))
    draw(ctx, line("If macOS blocks the first launch: System Settings › Privacy & Security › Open Anyway",
                   size: 11.5, weight: .regular, color: gray(0.06)), center: CGPoint(x: 330, y: y(338)))
    return ctx.makeImage()!
}

// MARK: README banner (1280 x 420 pt)

func banner(scale k: CGFloat) -> CGImage {
    let size = CGSize(width: 1280, height: 420)
    let ctx = canvas(Int(size.width * k), Int(size.height * k))
    ctx.scaleBy(x: k, y: k)
    let bounds = CGRect(origin: .zero, size: size)
    surface(ctx, clip: CGPath(rect: bounds, transform: nil), bounds: bounds, grainScale: 1 / k, top: gray(0.105), bottom: gray(0.07))

    // The mark and the name as one group, centered on the banner.
    let name = line("Keyhop", size: 96, weight: .semibold, color: Brand.ink)
    let nameWidth = CTLineGetBoundsWithOptions(name, .useGlyphPathBounds).width
    let markWidth: CGFloat = 176, gap: CGFloat = 44
    let left = size.width / 2 - (markWidth + gap + nameWidth) / 2
    pixelMark(ctx, center: CGPoint(x: left + markWidth / 2, y: size.height / 2), width: markWidth)
    draw(ctx, name, center: CGPoint(x: left + markWidth + gap + nameWidth / 2, y: size.height / 2))
    return ctx.makeImage()!
}

// MARK: Main

let out = CommandLine.arguments[1]
let iconset = "\(out)/AppIcon.iconset"
let icons = "\(out)/icons"
for folder in [iconset, icons] {
    try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
}

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let suffix = scale == 2 ? "@2x" : ""
        writePNG(icon(pixels: points * scale), "\(iconset)/icon_\(points)x\(points)\(suffix).png")
    }
}
writePNG(icon(pixels: 1024), "\(out)/icon-1024.png")
for size in [16, 24, 32, 48, 64, 128, 256, 512] {
    writePNG(icon(pixels: size), "\(icons)/keyhop-\(size).png")
}
writeICO(sizes: [16, 24, 32, 48, 64, 128, 256], "\(out)/keyhop.ico")
writePNG(dmgBackground(scale: 1), "\(out)/dmg-background.png")
writePNG(dmgBackground(scale: 2), "\(out)/dmg-background@2x.png")
writePNG(banner(scale: 2), "\(out)/banner.png")
print("Rendered art into \(out)")
