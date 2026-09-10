import AppKit
import SwiftUI

/// Colors from the app icon. The menu itself stays on system materials; these carry the
/// welcome window and the art.
enum Brand {
    static let enamelTop = Color(red: 0x1B / 255, green: 0x33 / 255, blue: 0x29 / 255)
    static let enamelBottom = Color(red: 0x0A / 255, green: 0x15 / 255, blue: 0x10 / 255)
    static let bone = Color(red: 0xED / 255, green: 0xE7 / 255, blue: 0xD9 / 255)
    static let amber = Color(red: 0xCF / 255, green: 0x9F / 255, blue: 0x57 / 255)
}

enum Grain {
    static let image: NSImage = {
        let size = 160
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 1, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite,
                                   bytesPerRow: size, bitsPerPixel: 8)!
        for i in 0..<(size * size) { rep.bitmapData![i] = UInt8.random(in: 0...255) }
        let image = NSImage(size: NSSize(width: size / 2, height: size / 2))
        image.addRepresentation(rep)
        return image
    }()
}

/// The icon's green-black enamel as a full-bleed surface.
struct Enamel: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.enamelTop, Brand.enamelBottom], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .center)
            Image(nsImage: Grain.image)
                .resizable(resizingMode: .tile)
                .opacity(0.07)
                .blendMode(.overlay)
        }
        .ignoresSafeArea()
    }
}

/// The app icon drawn live: the two tracks trade usage back and forth, the way a switch hands
/// work from one account to the other.
struct HandoffMark: View {
    var body: some View {
        TimelineView(.animation) { context in
            let progress = Self.handoff(at: context.date.timeIntervalSinceReferenceDate)
            GeometryReader { geo in
                let s = geo.size.width
                ZStack {
                    RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.23, blue: 0.19), Brand.enamelBottom],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: s * 0.03, y: s * 0.025)
                    VStack(spacing: s * 0.068) {
                        MarkTrack(from: 0, to: 0.62 - 0.3 * progress, color: Brand.bone)
                            .frame(height: s * 0.15)
                        MarkTrack(from: 0.38 - 0.3 * progress, to: 1, color: Brand.amber)
                            .frame(height: s * 0.15)
                    }
                    .frame(width: s * 0.728)
                }
            }
        }
        .accessibilityLabel("Switchr")
    }

    /// Holds at each end of a five-second loop and eases across in between.
    static func handoff(at time: TimeInterval) -> Double {
        let t = (time / 5).truncatingRemainder(dividingBy: 1)
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        switch t {
        case ..<0.35: return 0
        case ..<0.5: return ease((t - 0.35) / 0.15)
        case ..<0.85: return 1
        default: return 1 - ease((t - 0.85) / 0.15)
        }
    }
}

private struct MarkTrack: View {
    let from: Double
    let to: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.34))
                Capsule()
                    .fill(color)
                    .frame(width: max(geo.size.height, w * (to - from)))
                    .offset(x: w * from)
            }
            .clipShape(Capsule())
        }
    }
}
