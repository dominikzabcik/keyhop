import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await Probe.run()
                done.signal()
            }
            done.wait()
            return
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--reapply"), flag + 1 < CommandLine.arguments.count,
           let provider = Provider(rawValue: CommandLine.arguments[flag + 1]) {
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await Probe.reapply(provider)
                done.signal()
            }
            done.wait()
            return
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--usage-report"), flag + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[flag + 1]
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await Probe.usageReport(databasePath: path)
                done.signal()
            }
            done.wait()
            return
        }
        if CommandLine.arguments.contains("--preview-insights") {
            // The real Insights window with sample data, for screenshots.
            MainActor.assumeIsolated {
                NSApplication.shared.setActivationPolicy(.accessory)
                let store = AccountStore(preview: ())
                InsightsWindow.show(store: store, tracker: UsageTracker(preview: store), height: 1260)
                NSApplication.shared.run()
            }
            return
        }
        if CommandLine.arguments.contains("--preview-welcome") {
            // The real welcome window with sample data, for screenshots.
            MainActor.assumeIsolated {
                NSApplication.shared.setActivationPolicy(.accessory)
                WelcomeWindow.show(AccountStore(preview: ()), canMove: false, markSeen: false)
                NSApplication.shared.run()
            }
            return
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), flag + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshot.render(prefix: CommandLine.arguments[flag + 1]) }
            return
        }
        SwitchrApp.main()
    }
}

/// `Switchr --snapshot <prefix>` renders the menu with sample data to PNGs, light and dark.
@MainActor
enum Snapshot {
    static func render(prefix: String) {
        let store = AccountStore(preview: ())
        let tracker = UsageTracker(preview: store)
        let schemes: [(String, ColorScheme, Color)] = [
            ("dark", .dark, Color(red: 0.16, green: 0.16, blue: 0.17)),
            ("light", .light, Color(red: 0.94, green: 0.94, blue: 0.94)),
        ]
        for (name, scheme, ground) in schemes {
            let view = VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Image(nsImage: MenuBarGlyph.image(windows: store.menuBarWindows))
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                }
                MenuView().environmentObject(store).environmentObject(tracker)
            }
            .background(ground)
            .environment(\.colorScheme, scheme)
            write(view, to: "\(prefix)-\(name).png")
        }
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
        }
    }
}

/// `Switchr --probe` prints each tool's current login and limits without changing anything.
/// `Switchr --reapply <provider>` switches a tool to the login it already has, which exercises
/// the full switch path without changing accounts.
enum Probe {
    /// `Switchr --usage-report <database>` reads local logs into the given database and prints totals.
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
                let t = digest.total
                print("\(range.title): \(Numbers.tokens(t.tokens.total)) tokens, \(Numbers.usd(t.cost)) at API prices, \(t.requests) requests")
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
}
