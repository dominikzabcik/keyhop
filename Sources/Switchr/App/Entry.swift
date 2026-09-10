import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#endif

@main
enum Entry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        #if os(macOS)
        UserDefaults.standard.register(defaults: ["autoRefresh": true, "checkForUpdates": true, "autoInstallUpdates": true])
        if DebugTools.handle(CommandLine.arguments) { return }
        // The app binary also answers `switchr` commands, so Terminal users on a Mac get them too.
        if let command = arguments.first, SwitchrCLI.handles(command) {
            SwitchrCLI.runAndExit(arguments)
        }
        SwitchrApp.main()
        #else
        SwitchrCLI.runAndExit(arguments)
        #endif
    }
}

#if os(macOS)
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
#endif
