import Foundation

/// The native messaging host Chrome starts for the extension: `keyhop` run with the extension's
/// origin as its argument. It tells the extension which account each tool uses, hands it the
/// saved site login for a hop, and keeps the logins the extension sees. Nothing but framed
/// messages may reach standard output.
actor BrowserHost {
    struct Incoming: Decodable {
        var type: String
        var id: String?
        var site: String?
        var account: String?
        var email: String?
        var webId: String?
        var cookies: [BrowserCookie]?
        var version: String?
    }

    struct AccountRef: Encodable, Equatable {
        var id: String
        var email: String
        var name: String
        var web: Bool?
    }

    struct SiteState: Encodable, Equatable {
        var site: String
        var tool: String
        var active: AccountRef?
        var accounts: [AccountRef]
    }

    struct Outgoing: Encodable {
        var type: String
        var id: String?
        var site: String?
        var version: String?
        var sites: [SiteState]?
        var account: AccountRef?
        var email: String?
        var cookies: [BrowserCookie]?
        var error: String?
    }

    private let directory: URL
    private let vault: Vault
    private let send: @Sendable (Data) -> Void
    private var web: Set<UUID>?
    private var lastState: [SiteState] = []
    private var stamps: [Date?] = []
    private var extensionVersion: String?

    init(directory: URL = Platform.dataDirectory, vault: Vault = Vault(), send: @escaping @Sendable (Data) -> Void) {
        self.directory = directory
        self.vault = vault
        self.send = send
    }

    // MARK: Framing

    /// Chrome's framing: a 32-bit length in native byte order (little-endian on every Mac and PC
    /// Keyhop runs on), then that many bytes of JSON.
    static func frame(_ json: Data) -> Data {
        var length = UInt32(json.count).littleEndian
        return Data(bytes: &length, count: 4) + json
    }

    static func runAndExit() -> Never {
        let output = FileHandle.standardOutput
        let lock = NSLock()
        let host = BrowserHost(send: { json in
            lock.lock()
            output.write(BrowserHost.frame(json))
            lock.unlock()
        })
        let input = FileHandle.standardInput
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            while !Task.isCancelled {
                await host.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        Thread.detachNewThread {
            while true {
                let head = input.readData(ofLength: 4)
                guard head.count == 4 else { break }
                let length = head.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
                guard length > 0, length <= 4 << 20 else { break }
                let body = input.readData(ofLength: length)
                guard body.count == length else { break }
                let wait = DispatchSemaphore(value: 0)
                Task.detached {
                    await host.receive(body)
                    wait.signal()
                }
                wait.wait()
            }
            done.signal()
        }
        done.wait()
        exit(0)
    }

    // MARK: Messages

    func receive(_ body: Data) async {
        guard let message = try? JSONDecoder().decode(Incoming.self, from: body) else { return }
        if let reply = await handle(message) { emit(reply) }
    }

    func handle(_ message: Incoming) async -> Outgoing? {
        switch message.type {
        case "hello":
            extensionVersion = message.version ?? "unknown"
            noteSeen()
            stamps = stampsNow()
            lastState = await sites()
            return Outgoing(type: "state", version: AppVersion.current, sites: lastState)
        case "cookies":
            guard let id = message.account.flatMap(UUID.init(uuidString:)) else {
                return Outgoing(type: "cookies", id: message.id, error: "No account.")
            }
            let session = await vault.webSession(id)
            return Outgoing(type: "cookies", id: message.id, site: message.site, cookies: session?.cookies ?? [])
        case "session":
            return await keep(message)
        default:
            return Outgoing(type: "error", id: message.id, error: "Unknown message \(message.type).")
        }
    }

    private func keep(_ message: Incoming) async -> Outgoing {
        guard let site = message.site.flatMap(BrowserSite.init(rawValue:)), let email = message.email,
              let cookies = message.cookies, !cookies.isEmpty else {
            return Outgoing(type: "error", id: message.id, error: "Incomplete session.")
        }
        let accounts = AccountService.loadAccounts(from: directory)
        let found = BrowserSetup.matches(email: email, webID: message.webId ?? "", site: site, in: accounts)
        guard let first = found.first else {
            return Outgoing(type: "unknown", id: message.id, site: site.rawValue, email: email)
        }
        let session = WebSession(site: site.rawValue, email: email, cookies: cookies, savedAt: Date())
        var known = await webSet()
        for account in found where await vault.writeWebSession(session, for: account.id) {
            known.insert(account.id)
        }
        web = known
        return Outgoing(type: "saved", id: message.id, site: site.rawValue, account: ref(first, web: true))
    }

    // MARK: State

    /// Every two seconds: when the accounts or the one in use change, the extension hears.
    func tick() async {
        // Nothing is said before the extension says hello.
        guard extensionVersion != nil else { return }
        noteSeen()
        let now = stampsNow()
        guard now != stamps else { return }
        stamps = now
        let state = await sites()
        guard state != lastState else { return }
        lastState = state
        emit(Outgoing(type: "state", version: AppVersion.current, sites: state))
    }

    private func stampsNow() -> [Date?] {
        ["accounts.json", "cli-state.json"].map { name in
            (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path))?[.modificationDate] as? Date
        }
    }

    func sites() async -> [SiteState] {
        let accounts = AccountService.loadAccounts(from: directory)
        let active = CLIState.load(from: directory.appendingPathComponent("cli-state.json")).activeByTool
        let known = await webSet()
        return BrowserSite.allCases.map { site in
            let mine = accounts.filter { $0.provider == site.provider }
            let inUse = active[site.provider].flatMap { id in mine.first { $0.id == id } }
            return SiteState(site: site.rawValue, tool: site.provider.rawValue, active: inUse.map { ref($0, web: nil) },
                             accounts: mine.map { ref($0, web: known.contains($0.id)) })
        }
    }

    private func webSet() async -> Set<UUID> {
        if let web { return web }
        var found = Set<UUID>()
        for account in AccountService.loadAccounts(from: directory) where BrowserSite.of(account.provider) != nil {
            if await vault.webSession(account.id) != nil { found.insert(account.id) }
        }
        web = found
        return found
    }

    private func ref(_ account: Account, web: Bool?) -> AccountRef {
        AccountRef(id: account.id.uuidString, email: account.email, name: account.displayName, web: web)
    }

    private func emit(_ message: Outgoing) {
        guard let json = try? JSONEncoder().encode(message) else { return }
        send(json)
    }

    private var lastNote = Date.distantPast

    /// Settings shows when the extension last talked to Keyhop; once a minute is often enough.
    private func noteSeen() {
        guard extensionVersion != nil, Date().timeIntervalSince(lastNote) > 60 else { return }
        lastNote = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(BrowserSetup.Seen(lastSeen: Date(), extensionVersion: extensionVersion)) {
            try? Files.writeAtomically(data, to: directory.appendingPathComponent("browser.json"))
        }
    }
}
