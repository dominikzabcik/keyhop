import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        UserDefaults.standard.register(defaults: ["autoRefresh": true, "checkForUpdates": true, "autoInstallUpdates": true])
        if DebugTools.handle(CommandLine.arguments) { return }
        SwitchrApp.main()
    }
}

struct SwitchrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AccountStore.shared

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(store)
                .environmentObject(UsageTracker.shared)
        } label: {
            Image(nsImage: MenuBarGlyph.image(windows: store.menuBarWindows, sweep: store.glyphSweep))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            Alerts.shared.configure()
            WelcomeWindow.showIfNeeded(AccountStore.shared)
            Updater.shared.checkIfDue()
        }
    }
}
