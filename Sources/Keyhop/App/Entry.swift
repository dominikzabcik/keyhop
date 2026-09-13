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
        // Linked onto PATH as `keyhop` (by the installer or the Homebrew cask), the binary is the
        // command even with no arguments. The app itself runs as `Keyhop`.
        if URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent == "keyhop" {
            KeyhopCLI.runAndExit(arguments)
        }
        if DebugTools.handle(CommandLine.arguments) { return }
        // The app binary also answers `keyhop` commands, so Terminal users on a Mac get them too.
        if let command = arguments.first, KeyhopCLI.handles(command) {
            KeyhopCLI.runAndExit(arguments)
        }
        KeyhopApp.main()
        #else
        KeyhopCLI.runAndExit(arguments)
        #endif
    }
}

#if os(macOS)
struct KeyhopApp: App {
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
        // Started at login, or relaunched after an automatic update: stay in the menu bar. Opened
        // any other way (Finder, Launchpad, Spotlight, the Dock), open Keyhop's window.
        let quiet = Self.launchedAtLogin || CommandLine.arguments.contains(Updater.relaunchFlag)
        Task { @MainActor in
            Alerts.shared.configure()
            let welcomed = WelcomeWindow.showIfNeeded(AccountStore.shared)
            if !welcomed, !quiet { AppWindow.show() }
            Updater.shared.checkIfDue()
        }
    }

    /// Opening Keyhop again while it runs brings up its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { AppWindow.show() }
        return false
    }

    /// `keyhop://open?section=usage`, which `keyhop dashboard` sends.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == AppWindow.urlScheme {
            MainActor.assumeIsolated { AppWindow.show(section: AppWindow.section(from: url)) }
        }
    }

    private static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
#endif
