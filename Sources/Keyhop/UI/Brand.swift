#if os(macOS)
import AppKit
import CoreText
import SwiftUI

/// The dashboard's design tokens, so the menu, the welcome window and Keyhop's window read as one
/// app: Coss Blue's neutral surfaces, white at low opacity for edges and hover, one blue for
/// actions, and colors that otherwise only ever mean a state.
enum Brand {
    static let background = Color(hex: "#161616")
    static let sidebar = Color(hex: "#111111")
    static let panel = Color(hex: "#1A1A1A")
    static let raised = Color(hex: "#1F1F1F")
    static let raisedHover = Color(hex: "#262626")
    static let hover = Color.white.opacity(0.05)
    static let selected = Color.white.opacity(0.1)
    static let border = Color.white.opacity(0.10)
    static let borderStrong = Color.white.opacity(0.16)
    static let faint = Color.white.opacity(0.08)
    static let text = Color(hex: "#F5F5F5")
    static let muted = Color(hex: "#A3A3A3")
    static let subtle = Color(hex: "#8A8A8A")
    static let primary = Color(hex: "#60A5FA")
    static let primaryHover = Color(hex: "#7DB6FB")
    static let onPrimary = Color(hex: "#0A1628")
    static let good = Color(hex: "#34D399")
    static let warn = Color(hex: "#F59E0B")
    /// Red as text; `red` is the same state as a fill or a ring.
    static let bad = Color(hex: "#FF8A82")
    static let red = Color(hex: "#FB414A")
    static let info = Color(hex: "#93C5FD")

    static let backgroundColor = NSColor(srgbRed: 0x16 / 255, green: 0x16 / 255, blue: 0x16 / 255, alpha: 1)

    /// Geist, the window's face. Registered once at launch from the fonts the window's page embeds;
    /// until then, or if that fails, SwiftUI falls back to the system face.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Geist", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Geist Mono", size: size).weight(weight)
    }

    /// Figures: Geist a step heavier with digits of one width, so a number that changes never
    /// shifts what stands beside it.
    static func figure(_ size: CGFloat) -> Font {
        sans(size, weight: .semibold).monospacedDigit()
    }

    /// Names and headings: Geist, a step heavier than the text around it.
    static func heading(_ size: CGFloat) -> Font {
        sans(size, weight: .semibold)
    }

    /// Hands Geist and Geist Mono to Core Text for this process, from the base64 fonts in the
    /// window's stylesheet, so the app carries one copy of each.
    static func registerFonts() {
        var rest = Substring(DashboardPage.fonts)
        while let start = rest.range(of: "base64,") {
            rest = rest[start.upperBound...]
            guard let end = rest.firstIndex(of: ")") else { break }
            if let data = Data(base64Encoded: String(rest[..<end])),
               let provider = CGDataProvider(data: data as CFData),
               let font = CGFont(provider) {
                CTFontManagerRegisterGraphicsFont(font, nil)
            }
            rest = rest[end...]
        }
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
                colors: [Color.white.opacity(0.11), Color.white.opacity(0.035)],
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
                .fill(live ? Brand.good.opacity(0.1) : Color.white.opacity(0.07)))
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
                square(x: 16, y: 1, width: 6, height: 6, unit: unit, opacity: arms[0])
                square(x: 16, y: 17, width: 6, height: 6, unit: unit, opacity: arms[1])
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .animation(.easeOut(duration: 0.2), value: arms)
        }
        .accessibilityHidden(true)
    }

    private func square(x: Double, y: Double, width: Double, height: Double, unit: Double, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: unit * 1.5, style: .continuous)
            .fill(tint)
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
