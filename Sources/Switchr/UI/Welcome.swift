#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI

@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?
    private static let seenKey = "welcomeSeen"

    /// Shown on first launch, and whenever Switchr runs from outside Applications. Returns whether
    /// it showed.
    @discardableResult
    static func showIfNeeded(_ store: AccountStore) -> Bool {
        guard Relocator.canMove || !UserDefaults.standard.bool(forKey: seenKey) else { return false }
        show(store)
        return true
    }

    /// `markSeen: false` and `canMove: false` let `--preview-welcome` show the finished state
    /// without touching the real first-run flag.
    static func show(_ store: AccountStore, canMove: Bool = Relocator.canMove, markSeen: Bool = true) {
        if window == nil {
            let root = WelcomeView(canMove: canMove) { dismiss(store, markSeen: markSeen) }.environmentObject(store)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Brand.backgroundColor
            window.contentView = NSHostingView(rootView: root)
            window.center()
            self.window = window
        }
        // Closing the window counts as seen; only the move prompt comes back.
        if markSeen && !canMove { UserDefaults.standard.set(true, forKey: seenKey) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func dismiss(_ store: AccountStore, markSeen: Bool) {
        if markSeen { UserDefaults.standard.set(true, forKey: seenKey) }
        window?.close()
        window = nil
        store.pointAtMenuBar()
        // A real first run goes on into Switchr's window; the preview just closes.
        if markSeen { AppWindow.show() }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var store: AccountStore
    var canMove = Relocator.canMove
    let dismiss: () -> Void

    @State private var openAtLogin = true
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            PixelMark(animated: true)
                .frame(width: 52, height: 52)
                .padding(.top, 58)

            Text("Switchr")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Brand.text)
                .padding(.top, 24)
            Text("Your AI accounts, one click apart.")
                .font(.system(size: 13.5))
                .foregroundStyle(Brand.muted)
                .padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(Array(Provider.allCases.enumerated()), id: \.offset) { index, provider in
                    if index > 0 { RowDivider() }
                    DetectionRow(provider: provider)
                }
            }
            .card()
            .padding(.top, 32)
            .padding(.horizontal, 32)

            Spacer(minLength: 20)

            if !canMove {
                Toggle("Open Switchr at login", isOn: $openAtLogin)
                    .toggleStyle(CheckboxStyle())
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.muted)
                    .padding(.bottom, 14)
            }

            Button(action: primaryAction) {
                Text(canMove ? "Move to Applications" : "Open Switchr")
            }
            .buttonStyle(AppButtonStyle(kind: .primary, size: .large, fullWidth: true))
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 32)

            Text(problem ?? footnote)
                .font(.system(size: 11.5))
                .foregroundStyle(problem == nil ? Brand.subtle : Brand.bad)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 12)
        }
        .padding(.bottom, 26)
        .frame(width: 420, height: 500)
        .background(Brand.background)
        .environment(\.colorScheme, .dark)
    }

    private var footnote: String {
        canMove ? "Switchr copies itself there and reopens." : "Switchr also stays in the menu bar."
    }

    private func primaryAction() {
        if canMove {
            do {
                try Relocator.moveToApplications()
            } catch {
                problem = "Couldn't move Switchr: \(error.localizedDescription)"
            }
            return
        }
        if openAtLogin { try? SMAppService.mainApp.register() }
        dismiss()
    }
}

private struct DetectionRow: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider

    var body: some View {
        HStack(spacing: 12) {
            ProviderMark(provider: provider, tint: Brand.text)
                .frame(width: 16, height: 16)
            Text(provider.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brand.text)
            Spacer(minLength: 16)
            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(saved.isEmpty ? Brand.subtle : Brand.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var saved: [Account] { store.accounts(for: provider) }

    private var status: String {
        if let id = store.active[provider], let account = saved.first(where: { $0.id == id }) {
            return saved.count > 1 ? "\(account.email) +\(saved.count - 1)" : account.email
        }
        if !saved.isEmpty { return saved.count == 1 ? "1 account saved" : "\(saved.count) accounts saved" }
        return store.lastRefresh == nil ? "Looking…" : "Not signed in"
    }
}

/// Moves Switchr out of a disk image, Downloads, or a translocated copy into Applications.
enum Relocator {
    static var canMove: Bool {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return false }
        return !(path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/"))
    }

    @MainActor
    static func moveToApplications() throws {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: Bundle.main.bundlePath)
        var destination = URL(fileURLWithPath: "/Applications/Switchr.app")
        if !fm.isWritableFile(atPath: "/Applications") {
            let userApps = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
            try fm.createDirectory(at: userApps, withIntermediateDirectories: true)
            destination = userApps.appendingPathComponent("Switchr.app")
        }

        NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.switchr.app")
            .filter { $0 != .current }
            .forEach { $0.terminate() }
        if fm.fileExists(atPath: destination.path) {
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: source, to: destination)
        // This launch was already allowed, so the copy doesn't need the download flag.
        _ = try? Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
#endif
