import AppKit
import ServiceManagement
import SwiftUI

/// Command-line tools for development and support. Normal launches never reach them.
///
///     --probe                     print each tool's current login and limits, change nothing
///     --reapply <tool>            switch a tool to the login it already has
///     --usage-report <database>   read local logs into a database and print totals
///     --reset                     remove saved logins, Switchr's data folder and preferences
///     --update-now                install the latest release over this copy, without relaunching
///     --preview-menu [tool]       show the menu with sample data in a window
///     --preview-insights          show Insights with sample data
///     --preview-welcome           show the welcome window with sample data
///     --snapshot <prefix>         render the menu and welcome window with sample data to PNGs
enum DebugTools {
    static func handle(_ arguments: [String]) -> Bool {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        func blocking(_ work: @escaping @Sendable () async -> Void) {
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await work()
                done.signal()
            }
            done.wait()
        }

        if arguments.contains("--probe") {
            blocking { await Probe.run() }
            return true
        }
        if let raw = value(after: "--reapply"), let provider = Provider(rawValue: raw) {
            blocking { await Probe.reapply(provider) }
            return true
        }
        if let path = value(after: "--usage-report") {
            blocking { await Probe.usageReport(databasePath: path) }
            return true
        }
        if arguments.contains("--reset") {
            Reset.run()
            return true
        }
        if arguments.contains("--update-now") {
            MainActor.assumeIsolated {
                Task { @MainActor in
                    await Updater.shared.check(userInitiated: false)
                    guard let release = Updater.shared.available else {
                        print("Switchr \(Updater.currentVersion) is already the latest release.")
                        exit(0)
                    }
                    print("Installing Switchr \(release.version) over \(Updater.currentVersion)…")
                    let installed = await Updater.shared.install(relaunch: false)
                    if case .failed(let message) = Updater.shared.phase { print("Update failed: \(message)") }
                    exit(installed ? 0 : 1)
                }
            }
            RunLoop.main.run()
            return true
        }
        if arguments.contains("--preview-menu") {
            let tab = value(after: "--preview-menu").flatMap(Provider.init(rawValue:)) ?? .claude
            MainActor.assumeIsolated { Previews.menu(tab: tab) }
            return true
        }
        if arguments.contains("--preview-insights") {
            MainActor.assumeIsolated {
                let store = AccountStore(preview: ())
                Previews.run { InsightsWindow.show(store: store, tracker: UsageTracker(preview: store), height: 1260) }
            }
            return true
        }
        if arguments.contains("--preview-welcome") {
            MainActor.assumeIsolated {
                Previews.run { WelcomeWindow.show(AccountStore(preview: ()), canMove: false, markSeen: false) }
            }
            return true
        }
        if let prefix = value(after: "--snapshot") {
            MainActor.assumeIsolated { Snapshot.render(prefix: prefix) }
            return true
        }
        return false
    }
}

/// Real windows with sample data, placed on the sharpest screen so captures come out at full resolution.
@MainActor
enum Previews {
    static func run(_ show: () -> Void) {
        NSApplication.shared.setActivationPolicy(.accessory)
        show()
        for window in NSApp.windows where window.isVisible { placeOnSharpestScreen(window) }
        NSApp.activate(ignoringOtherApps: true)
        NSApplication.shared.run()
    }

    static func menu(tab: Provider) {
        let store = AccountStore(preview: (), focus: tab)
        let root = MenuView()
            .environmentObject(store)
            .environmentObject(UsageTracker(preview: store))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView = host
        run { window.makeKeyAndOrderFront(nil) }
    }

    private static func placeOnSharpestScreen(_ window: NSWindow) {
        guard let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) else { return }
        let frame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
    }
}

/// Renders the menu and welcome window with sample data to PNGs, for CI smoke tests.
@MainActor
enum Snapshot {
    static func render(prefix: String) {
        let store = AccountStore(preview: ())
        let tracker = UsageTracker(preview: store)
        write(MenuView().environmentObject(store).environmentObject(tracker), to: "\(prefix)-menu.png")
        write(WelcomeView(canMove: false, dismiss: {}).environmentObject(store), to: "\(prefix)-welcome.png")
    }

    private static func write(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return }
        let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        try? png?.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
    }
}

/// Removes everything Switchr stores. The tools' own current logins stay as they are.
enum Reset {
    static func run() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Switchr", isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let accounts = (try? decoder.decode([Account].self, from: Data(contentsOf: folder.appendingPathComponent("accounts.json")))) ?? []
        for account in accounts {
            Keychain.delete(service: Vault.service, account: account.id.uuidString)
        }
        try? FileManager.default.removeItem(at: folder)
        if Bundle.main.bundlePath.hasSuffix(".app") {
            try? SMAppService.mainApp.unregister()
        }
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        print("Removed \(accounts.count) saved logins, Switchr's data folder and its preferences.")
    }
}

enum Probe {
    static func run() async {
        for provider in Provider.allCases {
            let adapter = Adapters.all[provider]!
            do {
                guard let live = try await adapter.readLive() else {
                    print("\(provider.name): signed out")
                    continue
                }
                print("\(provider.name): \(live.email)  plan=\(live.plan ?? "-")")
                let report = try await adapter.fetchUsage(live.secret, allowRefresh: false) { _ in }
                for w in report.windows {
                    print("  \(w.label.padding(toLength: 6, withPad: " ", startingAt: 0)) \(Int(w.usedPercent.rounded()))%  resets in \(w.resetText(at: Date()))  pace \(w.pace(at: Date()).map { "\(Int($0 * 100))%" } ?? "-")")
                }
                if let plan = report.plan { print("  plan from usage: \(plan)") }
            } catch {
                print("\(provider.name): \(error.localizedDescription)")
            }
        }
    }

    static func reapply(_ provider: Provider) async {
        let adapter = Adapters.all[provider]!
        let cursorPIDs = { NSRunningApplication.runningApplications(withBundleIdentifier: "com.todesktop.230313mzl4w4u92").map(\.processIdentifier) }
        do {
            guard let before = try await adapter.readLive() else { return print("\(provider.name): signed out") }
            let pidsBefore = cursorPIDs()
            let started = Date()
            try await adapter.apply(before.secret)
            let elapsed = Date().timeIntervalSince(started)
            let after = try await adapter.readLive()
            print("\(provider.name): reapplied in \(String(format: "%.2f", elapsed))s, same login after: \(after?.identity == before.identity)")
            if provider == .cursor {
                print("  Cursor pids before \(pidsBefore) after \(cursorPIDs()) restarted: \(pidsBefore != cursorPIDs())")
            }
        } catch {
            print("\(provider.name): \(error.localizedDescription)")
        }
    }

    static func usageReport(databasePath: String) async {
        do {
            let engine = try TrackerEngine(url: URL(fileURLWithPath: databasePath))
            let started = Date()
            let added = try await engine.ingestLocalLogs()
            print("Read \(added) new records in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            let now = Date()
            for range in [InsightsRange.today, .week, .thirtyDays] {
                let interval = range.interval(now: now)
                let previous = DateInterval(start: interval.start.addingTimeInterval(-interval.duration), duration: interval.duration)
                let digest = try await engine.digest(interval: interval, previous: previous, bucket: range.bucket, provider: nil, sole: [:])
                let total = digest.total
                print("\(range.title): \(Numbers.tokens(total.tokens.total)) tokens, \(Numbers.usd(total.cost)) at API prices, \(total.requests) requests")
                var byProvider: [Provider: Totals] = [:]
                for (key, totals) in digest.byAccount { byProvider[key.provider, default: Totals()] += totals }
                for (provider, totals) in byProvider.sorted(by: { $0.value.cost > $1.value.cost }) {
                    let k = totals.tokens
                    print("  \(provider.name): \(Numbers.tokens(k.total)) (in \(Numbers.tokens(k.input)), cache write \(Numbers.tokens(k.cacheWrite + k.cacheWrite1h)), cache read \(Numbers.tokens(k.cacheRead)), out \(Numbers.tokens(k.output))), \(Numbers.usd(totals.cost))")
                }
                for (model, totals) in digest.byModel.sorted(by: { $0.value.cost > $1.value.cost }).prefix(4) {
                    print("    \(model): \(Numbers.tokens(totals.tokens.total)), \(Numbers.usd(totals.cost))")
                }
            }
        } catch {
            print("Usage report failed: \(error.localizedDescription)")
        }
    }
}
