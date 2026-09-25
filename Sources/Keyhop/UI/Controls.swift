#if os(macOS)
import SwiftUI

/// The dashboard's buttons: primary is near-white, secondary sits on a raised surface, ghost has no
/// chrome until hovered. A tiny, interruptible press confirms contact unless Reduce Motion is on.
struct AppButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    enum Size { case small, regular, large }

    var kind: Kind = .primary
    var size: Size = .regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, style: self)
    }

    private struct ButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let style: AppButtonStyle
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            let hot = hovering && isEnabled
            configuration.label
                .font(.system(size: style.size == .small ? 12.5 : 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(foreground(hot))
                .padding(.horizontal, style.size == .small ? 10 : 14)
                .frame(maxWidth: style.fullWidth ? .infinity : nil)
                .frame(height: height)
                .background(shape.fill(fill(hot)))
                .overlay(shape.strokeBorder(stroke(hot)))
                .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
                .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.97 : 1)
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
        }

        private var height: CGFloat {
            switch style.size {
            case .small: 28
            case .regular: 32
            case .large: 36
            }
        }

        private func foreground(_ hot: Bool) -> Color {
            switch style.kind {
            case .primary: Brand.onPrimary
            case .secondary: Brand.text
            case .ghost: hot ? Brand.text : Brand.muted
            }
        }

        private func fill(_ hot: Bool) -> Color {
            switch style.kind {
            case .primary: hot ? .white : Brand.primary
            case .secondary: hot ? Brand.raisedHover : Brand.raised
            case .ghost: hot ? Brand.hover : .clear
            }
        }

        private func stroke(_ hot: Bool) -> Color {
            style.kind == .secondary ? (hot ? Brand.borderStrong : Brand.border) : .clear
        }
    }
}

/// The dashboard's checkbox: an outlined square that fills near-white with a check when on.
struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
                ZStack {
                    shape.fill(configuration.isOn ? Brand.primary : .clear)
                    shape.strokeBorder(configuration.isOn ? Brand.primary : Brand.borderStrong)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Brand.onPrimary)
                    }
                }
                .frame(width: 14, height: 14)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// True while a view renders offscreen for `--snapshot`, where native menus can't draw.
private struct StaticSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var staticSnapshot: Bool {
        get { self[StaticSnapshotKey.self] }
        set { self[StaticSnapshotKey.self] = newValue }
    }
}

/// A whole list row as a button: it lights up under the pointer. `quiet` rows (like Add) stay
/// muted until then.
struct RowButtonStyle: ButtonStyle {
    var quiet = false
    var radius: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, quiet: quiet, radius: radius)
    }

    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        let quiet: Bool
        let radius: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let hot = hovering && isEnabled
            configuration.label
                .foregroundStyle(quiet && !hot ? Brand.muted : Brand.text)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(configuration.isPressed ? Brand.selected : hot ? Brand.hover : .clear))
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// A limit as the dashboard draws it: a thin track, the used part in ink, amber when usage runs
/// ahead of an even pace, red past 90%, and a tick where an even pace would be now.
struct LimitBar: View {
    let fraction: Double
    var pace: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let value = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(Self.tint(value, pace: pace))
                    .frame(width: value > 0 ? max(height, width * value) : 0)
                if let pace {
                    Capsule()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1.5, height: height + 5)
                        .offset(x: min(max(width * pace - 0.75, 0), width - 1.5))
                }
            }
            .frame(width: width, height: height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: value)
        }
        .frame(height: 5)
    }

    static func tint(_ value: Double, pace: Double?) -> Color {
        if value >= 0.9 { return Brand.bad }
        if let pace, value > pace + 0.08 { return Brand.warn }
        return Brand.text
    }
}
#endif
