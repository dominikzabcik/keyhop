#if os(macOS)
import AppKit
import SwiftUI

/// The dashboard's design tokens, so the menu, the welcome window and Keyhop's window read as one
/// app: near-black neutral surfaces, white at low opacity for edges and hover, and three colors
/// that only ever mean a state.
enum Brand {
    static let background = Color(white: 0.09)
    static let sidebar = Color(white: 0.072)
    static let panel = Color(white: 0.118)
    static let raised = Color(white: 0.135)
    static let raisedHover = Color(white: 0.16)
    static let hover = Color.white.opacity(0.05)
    static let selected = Color.white.opacity(0.1)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.14)
    static let faint = Color.white.opacity(0.08)
    static let text = Color(white: 0.92)
    static let muted = Color(white: 0.63)
    static let subtle = Color(white: 0.46)
    static let primary = Color(white: 0.95)
    static let onPrimary = Color(white: 0.09)
    static let good = Color(hex: "#5CC98A")
    static let warn = Color(hex: "#E3A64F")
    static let bad = Color(hex: "#EE7A69")

    static let backgroundColor = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Basteleur Bold, the window's face for figures, so a number reads the same in the menu as
    /// in Keyhop's window.
    static func figure(_ size: CGFloat) -> Font {
        DisplayFonts.register()
        return .custom("Basteleur-Bold", fixedSize: size)
    }

    /// Basteleur Moonlight, the window's face for headings and names.
    static func heading(_ size: CGFloat) -> Font {
        DisplayFonts.register()
        return .custom("Basteleur-Moonlight", fixedSize: size)
    }
}

/// Registers the embedded Basteleur faces with Core Text once, for this process only, so nothing
/// is installed on the computer.
enum DisplayFonts {
    private static let done: Void = {
        for encoded in [DisplayFont.boldOTF, DisplayFont.moonlightOTF] {
            guard let data = Data(base64Encoded: encoded),
                  let provider = CGDataProvider(data: data as CFData),
                  let font = CGFont(provider) else { continue }
            CTFontManagerRegisterGraphicsFont(font, nil)
        }
    }()

    static func register() { _ = done }
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
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(live ? Color(red: 0.66, green: 0.82, blue: 0.72) : Brand.muted)
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
