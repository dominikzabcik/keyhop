#if os(macOS)
import AppKit
import SwiftUI

// MARK: Facts

/// What the notch shows: per tool the active login's limit windows, tightest first, and today's
/// figures. Status only; the hop and everything else live in the window.
struct NotchFacts {
    struct Line {
        let window: String
        let left: Int
        let reset: String
        let tone: NotchTone
    }

    struct Group: Identifiable {
        let provider: Provider
        /// The tightest window leads at full weight; the others follow as quiet sub rows.
        let lines: [Line]
        var id: String { provider.rawValue }
    }

    let groups: [Group]
    let tokens: Int
    let cost: Double
    /// Each tool's share of today's tokens, largest first.
    let shares: [(provider: Provider, fraction: Double)]
    let readAt: Date?

    var tightest: Line? { groups.first?.lines.first }

    /// The open panel's height follows its fixed-height rows, so the window can be sized before
    /// the view lays out.
    var openHeight: CGFloat {
        let rows = groups.reduce(CGFloat(0)) { $0 + 30 + CGFloat($1.lines.count - 1) * 22 }
        let gaps = CGFloat(max(groups.count - 1, 0)) * 20
        return 51 + rows + gaps + 12 + 20 + 16
    }

    @MainActor
    static func make(store: AccountStore, tracker: UsageTracker, now: Date = Date()) -> NotchFacts {
        var groups: [Group] = []
        for provider in Provider.allCases {
            guard let id = store.active[provider], let snapshot = store.usage[id],
                  snapshot.signedOut != true, !snapshot.windows.isEmpty else { continue }
            let lines = snapshot.windows
                .sorted { SmartHop.room($0, now) < SmartHop.room($1, now) }
                .map { window -> Line in
                    let left = Int(SmartHop.room(window, now).rounded())
                    return Line(window: window.label.lowercased(), left: left,
                                reset: window.resetText(at: now), tone: NotchTone(left: left))
                }
            groups.append(Group(provider: provider, lines: lines))
        }
        groups.sort { ($0.lines.first?.left ?? 100) < ($1.lines.first?.left ?? 100) }

        let total = tracker.todayTotal
        let shares = tracker.todayByProvider
            .filter { $0.value.tokens.total > 0 }
            .sorted { $0.value.tokens.total > $1.value.tokens.total }
            .prefix(6)
            .map { (provider: $0.key, fraction: Double($0.value.tokens.total) / Double(max(total.tokens.total, 1))) }
        return NotchFacts(groups: groups, tokens: total.tokens.total, cost: total.cost,
                          shares: Array(shares), readAt: store.lastRefresh)
    }
}

/// The same reading as everywhere: 15% or less is out, 40% or less is getting there.
enum NotchTone {
    case ok, low, out

    init(left: Int) {
        self = left <= 15 ? .out : left <= 40 ? .low : .ok
    }

    var color: Color {
        switch self {
        case .ok: Brand.good
        case .low: Brand.warn
        case .out: Brand.red
        }
    }
}

// MARK: Shape

/// The bezel's silhouette: outward fillets where the black meets the screen's top edge, straight
/// sides, and rounded bottom corners. The fillets make it read as hardware, not a floating card.
struct NotchShape: Shape {
    var fillet: CGFloat = 10
    var bottomRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let f = fillet
        let r = bottomRadius
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.minX, y: rect.minY + f), radius: f,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.minX + f + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX - f - r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.maxX - f - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        path.addArc(center: CGPoint(x: rect.maxX, y: rect.minY + f), radius: f,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: State and window

/// What the panel and the view share: whether the companion is open, and how wide the hardware
/// notch is, so the collapsed flanks clear it.
@MainActor
final class NotchState: ObservableObject {
    @Published var open = false
    @Published var notchWidth: CGFloat = 200
    var onToggle: () -> Void = {}
    var onClose: () -> Void = {}
}

/// A borderless panel hugging the hardware notch: collapsed it widens the bezel into two readout
/// flanks; open it drops a true-black status panel. It never takes focus from the app in front.
@MainActor
final class NotchWindow {
    static let shared = NotchWindow()

    static let flankWidth: CGFloat = 74
    static let fillet: CGFloat = 10

    static var notchScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }
    static var hasNotchScreen: Bool { notchScreen != nil }

    private var panel: NSPanel?
    private let state = NotchState()
    private var outsideMonitor: Any?
    private var screenObserver: Any?

    static func applyFromDefaults() {
        shared.apply(UserDefaults.standard.bool(forKey: "notchCompanion"))
    }

    func apply(_ enabled: Bool) {
        if enabled { show() } else { hide() }
    }

    private func show() {
        guard panel == nil else {
            layout()
            return
        }
        guard Self.notchScreen != nil else { return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        state.onToggle = { [weak self] in
            guard let self else { return }
            setOpen(!state.open)
        }
        state.onClose = { [weak self] in self?.setOpen(false) }
        let root = NotchCompanionView(state: state)
            .environmentObject(AccountStore.shared)
            .environmentObject(UsageTracker.shared)
        panel.contentView = NSHostingView(rootView: root)
        self.panel = panel
        layout()
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
    }

    private func hide() {
        setOpen(false)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func setOpen(_ open: Bool) {
        guard state.open != open else { return }
        state.open = open
        layout(animated: true)
        if open {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                Task { @MainActor in NotchWindow.shared.setOpen(false) }
            }
        } else if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
    }

    private func layout(animated: Bool = false) {
        guard let panel else { return }
        guard let screen = Self.notchScreen else {
            panel.orderOut(nil)
            return
        }
        state.notchWidth = Self.notchWidth(on: screen)
        let collapsedWidth = state.notchWidth + 2 * Self.flankWidth + 2 * Self.fillet
        let size: CGSize
        if state.open {
            let facts = NotchFacts.make(store: AccountStore.shared, tracker: UsageTracker.shared)
            size = CGSize(width: max(420, state.notchWidth + 72), height: facts.openHeight)
        } else {
            size = CGSize(width: collapsedWidth, height: screen.safeAreaInsets.top)
        }
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true, animate: animated && !panel.frame.isEmpty)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private static func notchWidth(on screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return screen.frame.width - left.width - right.width
        }
        return 200
    }
}

// MARK: Views

/// The companion itself: black extends the bezel. Collapsed, the tightest limit sits on the left
/// flank and today's tokens on the right. Open, the limits and today, and the one quiet link.
struct NotchCompanionView: View {
    @ObservedObject var state: NotchState
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker

    var body: some View {
        // Resets and the read time move with the clock, not only with new readings.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(facts: NotchFacts.make(store: store, tracker: tracker, now: context.date), now: context.date)
        }
        .environment(\.colorScheme, .dark)
    }

    private func content(facts: NotchFacts, now: Date) -> some View {
        let shape = NotchShape(fillet: NotchWindow.fillet, bottomRadius: state.open ? 20 : 14)
        return ZStack(alignment: .top) {
            shape.fill(Color.black)
            if state.open {
                NotchPanel(facts: facts, now: now, close: state.onClose)
                    .padding(.horizontal, NotchWindow.fillet)
            } else {
                NotchFlanks(facts: facts, notchWidth: state.notchWidth)
                    .padding(.horizontal, NotchWindow.fillet)
            }
        }
        .contentShape(shape)
        .onTapGesture {
            if state.open { state.onClose() } else { state.onToggle() }
        }
        .accessibilityElement(children: state.open ? .contain : .ignore)
        .accessibilityLabel(summary(facts))
        .accessibilityAddTraits(.isButton)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: state.open)
    }

    private func summary(_ facts: NotchFacts) -> String {
        var parts: [String] = []
        if let tightest = facts.tightest, let first = facts.groups.first {
            parts.append("\(first.provider.shortName) \(tightest.window) window, \(tightest.left)% left, resets in \(tightest.reset)")
        }
        parts.append("\(Numbers.tokens(facts.tokens)) tokens today")
        return "Keyhop: " + parts.joined(separator: ". ")
    }
}

/// Collapsed: two readouts beside the hardware, in the bezel's own black.
private struct NotchFlanks: View {
    let facts: NotchFacts
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                if let tightest = facts.tightest {
                    Circle().fill(tightest.tone.color).frame(width: 6, height: 6)
                    Text("\(tightest.left)%")
                        .font(Brand.mono(12, weight: .medium))
                        .foregroundStyle(tightest.tone == .ok ? Brand.muted : tightest.tone.color)
                }
            }
            .frame(width: NotchWindow.flankWidth - 16, alignment: .leading)
            .padding(.leading, 16)
            Spacer(minLength: notchWidth)
            Text(Numbers.tokens(facts.tokens))
                .font(Brand.mono(12, weight: .medium))
                .foregroundStyle(Brand.muted)
                .frame(width: NotchWindow.flankWidth - 16, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// Open: one group per tool, its windows stacked with the tighter one leading, then a hairline
/// foot with today. A click anywhere but the link closes the panel.
private struct NotchPanel: View {
    let facts: NotchFacts
    let now: Date
    let close: () -> Void

    private static let hairline = Color(hex: "#FFFAF0").opacity(0.06)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(facts.groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Rectangle().fill(Self.hairline).frame(height: 1).padding(.vertical, 10)
                }
                NotchGroupRows(group: group)
            }
            Spacer(minLength: 0)
            foot
        }
        .padding(.top, 51)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .overlay(alignment: .topTrailing) {
            Text(readtime)
                .font(Brand.mono(11, weight: .medium))
                .foregroundStyle(stale ? Brand.warn : Brand.subtle)
                .padding(.top, 13)
                .padding(.trailing, 20)
        }
    }

    private var readtime: String {
        guard let readAt = facts.readAt else { return "" }
        let minutes = Int(now.timeIntervalSince(readAt) / 60)
        if minutes < 1 { return "read now" }
        if minutes < 60 { return "read \(minutes)m ago" }
        return "read \(minutes / 60)h ago"
    }

    private var stale: Bool {
        guard let readAt = facts.readAt else { return false }
        return now.timeIntervalSince(readAt) > 10 * 60
    }

    private var foot: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Self.hairline).frame(height: 1)
            HStack(alignment: .center, spacing: 12) {
                (Text(Numbers.tokens(facts.tokens)).foregroundStyle(Brand.text)
                    + Text(facts.cost > 0 ? " · \(Numbers.usd(facts.cost))" : "").foregroundStyle(Brand.muted))
                    .font(Brand.mono(13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Text("today")
                    .font(Brand.sans(12))
                    .foregroundStyle(Brand.subtle)
                NotchShareBar(shares: facts.shares)
                Spacer(minLength: 8)
                Button(action: {
                    close()
                    AppWindow.show(section: "home")
                }) {
                    HStack(spacing: 7) {
                        PixelMark()
                            .frame(width: 13, height: 13)
                        Text("Open Keyhop")
                            .font(Brand.sans(12))
                            .fixedSize()
                    }
                    .foregroundStyle(Brand.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Keyhop's window")
            }
            .padding(.top, 12)
        }
    }
}

private struct NotchGroupRows: View {
    let group: NotchFacts.Group

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(group.lines.enumerated()), id: \.offset) { index, line in
                row(line, lead: index == 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(group.provider.shortName), \(line.window) window, \(line.left)% left, resets in \(line.reset)")
            }
        }
    }

    private func row(_ line: NotchFacts.Line, lead: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                if lead {
                    Image(nsImage: Marks.image(for: group.provider))
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(line.tone.color)
                    Text(group.provider.shortName)
                        .font(Brand.sans(12.5, weight: .semibold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                }
            }
            .frame(width: 112, alignment: .leading)
            Text(line.window)
                .font(Brand.sans(11))
                .foregroundStyle(Brand.subtle)
                .frame(width: 38, alignment: .trailing)
                .lineLimit(1)
            Capsule()
                .fill(Brand.raisedHover)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(line.tone.color)
                            .frame(width: max(geo.size.width * CGFloat(line.left) / 100, line.left > 0 ? 4 : 0))
                    }
                }
                .clipShape(Capsule())
            Text(line.reset.isEmpty ? "\(line.left)%" : "\(line.left)% · \(line.reset)")
                .font(lead ? Brand.mono(12, weight: line.tone == .out ? .semibold : .medium) : Brand.mono(11))
                .foregroundStyle(lead ? (line.tone == .out ? line.tone.color : Brand.muted) : Brand.subtle)
                .frame(width: 112, alignment: .trailing)
                .lineLimit(1)
        }
        .frame(height: lead ? 30 : 22)
    }
}

/// Today's tokens by tool as thin grey segments, largest first: the same quiet ramp as the
/// window's share bar.
private struct NotchShareBar: View {
    let shares: [(provider: Provider, fraction: Double)]

    private static let greys = ["#cfcbc3", "#a39f97", "#827d74", "#666258", "#4e4a42", "#3a3731"]

    var body: some View {
        if shares.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        Capsule()
                            .fill(Color(hex: Self.greys[min(index, Self.greys.count - 1)]))
                            .frame(width: max((geo.size.width - CGFloat(shares.count - 1) * 2) * share.fraction, 2))
                    }
                }
            }
            .frame(maxWidth: 72)
            .frame(height: 2)
            .accessibilityLabel("Share of today's tokens: " + shares.map {
                "\($0.provider.shortName) \(Int(($0.fraction * 100).rounded()))%"
            }.joined(separator: ", "))
        }
    }
}
#endif
