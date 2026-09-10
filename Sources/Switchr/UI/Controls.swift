#if os(macOS)
import SwiftUI

/// Secondary text action: no chrome, brightens on hover.
struct QuietButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(QuietStyle())
            .font(.system(size: 11.5, weight: .medium))
    }
}

struct QuietStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietLabel(configuration: configuration)
    }

    private struct QuietLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering && isEnabled ? AnyShapeStyle(Brand.bone) : AnyShapeStyle(.secondary))
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// A limit as the icon draws it: a recessed groove with a bone fill, a tick at the even-pace point,
/// amber when usage runs ahead of pace, rust past 90%.
struct LimitTrack: View {
    let fraction: Double
    let pace: Double?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let value = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.36))
                if value > 0 {
                    Capsule()
                        .fill(Self.tint(value, pace: pace))
                        .frame(width: max(height, width * value))
                }
                if let pace {
                    // Dark where it crosses the fill, light over the empty groove, so it always reads.
                    Capsule()
                        .fill(pace <= value ? Color.black.opacity(0.6) : Brand.bone.opacity(0.75))
                        .frame(width: 2, height: height + 6)
                        .offset(x: min(max(width * pace - 1, 0), width - 2))
                }
            }
            .frame(width: width, height: height)
            .animation(.smooth(duration: 0.6), value: value)
        }
    }

    static func tint(_ value: Double, pace: Double?) -> Color {
        if value >= 0.9 { return Brand.rust }
        if let pace, value > pace + 0.08 { return Brand.amber }
        return Brand.bone
    }
}

/// The menu bar glyph at small size: two limits stacked.
struct TwinTracks: View {
    let values: [Double?]

    var body: some View {
        GeometryReader { geo in
            let rowHeight = (geo.size.height - 3) / 2
            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.38))
                        if row < values.count, let value = values[row], value > 0 {
                            Capsule()
                                .fill(value >= 0.9 ? Brand.rust : Brand.bone)
                                .frame(width: max(rowHeight, geo.size.width * min(value, 1)))
                        }
                    }
                    .frame(height: rowHeight)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
