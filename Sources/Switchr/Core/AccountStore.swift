#if os(macOS)
import AppKit
import Foundation

/// The menu's view of accounts: mirrors `AccountService` for SwiftUI and adds what only the app
/// needs (notices, the add flow's waiting state, the menu bar animation).
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var active: [Provider: UUID] = [:]
    @Published private(set) var usage: [UUID: UsageSnapshot] = [:]
    @Published private(set) var switching: UUID?
    @Published private(set) var addingFor: Provider?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published var notice: String?
    @Published private(set) var focusProvider: Provider?
    /// 0...1 while the menu bar icon animates to show where Switchr lives.
    @Published private(set) var glyphSweep: Double?

    static let shared = AccountStore()

    private let service: AccountService?
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var previousActive: UUID?
    private var timer: Timer?

    init() {
        service = AccountService(onActiveChange: { provider, id in
            Task { @MainActor in UsageTracker.shared.noteActive(provider, id) }
        })
        accounts = AccountService.loadAccounts(from: Platform.dataDirectory)
        focusProvider = UserDefaults.standard.string(forKey: "focusProvider").flatMap(Provider.init)

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                Updater.shared.checkIfDue()
                // With automatic checks off, usage is only read when the menu opens or on Refresh.
                guard UserDefaults.standard.bool(forKey: "autoRefresh") else { return }
                self?.refresh()
            }
        }
        // The menu is the only window, so becoming key means it just opened.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: false) }
        }
        refresh()
    }

    /// Sample data for previews. Touches no files, Keychain or network.
    init(preview: Void, focus: Provider = .claude) {
        service = nil
        let now = Date()
        func account(_ provider: Provider, _ email: String, _ label: String?, _ plan: String) -> Account {
            Account(id: UUID(), provider: provider, identity: email, email: email, label: label, plan: plan, addedAt: now)
        }
        func window(_ label: String, _ used: Double, _ resetIn: TimeInterval, _ length: TimeInterval) -> UsageWindow {
            UsageWindow(label: label, usedPercent: used, resetsAt: now.addingTimeInterval(resetIn), windowSeconds: length)
        }
        let claudeMain = account(.claude, "me@personal.dev", "Personal", "Max 5x")
        let claudeWork = account(.claude, "work@studio.dev", nil, "Pro")
        let cursorMain = account(.cursor, "me@personal.dev", nil, "Ultra")
        let cursorSpare = account(.cursor, "spare@personal.dev", nil, "Pro")
        let codexMain = account(.codex, "me@personal.dev", nil, "Plus")
        accounts = [claudeMain, claudeWork, cursorMain, cursorSpare, codexMain]
        active = [.claude: claudeMain.id, .cursor: cursorMain.id, .codex: codexMain.id]
        usage = [
            claudeMain.id: UsageSnapshot(windows: [window("5h", 51, 11_160, 18000), window("Week", 6, 590_000, 604_800)], fetchedAt: now),
            claudeWork.id: UsageSnapshot(windows: [window("5h", 92, 2_400, 18000), window("Week", 41, 300_000, 604_800)], fetchedAt: now),
            cursorMain.id: UsageSnapshot(windows: [window("Auto", 62, 1_140_000, 2_592_000), window("API", 39, 1_140_000, 2_592_000)], fetchedAt: now),
            cursorSpare.id: UsageSnapshot(error: "Login expired. Switch to it and sign in to Cursor again."),
            codexMain.id: UsageSnapshot(windows: [window("5h", 100, 16_440, 18000), window("Week", 62, 421_000, 604_800)], fetchedAt: now),
        ]
        lastRefresh = now.addingTimeInterval(-120)
        focusProvider = focus
    }

    func accounts(for provider: Provider) -> [Account] {
        accounts.filter { $0.provider == provider }
    }

    var soleAccounts: [Provider: UUID] {
        Dictionary(grouping: accounts, by: \.provider).compactMapValues { $0.count == 1 ? $0[0].id : nil }
    }

    func secret(for id: UUID) async -> Secret? {
        await service?.secret(for: id)
    }

    /// Usage of the account most recently switched to, for the menu bar glyph.
    var menuBarWindows: [UsageWindow] {
        let order = [focusProvider].compactMap { $0 } + Provider.allCases
        for provider in order {
            if let id = active[provider], let windows = usage[id]?.windows, !windows.isEmpty {
                return Array(windows.prefix(2))
            }
        }
        return []
    }

    // MARK: Refresh

    func refresh(force: Bool = true) {
        guard let service, refreshTask == nil, switching == nil else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 90 { return }
        isRefreshing = true
        refreshTask = Task {
            for provider in Provider.allCases where provider != addingFor {
                await report(await service.syncLive(provider), for: provider)
            }
            usage = await service.fetchUsage(previous: usage)
            await mirror()
            lastRefresh = Date()
            isRefreshing = false
            refreshTask = nil
            // Reading logs can take a while on first run, so it never holds up a switch.
            Task { await UsageTracker.shared.refresh(store: self) }
        }
    }

    private func mirror() async {
        guard let service else { return }
        accounts = await service.accounts
        active = await service.active
    }

    private func report(_ outcome: AccountService.SyncOutcome, for provider: Provider) async {
        switch outcome {
        case .failed(let message):
            notice = message
        case .saved(let id):
            if let account = await service?.account(id) { notice = "Saved \(account.email) to \(provider.name)." }
        case .current, .signedOut:
            break
        }
    }

    // MARK: Switching

    func switchTo(_ account: Account) {
        guard let service, switching == nil, addingFor == nil, active[account.provider] != account.id else { return }
        switching = account.id
        Task {
            await refreshTask?.value
            do {
                try await service.switchTo(account.id)
                setFocus(account.provider)
                notice = account.provider.switchNote
            } catch {
                notice = "Couldn't switch: \(error.localizedDescription)"
            }
            await mirror()
            switching = nil
            refresh()
        }
    }

    // MARK: Adding

    func beginAdd(_ provider: Provider) {
        guard let service, switching == nil, addingFor == nil else { return }
        addingFor = provider
        notice = nil
        Task {
            await refreshTask?.value
            do {
                previousActive = try await service.signOutForAdding(provider)
            } catch {
                notice = "Couldn't sign out of \(provider.name): \(error.localizedDescription)"
                addingFor = nil
                await mirror()
                return
            }
            await mirror()
            waitForLogin(provider)
        }
    }

    func cancelAdd() {
        guard addingFor != nil else { return }
        pollTask?.cancel()
        addingFor = nil
        if let id = previousActive, let account = accounts.first(where: { $0.id == id }) {
            switchTo(account)
        }
    }

    private func waitForLogin(_ provider: Provider) {
        guard let service else { return }
        pollTask?.cancel()
        pollTask = Task {
            let result = await service.waitForLogin(provider)
            guard !Task.isCancelled, addingFor == provider else { return }
            addingFor = nil
            guard let result else { return }
            await mirror()
            if result.alreadySaved {
                notice = "That account was already saved."
            } else if case .saved(let id) = result.outcome, let account = accounts.first(where: { $0.id == id }) {
                notice = "Saved \(account.email) to \(provider.name)."
            } else if case .failed(let message) = result.outcome {
                notice = message
            }
            setFocus(provider)
            refresh()
        }
    }

    // MARK: Editing

    func rename(_ account: Account, to label: String) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            accounts[index].label = trimmed.isEmpty ? nil : trimmed
        }
        Task {
            await service?.rename(account.id, to: label)
            await mirror()
        }
    }

    func remove(_ account: Account) {
        guard let service, active[account.provider] != account.id else { return }
        accounts.removeAll { $0.id == account.id }
        usage[account.id] = nil
        Task {
            try? await service.remove(account.id)
            await mirror()
        }
    }

    /// Plays the hand-off animation on the menu bar icon for a few seconds.
    func pointAtMenuBar() {
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            Task { @MainActor in
                let t = Date().timeIntervalSince(start) / 3
                if t >= 1 {
                    timer.invalidate()
                    self?.glyphSweep = nil
                } else {
                    self?.glyphSweep = t
                }
            }
        }
    }

    private func setFocus(_ provider: Provider) {
        focusProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "focusProvider")
    }
}
#endif
