import AppKit
import ServiceManagement
import SwiftUI

@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?
    private static let seenKey = "welcomeSeen"

    /// Shown on first launch, and whenever Switchr runs from outside Applications.
    static func showIfNeeded(_ store: AccountStore) {
        guard Relocator.canMove || !UserDefaults.standard.bool(forKey: seenKey) else { return }
        show(store)
    }

    /// `markSeen: false` and `canMove: false` let `--preview-welcome` show the finished state
    /// without touching the real first-run flag.
    static func show(_ store: AccountStore, canMove: Bool = Relocator.canMove, markSeen: Bool = true) {
        if window == nil {
            let root = WelcomeView(canMove: canMove) { dismiss(store, markSeen: markSeen) }.environmentObject(store)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
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
            HandoffMark()
                .frame(width: 124, height: 124)
                .padding(.top, 56)

            Text("Switchr")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.bone)
                .padding(.top, 26)
            Text("Your AI accounts, one click apart.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(spacing: 15) {
                ForEach(Provider.allCases) { DetectionRow(provider: $0) }
            }
            .padding(.top, 38)
            .padding(.horizontal, 50)

            Spacer(minLength: 24)

            if !canMove {
                Toggle("Open Switchr at login", isOn: $openAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }

            Button(action: primaryAction) {
                Text(canMove ? "Move to Applications" : "Done")
            }
            .buttonStyle(BoneButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 50)

            Text(problem ?? footnote)
                .font(.system(size: 11))
                .foregroundStyle(problem == nil ? .tertiary : .secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 50)
                .padding(.top, 12)
        }
        .padding(.bottom, 26)
        .frame(width: 420, height: 580)
        .background(Enamel())
        .environment(\.colorScheme, .dark)
    }

    private var footnote: String {
        canMove ? "Switchr copies itself there and reopens." : "Switchr keeps running in the menu bar."
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
            ProviderMark(provider: provider)
                .frame(width: 15, height: 15)
            Text(provider.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brand.bone)
            Spacer(minLength: 16)
            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(saved.isEmpty ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
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

struct BoneButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        BoneButton(configuration: configuration, compact: compact)
    }

    private struct BoneButton: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(Brand.enamelBottom)
                .frame(maxWidth: .infinity, minHeight: compact ? 26 : 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Brand.bone.opacity(configuration.isPressed ? 0.78 : hovering ? 0.9 : 1))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
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
