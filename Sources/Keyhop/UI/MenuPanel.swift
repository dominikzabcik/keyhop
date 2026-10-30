#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Keyhop's status item and the panel it drops: the notch's black bezel hanging from the menu bar,
/// with the menu inside. A MenuBarExtra window brings the system's own chrome (its material, edge
/// and sizing), which can't match the notch, so the panel is drawn here like the notch's.
@MainActor
final class MenuPanel: NSObject {
    static let shared = MenuPanel()

    static let width: CGFloat = MenuView.width + 2 * NotchWindow.fillet
    static let shadowRoom: CGFloat = 24

    private var item: NSStatusItem?
    private var panel: KeyPanel?
    private let state = MenuPanelState()
    private var glyphWatch: AnyCancellable?
    private var monitors: [Any] = []
    private var closedAt = Date.distantPast

    func install(store: AccountStore) {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarGlyph.image(windows: store.menuBarWindows, sweep: store.glyphSweep)
        item.button?.target = self
        item.button?.action = #selector(iconClicked)
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        item.button?.setAccessibilityLabel("Keyhop")
        self.item = item
        // objectWillChange fires before the change lands, so the glyph is drawn a turn later.
        glyphWatch = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak store] _ in
                guard let store else { return }
                self?.item?.button?.image = MenuBarGlyph.image(windows: store.menuBarWindows, sweep: store.glyphSweep)
            }
    }

    var isOpen: Bool { state.open }

    @objc private func iconClicked() {
        guard let button = item?.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        toggle(under: buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)),
               top: buttonWindow.frame.minY, inset: 0, on: screen)
    }

    /// The notch's flank covers the icon when it sits next to the notch, so a click on the notch
    /// opens the same panel as the notch itself, from the screen's top edge, its content clear of
    /// the hardware by `inset`.
    func toggle(under anchor: NSRect, top: CGFloat, inset: CGFloat, on screen: NSScreen) {
        if state.open {
            close()
        } else if Date().timeIntervalSince(closedAt) > 0.25 {
            // The click that made the panel give up focus already closed it; it shouldn't reopen.
            state.inset = inset
            open(under: anchor, top: top, on: screen)
        }
    }

    private func open(under anchor: NSRect, top: CGFloat, on screen: NSScreen) {
        let panel = self.panel ?? makePanel()
        let shapeX = min(max(anchor.midX - Self.width / 2, screen.frame.minX + 6), screen.frame.maxX - 6 - Self.width)
        let height = top - screen.visibleFrame.minY
        panel.setFrame(NSRect(x: shapeX - Self.shadowRoom, y: top - height,
                              width: Self.width + 2 * Self.shadowRoom, height: height), display: false)
        panel.makeKeyAndOrderFront(nil)
        item?.button?.highlight(true)
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(still ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.84)) {
            state.open = true
        }
        monitors = [
            // The click on the icon reaches this monitor too while Keyhop is in the background;
            // the icon's own action answers that one.
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                guard !anchor.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) else { return }
                Task { @MainActor in MenuPanel.shared.close() }
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                Task { @MainActor in MenuPanel.shared.close() }
                return nil
            },
        ].compactMap { $0 }
    }

    func close() {
        guard state.open else { return }
        closedAt = Date()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        item?.button?.highlight(false)
        withAnimation(.easeIn(duration: 0.1)) { state.open = false }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !state.open else { return }
            panel?.orderOut(nil)
        }
    }

    /// As tall as the screen below the menu bar and only as wide as the bezel: its clear pixels let
    /// clicks through, so its size never has to follow the menu's.
    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.onResign = { [weak self] in self?.close() }
        let host = NSHostingView(rootView: MenuPanelView(state: state)
            .environmentObject(AccountStore.shared)
            .environmentObject(UsageTracker.shared))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        let container = NSView()
        container.addSubview(host)
        panel.contentView = container
        host.frame = container.bounds
        self.panel = panel
        return panel
    }
}

@MainActor
final class MenuPanelState: ObservableObject {
    @Published var open = false
    @Published var inset: CGFloat = 0
}

/// Takes the keyboard without bringing Keyhop forward, so Escape, ⌘R and renaming work.
final class KeyPanel: NSPanel {
    var onResign: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResign()
    }
}

private struct MenuPanelView: View {
    @ObservedObject var state: MenuPanelState

    var body: some View {
        VStack(spacing: 0) {
            if state.open {
                MenuBezel { MenuView().padding(.top, state.inset) }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
            }
        }
        .padding(.horizontal, MenuPanel.shadowRoom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The notch's silhouette around the menu: fillets where it meets the menu bar, the open notch's
/// bottom corners, the same black and the same shadow.
struct MenuBezel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = NotchShape(fillet: NotchWindow.fillet, bottomRadius: 20)
        content
            .padding(.horizontal, NotchWindow.fillet)
            .clipShape(shape)
            .background(shape.fill(Color.black).shadow(color: .black.opacity(0.45), radius: 14, y: 6))
    }
}
#endif
