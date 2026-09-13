#if os(macOS)
import AppKit
import SwiftUI

/// Menu bar icon: the K, drawn on whole pixels. With limits read, each arm is one of the account in
/// use's two nearest limits, lit as far as it's used.
enum MenuBarGlyph {
    /// `sweep` (0...1) replaces the data with the hop animation.
    static func image(windows: [UsageWindow], sweep: Double? = nil) -> NSImage {
        let arms = levels(windows: windows, sweep: sweep)
        // 16 x 16 points: a 4-point grid with 1-point gaps, whole pixels at 1x and 2x.
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ alpha: CGFloat) {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: 1, yRadius: 1).fill()
            }
            box(1, 2, 4, 12, 1)
            box(6, 6, 4, 4, 1)
            box(11, 2, 4, 4, 0.28 + 0.72 * arms[0])
            box(11, 10, 4, 4, 0.28 + 0.72 * arms[1])
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = windows.isEmpty
            ? "Keyhop"
            : "Keyhop, " + windows.prefix(2).map { "\($0.label) \(Int($0.usedPercent.rounded())) percent used" }.joined(separator: ", ")
        return image
    }

    /// How lit each arm is, 0...1. With nothing read yet both are solid, as in the logo.
    static func levels(windows: [UsageWindow], sweep: Double?) -> [Double] {
        if let sweep {
            let top = 0.5 - 0.42 * cos(sweep * 3 * 2 * .pi)
            return [top, 1 - top]
        }
        guard !windows.isEmpty else { return [1, 1] }
        return (0..<2).map { $0 < windows.count ? min(max(windows[$0].usedPercent / 100, 0), 1) : 0 }
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
