import Foundation

/// Saved accounts and everything done with them: noticing logins, switching, adding and
/// fetching limits. The macOS app and the `keyhop` command both drive this, so the rules
/// (above all: save the login in use before replacing it) live in one place.
actor AccountService {
    enum SyncOutcome: Equatable, Sendable {
        case signedOut
        case current(UUID)
        /// A login Keyhop hadn't seen before, now saved.
        case saved(UUID)
        case failed(String)
    }

    private(set) var accounts: [Account]
    private(set) var active: [Provider: UUID] = [:]
    let vault: Vault
    private let adapters: [Provider: any ProviderAdapter]
    private let metaURL: URL
    private let onActiveChange: @Sendable (Provider, UUID?) -> Void
    private let directory: URL
    /// The running sessions of a tool, so a login one may hold has its token left to it.
    private let sessions: @Sendable (Provider) -> [ToolSession]?
    /// The last hop per tool, so a login something else puts back soon after can be noticed.
    private var lastHop: [Provider: (from: UUID, to: UUID, at: Date)] = [:]
    private var notes: [String] = []

    init(directory: URL = Platform.dataDirectory,
         adapters: [Provider: any ProviderAdapter] = Adapters.all,
         vault: Vault = Vault(),
         onActiveChange: @escaping @Sendable (Provider, UUID?) -> Void = { _, _ in },
         sessions: (@Sendable (Provider) -> [ToolSession]?)? = nil) {
        self.directory = directory
        let runBase = directory.appendingPathComponent("run", isDirectory: true)
        self.sessions = sessions ?? { ToolSessions.running($0, runBase: runBase) }
        metaURL = directory.appendingPathComponent("accounts.json")
        accounts = Self.loadAccounts(from: directory)
        self.adapters = adapters
        self.vault = vault
        self.onActiveChange = onActiveChange
    }

    static func loadAccounts(from directory: URL) -> [Account] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Account].self, from: Data(contentsOf: directory.appendingPathComponent("accounts.json")))) ?? []
    }

    func holdsManyLogins(_ provider: Provider) -> Bool {
        adapters[provider]?.holdsManyLogins ?? false
    }

    func account(_ id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    /// Tools with exactly one saved account. Usage from before Keyhop recorded any switch can
    /// only have come from that account.
    var soleAccounts: [Provider: UUID] {
        Dictionary(grouping: accounts, by: \.provider).compactMapValues { $0.count == 1 ? $0[0].id : nil }
    }

    /// What happened on its own since the last look, for the app and the window to say.
    func takeNotes() -> [String] {
        defer { notes.removeAll() }
        return notes
    }

    func secret(for id: UUID) async -> Secret? {
        await vault.read(id)
    }

    // MARK: Logins

    /// Reads the tool's current login, keeps the saved copy of it fresh (tools rotate tokens on
    /// their own), and saves logins Keyhop hasn't seen yet.
    func syncLive(_ provider: Provider) async -> SyncOutcome {
        guard let adapter = adapters[provider] else { return .signedOut }
        let live: LiveLogin?
        do {
            live = try await adapter.readLive()
        } catch {
            return .failed("\(provider.name): \(error.localizedDescription)")
        }
        guard let live else {
            setActive(provider, nil)
            return .signedOut
        }

        if let known = accounts.first(where: { $0.provider == provider && $0.identity == live.identity }) {
            guard await vault.write(live.secret, for: known.id) else {
                return .failed("Couldn't update the saved \(provider.name) login in \(vault.storeName).")
            }
            if let index = accounts.firstIndex(where: { $0.id == known.id }) {
                let placeholder = "\(provider.name) account"
                if !live.email.isEmpty, live.emailTrusted || accounts[index].email == placeholder {
                    accounts[index].email = live.email
                }
                if let plan = live.plan { accounts[index].plan = plan }
            }
            // An open session that saves its token after a hop writes the old login back. Its fresh
            // token is kept above; the hop is put back once and the person is told.
            if let hop = lastHop[provider], hop.from == known.id, active[provider] == hop.to,
               Date().timeIntervalSince(hop.at) < 15 * 60 {
                lastHop[provider] = nil
                if let target = account(hop.to), sessions(provider)?.contains(where: { $0.place == .own(hop.to) }) != true,
                   (try? await RefreshLock.holding(hop.to, in: directory, { () async throws -> Bool in
                       guard let secret = await Self.freshest(target, vault: vault, directory: directory) else { return false }
                       try await adapter.apply(secret)
                       return true
                   })) == true {
                    let name = account(hop.to)?.displayName ?? "the new login"
                    notes.append("An open \(provider.name) session put \(known.displayName) back. Keyhop moved it to \(name) again; restart that session to keep it there.")
                    saveMeta()
                    return .current(hop.to)
                }
            }
            setActive(provider, known.id)
            saveMeta()
            await saveOtherLogins(provider, adapter: adapter)
            return .current(known.id)
        }

        let email = live.email.isEmpty ? "\(provider.name) account" : live.email
        let account = Account(id: UUID(), provider: provider, identity: live.identity, email: email,
                              label: nil, plan: live.plan, addedAt: Date())
        guard await vault.write(live.secret, for: account.id) else {
            return .failed("Couldn't save the \(provider.name) login to \(vault.storeName).")
        }
        // Another sync may have saved the same login while this one waited on the vault.
        if let existing = accounts.first(where: { $0.provider == provider && $0.identity == live.identity }) {
            await vault.delete(account.id)
            setActive(provider, existing.id)
            return .current(existing.id)
        }
        accounts.append(account)
        setActive(provider, account.id)
        saveMeta()
        await saveOtherLogins(provider, adapter: adapter)
        return .saved(account.id)
    }

    /// Saves the logins a tool holds besides the one in use, for tools that keep several at once.
    /// Nothing here changes which account is active; a failure only means one is saved later.
    private func saveOtherLogins(_ provider: Provider, adapter: any ProviderAdapter) async {
        guard let logins = try? await adapter.readAllLogins(), logins.count > 1 else { return }
        var changed = false
        for live in logins where !accounts.contains(where: { $0.provider == provider && $0.identity == live.identity }) {
            let email = live.email.isEmpty ? "\(provider.name) account" : live.email
            let account = Account(id: UUID(), provider: provider, identity: live.identity, email: email,
                                  label: nil, plan: live.plan, addedAt: Date())
            guard await vault.write(live.secret, for: account.id) else { continue }
            if accounts.contains(where: { $0.provider == provider && $0.identity == live.identity }) {
                await vault.delete(account.id)
                continue
            }
            accounts.append(account)
            changed = true
        }
        if changed { saveMeta() }
    }

    /// Moves the tool to a saved account. The login in use is saved first, so a switch never
    /// loses one.
    @discardableResult
    func switchTo(_ id: UUID) async throws -> Account {
        guard let account = account(id), let adapter = adapters[account.provider] else {
            throw KeyhopError("That account isn't saved.")
        }
        let provider = account.provider
        if case .failed(let message) = await syncLive(provider) { throw KeyhopError(message) }
        guard active[provider] != id else { return account }
        if let session = sessions(provider)?.first(where: { $0.place == .own(id) }) {
            throw KeyhopError("\(account.displayName) is running in its own terminal (keyhop run\(session.directory.map { " in \($0)" } ?? "")). Two places refreshing one login sign it out, so close that session before hopping to it.")
        }
        let previous = active[provider]
        lastHop[provider] = nil
        // Under the refresh lock, so a refresh in flight elsewhere can't retire the token being put in place.
        let vault = vault, directory = directory, storeName = vault.storeName
        try await RefreshLock.holding(id, in: directory) {
            guard let secret = await Self.freshest(account, vault: vault, directory: directory) else {
                throw KeyhopError("The saved login for \(account.email) is missing from \(storeName).")
            }
            try await adapter.apply(secret)
        }
        switch await syncLive(provider) {
        case .current(let active) where active == id,
             .saved(let active) where active == id:
            if let previous { lastHop[provider] = (previous, id, Date()) }
            return account
        case .failed(let message):
            throw KeyhopError("The login was applied, but Keyhop couldn't confirm the switch. \(message)")
        case .signedOut:
            throw KeyhopError("The login was applied, but \(provider.name) still appears signed out.")
        case .current(let active), .saved(let active):
            let live = self.account(active)?.displayName ?? "another account"
            throw KeyhopError("The login was applied, but \(provider.name) reports \(live) instead of \(account.displayName).")
        }
    }

    /// Signs the tool out on this machine only, after saving its login, so the next sign-in can be
    /// a different account. Returns the account that was in use.
    func signOutForAdding(_ provider: Provider) async throws -> UUID? {
        guard let adapter = adapters[provider] else { return nil }
        // Waiting ten minutes for a login that can never arrive helps nobody.
        if let blocker = adapter.blocker() { throw KeyhopError(Output.plain(blocker)) }
        if case .failed(let message) = await syncLive(provider) { throw KeyhopError(message) }
        let previous = active[provider]
        if previous != nil {
            try await adapter.signOutLocally()
            setActive(provider, nil)
        }
        return previous
    }

    /// Waits for the tool to have a login again, then saves it. Returns nil when time runs out or
    /// the calling task is cancelled.
    func waitForLogin(_ provider: Provider, attempts: Int = 300, interval: Duration = .seconds(2)) async -> (outcome: SyncOutcome, alreadySaved: Bool)? {
        guard let adapter = adapters[provider] else { return nil }
        // A tool that holds several logins (gh) never signed out, so its old account is still live.
        // For those, wait for a login that wasn't saved before rather than returning the old one.
        let stillSignedIn = (try? await adapter.readLive()) != nil
        let before = Set(accounts.filter { $0.provider == provider }.map(\.identity))
        for _ in 0..<attempts {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return nil }
            if stillSignedIn {
                guard let logins = try? await adapter.readAllLogins(),
                      let fresh = logins.first(where: { !before.contains($0.identity) }) else { continue }
                let outcome = await syncLive(provider)
                if case .failed = outcome { return (outcome, false) }
                guard let saved = accounts.first(where: { $0.provider == provider && $0.identity == fresh.identity }) else { continue }
                return (.saved(saved.id), false)
            }
            if let live = try? await adapter.readLive() {
                let known = accounts.contains { $0.provider == provider && $0.identity == live.identity }
                return (await syncLive(provider), known)
            }
        }
        return nil
    }

    // MARK: One login, one place

    private func hasOwnFolder(_ account: Account) -> Bool {
        RunDirectories.supports(account.provider)
            && FileManager.default.fileExists(atPath: RunDirectories.folder(provider: account.provider, account: account.id, base: runBase).path)
    }

    private var runBase: URL { directory.appendingPathComponent("run", isDirectory: true) }

    /// The saved login, or the newer copy its tool left in the login's `keyhop run` folder, which
    /// then becomes the saved one: the tool refreshed it there and retired the saved token.
    static func freshest(_ account: Account, vault: Vault, directory: URL) async -> Secret? {
        guard let saved = await vault.read(account.id) else { return nil }
        let folder = RunDirectories.folder(provider: account.provider, account: account.id, base: directory.appendingPathComponent("run", isDirectory: true))
        let newer: Secret?
        switch account.provider {
        case .claude: newer = ClaudeAdapter.folderCopy(in: folder, newerThan: saved)
        case .codex: newer = CodexAdapter.folderCopy(in: folder, newerThan: saved)
        default: newer = nil
        }
        guard let newer else { return saved }
        return await vault.write(newer, for: account.id) ? newer : saved
    }

    /// Where `keyhop run` runs a login: nil for the tool's usual folder when the login is the one
    /// in use there (a second copy would refresh against the first), else its own folder with the
    /// freshest login in it. Refuses while a session in the usual folder may still hold it.
    func prepareRun(_ id: UUID) async throws -> URL? {
        guard let account = account(id) else { throw KeyhopError("That account isn't saved.") }
        if case .failed(let message) = await syncLive(account.provider) { throw KeyhopError(message) }
        if active[account.provider] == id { return nil }
        if let found = sessions(account.provider),
           let session = found.first(where: { $0.place != .own(id) && ToolSessions.holds($0, account, hasOwnFolder: false) }) {
            throw KeyhopError("A \(account.provider.name) session\(session.directory.map { " in \($0)" } ?? "") started before Keyhop saw \(account.displayName) leave, so it may still hold that login. Two places refreshing one login sign it out: close that session first, or hop to \(account.displayName) instead.")
        }
        let vault = vault, directory = directory, base = runBase, storeName = vault.storeName
        return try await RefreshLock.holding(id, in: directory) {
            guard let secret = await Self.freshest(account, vault: vault, directory: directory) else {
                throw KeyhopError("The saved login for \(account.displayName) is missing from \(storeName).")
            }
            return try RunDirectories.prepare(account: account, secret: secret, base: base)
        }
    }

    // MARK: Limits

    /// Fetches every saved account's limits with its own token. Tokens are refreshed only for
    /// accounts that aren't in use, and for Claude Code and Codex only while none of their
    /// sessions runs (`ToolSessions`). Failures keep the last good reading alongside the error.
    func fetchUsage(previous: [UUID: UsageSnapshot], progress: ProgressHandler? = nil) async -> [UUID: UsageSnapshot] {
        // A login not in use is noted as left now if it never was, so later sessions don't count.
        var noted = false
        for index in accounts.indices where accounts[index].leftAt == nil && active[accounts[index].provider] != accounts[index].id {
            accounts[index].leftAt = Self.leaveTime()
            noted = true
        }
        if noted { saveMeta() }
        var running: [Provider: [ToolSession]?] = [:]
        for provider in Set(accounts.map(\.provider)) where ToolSessions.rotating.contains(provider) {
            running[provider] = sessions(provider)
        }
        // (account, leave its token alone): the login in use, or one a running session may hold.
        func held(_ account: Account, _ found: [ToolSession]??, ownFolder: Bool) -> Bool {
            guard let found else { return false }
            guard let found else { return true }
            return found.contains { ToolSessions.holds($0, account, hasOwnFolder: ownFolder) }
        }
        let targets = accounts.map { account -> (Account, Bool, Bool) in
            let ownFolder = hasOwnFolder(account)
            if active[account.provider] == account.id { return (account, true, ownFolder) }
            return (account, held(account, running[account.provider], ownFolder: ownFolder), ownFolder)
        }
        let directory = directory
        let sessions = sessions
        progress?(WorkProgress(step: .limits, done: 0, total: targets.count))
        let vault = vault
        let adapters = adapters
        let results = await withTaskGroup(of: (UUID, UsageSnapshot, String?).self) { group -> [(UUID, UsageSnapshot, String?)] in
            for (account, isActive, ownFolder) in targets {
                guard let adapter = adapters[account.provider] else { continue }
                let earlier = previous[account.id] ?? UsageSnapshot()
                group.addTask {
                    var snapshot = earlier
                    var plan: String?
                    if await vault.read(account.id) != nil {
                        do {
                            let read = { () async throws -> LimitReport in
                                // Read again inside the lock: another process, or the tool in the login's own
                                // folder, may have just refreshed it.
                                guard let secret = await Self.freshest(account, vault: vault, directory: directory) else {
                                    throw KeyhopError("The saved login is missing.")
                                }
                                // A session may have started while this waited on the lock: look again.
                                let leave = isActive || (ToolSessions.rotating.contains(account.provider)
                                    && held(account, .some(sessions(account.provider)), ownFolder: ownFolder))
                                return try await adapter.fetchUsage(secret, allowRefresh: !leave) { updated in
                                    // The old token is spent: the new one has to be kept, so try again before giving up.
                                    for attempt in 0..<3 {
                                        if await vault.write(updated, for: account.id) { return }
                                        try? await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
                                    }
                                }
                            }
                            let report = isActive ? try await read() : try await RefreshLock.holding(account.id, in: directory, read)
                            snapshot = UsageSnapshot(windows: report.windows, error: nil, fetchedAt: Date())
                            plan = report.plan
                        } catch is LimitsWaitForTool {
                            // Not signed out: the tool refreshes it on its next use. The last reading stays.
                            snapshot.error = nil
                            snapshot.signedOut = nil
                        } catch {
                            // A failed reading keeps the last good one; only a turned-down login is signed out.
                            snapshot.error = error.localizedDescription
                            snapshot.signedOut = (error as? KeyhopError)?.signedOut == true ? true : nil
                        }
                    } else {
                        snapshot.error = "The saved login is missing."
                        snapshot.signedOut = true
                    }
                    return (account.id, snapshot, plan)
                }
            }
            var collected: [(UUID, UsageSnapshot, String?)] = []
            let names = Dictionary(uniqueKeysWithValues: targets.map { ($0.0.id, $0.0.provider.name) })
            for await result in group {
                collected.append(result)
                progress?(WorkProgress(step: .limits, done: collected.count, total: targets.count, detail: names[result.0]))
            }
            return collected
        }

        var usage: [UUID: UsageSnapshot] = [:]
        var changed = false
        for (id, snapshot, plan) in results {
            usage[id] = snapshot
            if let plan, let index = accounts.firstIndex(where: { $0.id == id }), accounts[index].plan != plan {
                accounts[index].plan = plan
                changed = true
            }
        }
        if changed { saveMeta() }
        return usage
    }

    // MARK: Editing

    func rename(_ id: UUID, to label: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].label = trimmed.isEmpty ? nil : trimmed
        saveMeta()
    }

    func remove(_ id: UUID) async throws {
        guard let account = account(id) else { throw KeyhopError("That account isn't saved.") }
        guard active[account.provider] != id else {
            throw KeyhopError("\(account.displayName) is in use. Switch \(account.provider.name) to another account first.")
        }
        accounts.removeAll { $0.id == id }
        saveMeta()
        await vault.delete(id)
    }

    private func setActive(_ provider: Provider, _ id: UUID?) {
        guard active[provider] != id else { return }
        if let left = active[provider], let index = accounts.firstIndex(where: { $0.id == left }) {
            accounts[index].leftAt = Self.leaveTime()
        }
        active[provider] = id
        onActiveChange(provider, id)
    }

    /// Now, rounded up to the second the accounts file keeps, so a session that started a moment
    /// before the leave never reads as after it.
    static func leaveTime(_ now: Date = Date()) -> Date {
        Date(timeIntervalSince1970: (now.timeIntervalSince1970).rounded(.up))
    }

    private func saveMeta() {
        // Another Keyhop process may have seen a later leave: keep the latest of the two.
        let onDisk = Dictionary(Self.loadAccounts(from: directory).map { ($0.id, $0.leftAt) }, uniquingKeysWith: { a, _ in a })
        for index in accounts.indices {
            if let theirs = onDisk[accounts[index].id] ?? nil, theirs > (accounts[index].leftAt ?? .distantPast),
               active[accounts[index].provider] != accounts[index].id {
                accounts[index].leftAt = theirs
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(accounts) else { return }
        try? Files.writeAtomically(data, to: metaURL)
    }
}
