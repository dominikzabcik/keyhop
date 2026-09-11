#if os(macOS)
import AppKit
import SwiftUI

/// Menu bar icon: Switchr's pixel mark, two rows of four squares on the dashboard logo's grid. With
/// limits read, each row is one of the account in use's two nearest limits, lit as far as it's used.
enum MenuBarGlyph {
    /// `sweep` (0...1) replaces the data with the hand-off animation.
    static func image(windows: [UsageWindow], sweep: Double? = nil) -> NSImage {
        let levels = levels(windows: windows, sweep: sweep)
        // 22 x 12 points: squares of 4 with gaps of 2 across and 4 between rows, whole pixels at 2x.
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            for row in 0..<2 {
                for column in 0..<4 {
                    let lit = min(max(levels[row] - Double(column), 0), 1)
                    NSColor.black.withAlphaComponent(0.28 + 0.72 * lit).setFill()
                    let square = NSRect(x: CGFloat(column) * 6, y: 2 + CGFloat(row) * 8, width: 4, height: 4)
                    NSBezierPath(roundedRect: square, xRadius: 1, yRadius: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = windows.isEmpty
            ? "Switchr"
            : "Switchr, " + windows.prefix(2).map { "\($0.label) \(Int($0.usedPercent.rounded())) percent used" }.joined(separator: ", ")
        return image
    }

    /// Lit squares per row, 0...4. With nothing read yet it's the logo: three on top, one below.
    static func levels(windows: [UsageWindow], sweep: Double?) -> [Double] {
        if let sweep {
            let top = 0.5 - 0.42 * cos(sweep * 3 * 2 * .pi)
            return [top * 4, (1 - top) * 4]
        }
        guard !windows.isEmpty else { return [3, 1] }
        return (0..<2).map { $0 < windows.count ? min(max(windows[$0].usedPercent / 100, 0), 1) * 4 : 0 }
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
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(Brand.muted))
            .accessibilityHidden(true)
    }
}
#endif
