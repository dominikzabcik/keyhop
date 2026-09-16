import SwiftUI

/// The same neutral palette as Keyhop's window and the website. The Mac app's tokens live in an
/// AppKit file, so the phone keeps its own copy of the few colours it needs rather than importing
/// a desktop framework.
enum Brand {
    static let background = Color(red: 0.090, green: 0.090, blue: 0.090)
    static let panel = Color(red: 0.106, green: 0.106, blue: 0.106)
    static let raised = Color(red: 0.135, green: 0.135, blue: 0.135)
    static let border = Color.white.opacity(0.08)
    static let text = Color(white: 0.92)
    static let muted = Color(white: 0.63)
    static let subtle = Color(white: 0.46)
    static let good = Color(red: 0.36, green: 0.79, blue: 0.54)
    /// A limit with nothing left. Warm and held back, the same weight as `good`, never a red alarm.
    static let spent = Color(red: 0.86, green: 0.62, blue: 0.36)
    static let wrong = Color(red: 0.93, green: 0.48, blue: 0.41)

    /// Tier tones, matching the website's: a quiet shift, never a colour badge.
    static func tier(_ key: String) -> Color {
        switch key {
        case "silver": Color(hue: 0, saturation: 0, brightness: 0.68)
        case "gold": Color(hue: 42 / 360, saturation: 0.26, brightness: 0.66)
        case "platinum": Color(hue: 190 / 360, saturation: 0.12, brightness: 0.72)
        case "diamond": Color(hue: 205 / 360, saturation: 0.20, brightness: 0.80)
        case "master": Color(white: 0.95)
        default: Color(hue: 26 / 360, saturation: 0.20, brightness: 0.58)
        }
    }
}

/// Keyhop's mark: the stem, the joint that makes it a K, and two arms with the upper one hopped
/// clear. Drawn on the same 24-unit grid as every other surface.
///
/// `arms` lights each arm as far as one of the two nearest limits is used, exactly as the Mac's
/// menu bar icon does. Left empty the mark is solid, the way the logo is.
struct KeyhopMark: View {
    var size: CGFloat = 28
    var arms: [Double] = []

    var body: some View {
        Canvas { context, _ in
            let unit = size / 24
            func square(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ level: Double = 1) {
                let rect = CGRect(x: x * unit, y: y * unit, width: width * unit, height: height * unit)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5 * unit),
                             with: .color(Brand.text.opacity(0.28 + 0.72 * level)))
            }
            square(2.5, 2.5, 6, 19.5)
            square(9.6, 9.2, 6, 6)
            // The upper arm carries the nearest limit, the lower one the next.
            square(16, 1, 6, 6, arms.isEmpty ? 1 : min(max(arms[0], 0), 1))
            square(16, 17, 6, 6, arms.count > 1 ? min(max(arms[1], 0), 1) : (arms.isEmpty ? 1 : 0))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The climbing squares that stand for a tier, lit as far as it has come.
struct TierMark: View {
    let key: String
    var height: CGFloat = 16

    private var lit: Int {
        ["bronze": 1, "silver": 2, "gold": 3, "platinum": 4, "diamond": 5, "master": 6][key] ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: height * 0.12) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: height * 0.09, style: .continuous)
                    .fill(Brand.tier(key))
                    .opacity(index < lit ? 1 : 0.22)
                    .frame(width: height * 0.19, height: height * (0.25 + CGFloat(index) * 0.15))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// How full one window is: a track with the used part filled, and rounded caps so it reads as a
/// measure rather than a rule. The fill shifts in value rather than colour, except at the very top
/// of a window, where there is genuinely nothing left to use.
struct CapacityTrack: View {
    let usedPercent: Double
    var height: CGFloat = 5

    private var share: Double { min(max(usedPercent / 100, 0), 1) }

    private var fill: Color {
        switch usedPercent {
        case 95...: Brand.spent
        case 75...: Brand.text.opacity(0.82)
        default: Brand.muted.opacity(0.55)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.raised)
                // A sliver of fill still reads as a measure; nothing at all reads as a broken bar.
                Capsule().fill(fill).frame(width: max(share * geometry.size.width, share > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A card, in the house style: a panel a hair lighter than the ground with a self-coloured edge.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.border, lineWidth: 1))
    }
}

enum Format {
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        func trimmed(_ number: Double, _ suffix: String) -> String {
            let text = number >= 100 ? String(format: "%.0f", number) : String(format: "%.1f", number)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + suffix
        }
        switch value {
        case 1e9...: return trimmed(value / 1e9, "B")
        case 1e6...: return trimmed(value / 1e6, "M")
        case 1e3...: return trimmed(value / 1e3, "K")
        default: return "\(count)"
        }
    }

    static let toolNames = ["claude": "Claude Code", "cursor": "Cursor", "codex": "Codex", "gemini": "Gemini CLI"]

    static func tool(_ id: String) -> String { toolNames[id] ?? id.capitalized }

    /// How long until a moment, in the same words the Mac uses: "24m", "3h 10m", "2d".
    static func until(_ date: Date, from now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "now" }
        let days = seconds / 86400, hours = (seconds % 86400) / 3600, minutes = (seconds % 3600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    static func tier(_ tier: CloudSeason.Tier) -> String {
        let roman = ["", "I", "II", "III"]
        guard let division = tier.division, division > 0, division < roman.count else { return tier.name }
        return "\(tier.name) \(roman[division])"
    }
}
