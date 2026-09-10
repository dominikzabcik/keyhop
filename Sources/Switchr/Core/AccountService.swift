import Foundation

/// Saved accounts and everything done with them: noticing logins, switching, adding and
/// fetching limits. The macOS app and the `switchr` command both drive this, so the rules
/// (above all: save the login in use before replacing it) live in one place.
actor AccountService {
    enum SyncOutcome: Equatable, Sendable {
        case signedOut
        case current(UUID)
        /// A login Switchr hadn't seen before, now saved.
        case saved(UUID)
        case failed(String)
    }

    private(set) var accounts: [Account]
    private(set) var active: [Provider: UUID] = [:]
    let vault: Vault
    private let adapters: [Provider: any ProviderAdapter]
    private let metaURL: URL
    private let onActiveChange: @Sendable (Provider, UUID?) -> Void

    init(directory: URL = Platform.dataDirectory,
         adapters: [Provider: any ProviderAdapter] = Adapters.all,
         vault: Vault = Vault(),
         onActiveChange: @escaping @Sendable (Provider, UUID?) -> Void = { _, _ in }) {
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

    func account(_ id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    /// Tools with exactly one saved account. Usage from before Switchr recorded any switch can
    /// only have come from that account.
    var soleAccounts: [Provider: UUID] {
        Dictionary(grouping: accounts, by: \.provider).compactMapValues { $0.count == 1 ? $0[0].id : nil }
    }

    func secret(for id: UUID) async -> Secret? {
        await vault.read(id)
    }

    // MARK: Logins

    /// Reads the tool's current login, keeps the saved copy of it fresh (tools rotate tokens on
    /// their own), and saves logins Switchr hasn't seen yet.
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
            setActive(provider, known.id)
            saveMeta()
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
        return .saved(account.id)
    }

    /// Moves the tool to a saved account. The login in use is saved first, so a switch never
    /// loses one.
    @discardableResult
    func switchTo(_ id: UUID) async throws -> Account {
        guard let account = account(id), let adapter = adapters[account.provider] else {
            throw SwitchrError("That account isn't saved.")
        }
        let provider = account.provider
        if case .failed(let message) = await syncLive(provider) { throw SwitchrError(message) }
        guard active[provider] != id else { return account }
        guard let secret = await vault.read(id) else {
            throw SwitchrError("The saved login for \(account.email) is missing from \(vault.storeName).")
        }
        try await adapter.apply(secret)
        _ = await syncLive(provider)
        return account
    }

    /// Signs the tool out on this machine only, after saving its login, so the next sign-in can be
    /// a different account. Returns the account that was in use.
    func signOutForAdding(_ provider: Provider) async throws -> UUID? {
        guard let adapter = adapters[provider] else { return nil }
        if case .failed(let message) = await syncLive(provider) { throw SwitchrError(message) }
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
        for _ in 0..<attempts {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return nil }
            if let live = try? await adapter.readLive() {
                let known = accounts.contains { $0.provider == provider && $0.identity == live.identity }
                return (await syncLive(provider), known)
            }
        }
        return nil
    }

    // MARK: Limits

    /// Fetches every saved account's limits with its own token. Tokens are refreshed only for
    /// accounts that aren't in use. Failures keep the last good reading alongside the error.
    func fetchUsage(previous: [UUID: UsageSnapshot]) async -> [UUID: UsageSnapshot] {
        let targets = accounts.map { ($0, active[$0.provider] == $0.id) }
        let vault = vault
        let adapters = adapters
        let results = await withTaskGroup(of: (UUID, UsageSnapshot, String?).self) { group -> [(UUID, UsageSnapshot, String?)] in
            for (account, isActive) in targets {
                guard let adapter = adapters[account.provider] else { continue }
                let earlier = previous[account.id] ?? UsageSnapshot()
                group.addTask {
                    var snapshot = earlier
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
                        snapshot.error = "The saved login is missing."
                    }
                    return (account.id, snapshot, plan)
                }
            }
            var collected: [(UUID, UsageSnapshot, String?)] = []
            for await result in group { collected.append(result) }
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
        guard let account = account(id) else { throw SwitchrError("That account isn't saved.") }
        guard active[account.provider] != id else {
            throw SwitchrError("\(account.displayName) is in use. Switch \(account.provider.name) to another account first.")
        }
        accounts.removeAll { $0.id == id }
        saveMeta()
        await vault.delete(id)
    }

    private func setActive(_ provider: Provider, _ id: UUID?) {
        guard active[provider] != id else { return }
        active[provider] = id
        onActiveChange(provider, id)
    }

    private func saveMeta() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(accounts) else { return }
        try? Files.writeAtomically(data, to: metaURL)
    }
}
