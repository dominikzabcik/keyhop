import AppKit
import Foundation

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

    private let adapters = Adapters.all
    private let vault = Vault()
    private let metaURL: URL
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var previousActive: UUID?
    private var timer: Timer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Switchr", isDirectory: true)
        metaURL = dir.appendingPathComponent("accounts.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        accounts = (try? decoder.decode([Account].self, from: Data(contentsOf: metaURL))) ?? []
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

    /// Sample data for `--snapshot` renders. Touches no files, Keychain or network.
    init(preview: Void, focus: Provider = .claude) {
        metaURL = URL(fileURLWithPath: "/dev/null")
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

    /// Tools with exactly one saved account. Usage from before Switchr recorded any switch
    /// can only have come from that account.
    var soleAccounts: [Provider: UUID] {
        Dictionary(grouping: accounts, by: \.provider).compactMapValues { $0.count == 1 ? $0[0].id : nil }
    }

    func secret(for id: UUID) async -> Secret? {
        await vault.read(id)
    }

    private func setActive(_ provider: Provider, _ id: UUID?) {
        guard active[provider] != id else { return }
        active[provider] = id
        UsageTracker.shared.noteActive(provider, id)
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
        guard refreshTask == nil, switching == nil else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 90 { return }
        isRefreshing = true
        refreshTask = Task {
            for provider in Provider.allCases where provider != addingFor {
                await syncLive(provider)
            }
            await fetchAllUsage()
            lastRefresh = Date()
            isRefreshing = false
            refreshTask = nil
            // Reading logs can take a while on first run, so it never holds up a switch.
            Task { await UsageTracker.shared.refresh(store: self) }
        }
    }

    /// Reads the tool's current login, keeps the saved copy of it fresh (the tool rotates
    /// tokens on its own), and saves logins Switchr hasn't seen yet.
    @discardableResult
    private func syncLive(_ provider: Provider) async -> Bool {
        let adapter = adapters[provider]!
        let live: LiveLogin?
        do {
            live = try await adapter.readLive()
        } catch {
            notice = "\(provider.name): \(error.localizedDescription)"
            return false
        }
        guard let live else {
            setActive(provider, nil)
            return true
        }

        if let index = accounts.firstIndex(where: { $0.provider == provider && $0.identity == live.identity }) {
            guard await vault.write(live.secret, for: accounts[index].id) else {
                notice = "Couldn't update the saved \(provider.name) login in Keychain."
                return false
            }
            let placeholder = "\(provider.name) account"
            if !live.email.isEmpty, live.emailTrusted || accounts[index].email == placeholder {
                accounts[index].email = live.email
            }
            if let plan = live.plan { accounts[index].plan = plan }
            setActive(provider, accounts[index].id)
        } else {
            let email = live.email.isEmpty ? "\(provider.name) account" : live.email
            let account = Account(id: UUID(), provider: provider, identity: live.identity, email: email,
                                  label: nil, plan: live.plan, addedAt: Date())
            guard await vault.write(live.secret, for: account.id) else {
                notice = "Couldn't save the \(provider.name) login to Keychain."
                return false
            }
            accounts.append(account)
            setActive(provider, account.id)
            notice = "Saved \(email) to \(provider.name)."
        }
        saveMeta()
        return true
    }

    private func fetchAllUsage() async {
        let targets = accounts.map { ($0, active[$0.provider] == $0.id) }
        await withTaskGroup(of: Void.self) { group in
            for (account, isActive) in targets {
                let adapter = adapters[account.provider]!
                let vault = vault
                group.addTask {
                    var snapshot = await self.usage[account.id] ?? UsageSnapshot()
                    var plan: String?
                    if let secret = await vault.read(account.id) {
                        do {
                            let report = try await adapter.fetchUsage(secret, allowRefresh: !isActive) { updated in
                                await vault.write(updated, for: account.id)
                            }
                            snapshot = UsageSnapshot(windows: report.windows, error: nil, fetchedAt: Date())
                            plan = report.plan
                        } catch {
                            snapshot.error = error.localizedDescription
                        }
                    } else {
                        snapshot.error = "Saved login is missing from Keychain."
                    }
                    await self.apply(snapshot, plan: plan, to: account.id)
                }
            }
        }
    }

    private func apply(_ snapshot: UsageSnapshot, plan: String?, to id: UUID) {
        usage[id] = snapshot
        if let plan, let i = accounts.firstIndex(where: { $0.id == id }), accounts[i].plan != plan {
            accounts[i].plan = plan
            saveMeta()
        }
    }

    // MARK: Switching

    func switchTo(_ account: Account) {
        guard switching == nil, addingFor == nil, active[account.provider] != account.id else { return }
        switching = account.id
        Task {
            await refreshTask?.value
            defer { switching = nil }
            let provider = account.provider
            // Save whatever is signed in right now first, so a switch never loses a login.
            guard await syncLive(provider) else { return }
            guard active[provider] != account.id else { return }
            guard let secret = await vault.read(account.id) else {
                notice = "The saved login for \(account.email) is missing from Keychain."
                return
            }
            do {
                try await adapters[provider]!.apply(secret)
                await syncLive(provider)
                setFocus(provider)
                notice = provider.switchNote
            } catch {
                notice = "Couldn't switch: \(error.localizedDescription)"
            }
            switching = nil
            refresh()
        }
    }

    // MARK: Adding

    func beginAdd(_ provider: Provider) {
        guard switching == nil, addingFor == nil else { return }
        addingFor = provider
        notice = nil
        Task {
            await refreshTask?.value
            guard await syncLive(provider) else { addingFor = nil; return }
            previousActive = active[provider]
            if active[provider] != nil {
                do {
                    try await adapters[provider]!.signOutLocally()
                    setActive(provider, nil)
                } catch {
                    notice = "Couldn't sign out of \(provider.name): \(error.localizedDescription)"
                    addingFor = nil
                    return
                }
            }
            waitForLogin(provider)
        }
    }

    func cancelAdd() {
        guard let provider = addingFor else { return }
        pollTask?.cancel()
        addingFor = nil
        if let id = previousActive, let account = accounts.first(where: { $0.id == id }) {
            switchTo(account)
        }
        _ = provider
    }

    private func waitForLogin(_ provider: Provider) {
        pollTask?.cancel()
        pollTask = Task {
            let adapter = adapters[provider]!
            for _ in 0..<300 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, addingFor == provider else { return }
                if let live = try? await adapter.readLive() {
                    let known = accounts.contains { $0.provider == provider && $0.identity == live.identity }
                    await syncLive(provider)
                    if known { notice = "That account was already saved." }
                    setFocus(provider)
                    addingFor = nil
                    refresh()
                    return
                }
            }
            addingFor = nil
        }
    }

    // MARK: Editing

    func rename(_ account: Account, to label: String) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[i].label = trimmed.isEmpty ? nil : trimmed
        saveMeta()
    }

    func remove(_ account: Account) {
        guard active[account.provider] != account.id else { return }
        accounts.removeAll { $0.id == account.id }
        usage[account.id] = nil
        saveMeta()
        Task { await vault.delete(account.id) }
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

    private func saveMeta() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(accounts) else { return }
        try? Files.writeAtomically(data, to: metaURL)
    }
}
