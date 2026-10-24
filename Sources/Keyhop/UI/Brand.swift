#if os(macOS)
import AppKit
import CoreText
import SwiftUI

/// The design tokens of the Keyhop 2.0 world, so the menu, the welcome window and Keyhop's window
/// read as one app: warm charcoal surfaces, hairlines cut from the paper ink, paper-on-ink actions,
/// color only where it means a state, and brand blue only inside the K mark.
enum Brand {
    static let background = Color(hex: "#0C0B0A")
    static let sidebar = Color(hex: "#090807")
    static let panel = Color(hex: "#121110")
    static let raised = Color(hex: "#181613")
    static let raisedHover = Color(hex: "#201D19")
    static let hover = Color(hex: "#FFFAF0").opacity(0.05)
    static let selected = Color(hex: "#FFFAF0").opacity(0.09)
    static let border = Color(hex: "#FFFAF0").opacity(0.07)
    static let borderStrong = Color(hex: "#FFFAF0").opacity(0.12)
    static let faint = Color(hex: "#FFFAF0").opacity(0.05)
    static let text = Color(hex: "#ECEAE5")
    static let muted = Color(hex: "#A8A49B")
    static let subtle = Color(hex: "#8B8780")
    /// Actions are paper on ink; blue stopped being a button color in 2.0.
    static let primary = Color(hex: "#ECEAE5")
    static let primaryHover = Color(hex: "#F8F6F1")
    static let onPrimary = Color(hex: "#121110")
    /// The one blue, and it lives only in the K mark.
    static let blue = Color(hex: "#2F5FD9")
    static let good = Color(hex: "#4FAE72")
    static let warn = Color(hex: "#D9A03A")
    /// Red as text; `red` is the same state as a fill or a ring.
    static let bad = Color(hex: "#E8705F")
    static let red = Color(hex: "#E05746")

    /// The window's ground, the page's --g0: warm charcoal behind loads, resizes and corners.
    static let backgroundColor = NSColor(srgbRed: 0x0c / 255, green: 0x0b / 255, blue: 0x0a / 255, alpha: 1)

    /// The system face: the window speaks SF, so the menu and the welcome window do too.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Figures: a step heavier with digits of one width, so a number that changes never
    /// shifts what stands beside it.
    static func figure(_ size: CGFloat) -> Font {
        sans(size, weight: .semibold).monospacedDigit()
    }

    /// Names and headings: a step heavier than the text around it.
    static func heading(_ size: CGFloat) -> Font {
        sans(size, weight: .semibold)
    }
}

extension Color {
    init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

extension View {
    /// The dashboard's card: a panel one step above the background, edged in its own light. The
    /// edge is brighter along the top lip, the way a raised surface catches the light, rather than
    /// a drawn grey outline.
    func card(radius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Brand.panel))
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(
                colors: [Color(hex: "#FFFAF0").opacity(0.11), Color(hex: "#FFFAF0").opacity(0.035)],
                startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// The line between rows of a list.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Brand.border).frame(height: 1)
    }
}

/// A small status label, as in the dashboard: plain words on a quiet surface. `live` tints it green.
struct Badge: View {
    let text: String
    var live = false

    init(_ text: String, live: Bool = false) {
        self.text = text
        self.live = live
    }

    var body: some View {
        Text(text)
            .font(Brand.sans(11.5, weight: .medium))
            .foregroundStyle(live ? Brand.good : Brand.muted)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(live ? Brand.good.opacity(0.1) : Brand.border))
    }
}

/// The mark: a stem, the joint that makes it a K, and two arms with the upper one hopped clear.
/// Animated, the light hops between the arms, the way work moves between accounts.
struct PixelMark: View {
    var animated = false
    var tint = Brand.text

    /// How lit each arm is, 0...1. The logo keeps both solid.
    static let logo: [Double] = [1, 1]

    /// The light rests on one arm, then hops to the other.
    static func hop(step: Int) -> [Double] {
        let arms: [[Double]] = [[1, 0.26], [1, 0.26], [1, 0.26], [0.26, 1], [0.26, 1], [0.26, 1]]
        return arms[((step % arms.count) + arms.count) % arms.count]
    }

    var body: some View {
        if animated {
            TimelineView(.periodic(from: .now, by: 0.3)) { context in
                grid(Self.hop(step: Int(context.date.timeIntervalSinceReferenceDate / 0.3)))
            }
        } else {
            grid(Self.logo)
        }
    }

    private func grid(_ arms: [Double]) -> some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / 24
            ZStack(alignment: .topLeading) {
                square(x: 2.5, y: 2.5, width: 6, height: 19.5, unit: unit, opacity: 1)
                square(x: 9.6, y: 9.2, width: 6, height: 6, unit: unit, opacity: 1)
                // The hopped arm carries the one blue; animated, the light owns both arms.
                square(x: 16, y: 1, width: 6, height: 6, unit: unit, opacity: arms[0], color: animated ? tint : Brand.blue)
                square(x: 16, y: 17, width: 6, height: 6, unit: unit, opacity: arms[1])
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .animation(.easeOut(duration: 0.2), value: arms)
        }
        .accessibilityHidden(true)
    }

    private func square(x: Double, y: Double, width: Double, height: Double, unit: Double, opacity: Double, color: Color? = nil) -> some View {
        RoundedRectangle(cornerRadius: unit * 1.5, style: .continuous)
            .fill(color ?? tint)
            .opacity(opacity)
            .frame(width: unit * width, height: unit * height)
            .offset(x: unit * x, y: unit * y)
    }
}

/// One of the dashboard's line icons.
struct Icon: View {
    let name: String
    var size: CGFloat = 14

    init(_ name: String, size: CGFloat = 14) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(nsImage: IconImages.image(name))
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum IconImages {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage {
        if let cached = cache[name] { return cached }
        let image = NSImage(data: Data(InterfaceIcons.svg(name).utf8)) ?? NSImage()
        image.isTemplate = true
        cache[name] = image
        return image
    }
}
#endif
