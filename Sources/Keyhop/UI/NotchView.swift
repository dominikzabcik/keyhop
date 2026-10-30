#if os(macOS)
import AppKit
import SwiftUI

// MARK: Facts

/// What the notch shows: per tool the limits of the login it reads, tightest first, and today.
/// Status only; the hop and everything else live in the menu and the window.
struct NotchFacts {
    let groups: [LimitGroup]
    let today: TodayLine.Today?
    let readAt: Date?

    /// The figure on the left flank: the tightest window that has a reading.
    var tightest: LimitGroup.Line? { groups.lazy.compactMap(\.lines.first).first }

    /// The open panel's height follows its fixed-height rows, so the window can be sized before
    /// the view lays out.
    var openHeight: CGFloat {
        let rows = groups.reduce(CGFloat(0)) { $0 + $1.height }
        let gaps = CGFloat(max(groups.count - 1, 0)) * 21
        return 51 + rows + gaps + 12 + 20 + 16
    }

    @MainActor
    static func make(store: AccountStore, tracker: UsageTracker, now: Date = Date()) -> NotchFacts {
        NotchFacts(groups: LimitGroup.make(store: store, now: now), today: TodayLine.Today(tracker: tracker),
                   readAt: store.lastRefresh)
    }
}

// MARK: Shape

/// The bezel's silhouette: outward fillets where the black meets the screen's top edge, straight
/// sides, and rounded bottom corners. The fillets make it read as hardware, not a floating card.
struct NotchShape: Shape {
    var fillet: CGFloat = 10
    var bottomRadius: CGFloat = 14

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

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

/// What the panel and the view share: whether the companion is open, and the hardware notch's
/// size, so the collapsed flanks clear it and sit level with it.
@MainActor
final class NotchState: ObservableObject {
    @Published var open = false
    /// Under the pointer, before it opens: the bezel lifts a little at once, so it answers the
    /// pointer instead of waiting out the open delay.
    @Published var lifted = false
    @Published var notchWidth: CGFloat = 200
    @Published var barHeight: CGFloat = 37
    var onToggle: () -> Void = {}
    var onClose: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onResize: () -> Void = {}

    var collapsedWidth: CGFloat { notchWidth + 2 * NotchWindow.flankWidth + 2 * NotchWindow.fillet }
    var openWidth: CGFloat { max(440, notchWidth + 72) }
}

/// A borderless panel hugging the hardware notch: collapsed it widens the bezel into two readout
/// flanks; under the pointer, or on a click, it drops a true-black status panel. It never takes
/// focus from the app in front.
@MainActor
final class NotchWindow {
    static let shared = NotchWindow()

    static let flankWidth: CGFloat = 74
    static let fillet: CGFloat = 10
    /// Long enough that crossing the flanks on the way to the menu bar doesn't open it; the lift
    /// answers the pointer meanwhile.
    static let openDelay: Duration = .milliseconds(140)
    static let closeDelay: Duration = .milliseconds(160)
    static let shadowRoom: CGFloat = 24

    static var notchScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }
    static var hasNotchScreen: Bool { notchScreen != nil }

    private var panel: NSPanel?
    private let state = NotchState()
    private var outsideMonitor: Any?
    private var screenObserver: Any?
    private var hoverTask: Task<Void, Never>?
    /// A click that closed it keeps it closed until the pointer leaves and comes back.
    private var hoverArmed = true

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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // A click opens the full menu under the notch: the readout is the hover's.
        state.onToggle = { [weak self] in
            guard let self, let screen = Self.notchScreen else { return }
            hoverTask?.cancel()
            hoverArmed = false
            setOpen(false)
            let notch = NSRect(x: screen.frame.midX - state.collapsedWidth / 2, y: screen.frame.maxY - state.barHeight,
                               width: state.collapsedWidth, height: state.barHeight)
            MenuPanel.shared.toggle(under: notch, top: screen.frame.maxY, inset: state.barHeight, on: screen)
        }
        state.onClose = { [weak self] in
            self?.hoverArmed = false
            self?.setOpen(false)
        }
        state.onHover = { [weak self] inside in self?.hover(inside) }
        state.onResize = { [weak self] in self?.layout() }
        let root = NotchCompanionView(state: state)
            .environmentObject(AccountStore.shared)
            .environmentObject(UsageTracker.shared)
        // Hosted inside a plain view, so SwiftUI never sizes the panel while the shape springs;
        // as the content view it would, and AppKit gives up after too many constraint passes.
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        let container = NSView()
        container.addSubview(host)
        panel.contentView = container
        host.frame = container.bounds
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
        hoverTask?.cancel()
        setOpen(false)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func hover(_ inside: Bool) {
        hoverTask?.cancel()
        if !inside { hoverArmed = true }
        // The menu dropped from the notch covers the readout's place.
        guard !MenuPanel.shared.isOpen || !inside else { return }
        let lift = inside && hoverArmed && !state.open
        if state.lifted != lift, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { state.lifted = lift }
        } else {
            state.lifted = lift
        }
        guard inside ? hoverArmed && !state.open : state.open else { return }
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: inside ? Self.openDelay : Self.closeDelay)
            guard let self, !Task.isCancelled else { return }
            if inside {
                // A drag passing over the bezel is headed somewhere else.
                guard NSEvent.pressedMouseButtons == 0 else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            setOpen(inside)
        }
    }

    private func setOpen(_ open: Bool) {
        guard state.open != open else { return }
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if open {
            withAnimation(still ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.84)) {
                state.open = true
                state.lifted = false
            }
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                Task { @MainActor in
                    NotchWindow.shared.hoverArmed = false
                    NotchWindow.shared.setOpen(false)
                }
            }
        } else {
            withAnimation(still ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 1)) {
                state.open = false
            }
            if let outsideMonitor {
                NSEvent.removeMonitor(outsideMonitor)
                self.outsideMonitor = nil
            }
        }
    }

    /// The panel always has the open size plus room for the shadow, and only the shape moves inside
    /// it: resizing a window mid-animation shows a frame before SwiftUI redraws, which blinks. Its
    /// clear pixels let clicks through to the menu bar beside the notch.
    private func layout() {
        guard let panel else { return }
        guard let screen = Self.notchScreen else {
            panel.orderOut(nil)
            return
        }
        state.notchWidth = Self.notchWidth(on: screen)
        state.barHeight = screen.safeAreaInsets.top
        let facts = NotchFacts.make(store: AccountStore.shared, tracker: UsageTracker.shared)
        let size = CGSize(width: max(state.openWidth, state.collapsedWidth) + 2 * Self.shadowRoom,
                          height: max(facts.openHeight, state.barHeight) + Self.shadowRoom)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
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
        let open = state.open
        let shape = NotchShape(fillet: NotchWindow.fillet, bottomRadius: open ? 20 : 14)
        return ZStack(alignment: .top) {
            if open {
                NotchPanel(facts: facts, now: now, close: state.onClose)
                    .padding(.horizontal, NotchWindow.fillet)
                    .frame(width: state.openWidth, height: facts.openHeight, alignment: .top)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                            .animation(.easeOut(duration: 0.2)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                            .animation(.easeIn(duration: 0.1))))
            } else {
                NotchFlanks(facts: facts, notchWidth: state.notchWidth)
                    .padding(.horizontal, NotchWindow.fillet)
                    .frame(width: state.collapsedWidth, height: state.barHeight)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.1)),
                                            removal: .opacity.animation(.easeOut(duration: 0.1))))
            }
        }
        .frame(width: open ? state.openWidth : state.collapsedWidth + (state.lifted ? 12 : 0),
               height: open ? facts.openHeight : state.barHeight + (state.lifted ? 5 : 0), alignment: .top)
        .clipShape(shape)
        .background(shape.fill(Color.black).shadow(color: .black.opacity(open ? 0.45 : 0), radius: 14, y: 6))
        .contentShape(shape)
        .onHover { state.onHover($0) }
        .onTapGesture {
            state.onToggle()
        }
        .onChange(of: facts.openHeight) { _, _ in state.onResize() }
        .accessibilityElement(children: open ? .contain : .ignore)
        .accessibilityLabel(summary(facts))
        .accessibilityAddTraits(.isButton)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func summary(_ facts: NotchFacts) -> String {
        var parts: [String] = []
        if let group = facts.groups.first(where: { !$0.lines.isEmpty }), let line = group.lines.first {
            parts.append("\(group.provider.shortName) \(line.window) window, \(line.left)% left"
                + (line.reset.isEmpty ? "" : ", resets in \(line.reset)"))
        }
        if let today = facts.today { parts.append("\(Numbers.tokens(today.tokens)) tokens today") }
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
            Text(facts.today.map { Numbers.tokens($0.tokens) } ?? "…")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(facts.groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    RowDivider().padding(.vertical, 10)
                }
                LimitRows(group: group)
            }
            Spacer(minLength: 0)
            RowDivider()
            ReadoutFoot(today: facts.today, close: close)
                .padding(.top, 12)
        }
        .padding(.top, 51)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .overlay(alignment: .topTrailing) {
            ReadTime(readAt: facts.readAt, now: now)
                .padding(.top, 13)
                .padding(.trailing, 20)
        }
    }
}
#endif
