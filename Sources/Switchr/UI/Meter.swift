import AppKit
import SwiftUI

/// A usage track with a tick at the even-pace point, so "ahead of budget" reads at a glance.
struct Meter: View {
    let fraction: Double
    let pace: Double?
    let emphasized: Bool

    private let barHeight: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let value = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: barHeight)
                Capsule()
                    .fill(tint(value))
                    .frame(width: value > 0 ? max(barHeight, width * value) : 0, height: barHeight)
                if let pace {
                    Capsule()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 1.5, height: geo.size.height)
                        .offset(x: min(max(width * pace - 0.75, 0), width - 1.5))
                }
            }
            .frame(width: width, height: geo.size.height)
            .animation(.smooth(duration: 0.6), value: value)
        }
    }

    private func tint(_ value: Double) -> Color {
        if value >= 0.9 { return Color(red: 0.74, green: 0.42, blue: 0.37) }
        if let pace, value > pace + 0.08 { return Color(red: 0.76, green: 0.61, blue: 0.38) }
        return Color.primary.opacity(emphasized ? 0.7 : 0.36)
    }
}

/// Menu bar icon: the in-use account's two nearest limits as two short tracks.
enum MenuBarGlyph {
    /// `sweep` (0...1) replaces the data with the icon's hand-off animation.
    static func image(windows: [UsageWindow], sweep: Double? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let values: [Double?]
        if let sweep {
            let top = 0.5 - 0.42 * cos(sweep * 3 * 2 * .pi)
            values = [top, 1 - top]
        } else {
            values = (0..<2).map { $0 < windows.count ? windows[$0].usedPercent / 100 : nil }
        }
        let idle = windows.isEmpty && sweep == nil
        let image = NSImage(size: size, flipped: false) { rect in
            let barWidth: CGFloat = 16, barHeight: CGFloat = 3.5, gap: CGFloat = 3
            let x = (rect.width - barWidth) / 2
            let top = (rect.height + gap) / 2
            let rows = [top, top - gap - barHeight]
            for (i, y) in rows.enumerated() {
                let track = NSRect(x: x, y: y, width: barWidth, height: barHeight)
                NSColor.black.withAlphaComponent(idle ? 0.55 : 0.3).setFill()
                NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
                guard let raw = values[i] else { continue }
                let value = min(max(raw, 0), 1)
                guard value > 0 else { continue }
                let fill = NSRect(x: x, y: y, width: max(barHeight, barWidth * value), height: barHeight)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: fill, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Switchr"
        return image
    }
}

struct ProviderMark: View {
    let provider: Provider

    var body: some View {
        Image(nsImage: Marks.image(for: provider))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.secondary)
    }
}
