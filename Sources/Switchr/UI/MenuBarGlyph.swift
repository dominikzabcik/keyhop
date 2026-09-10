#if os(macOS)
import AppKit
import SwiftUI

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
        image.accessibilityDescription = windows.isEmpty
            ? "Switchr"
            : "Switchr, " + windows.prefix(2).map { "\($0.label) \(Int($0.usedPercent.rounded())) percent used" }.joined(separator: ", ")
        return image
    }
}

struct ProviderMark: View {
    let provider: Provider
    var tint: Color?

    var body: some View {
        Image(nsImage: Marks.image(for: provider))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .accessibilityHidden(true)
    }
}
#endif
