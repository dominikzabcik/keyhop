import XCTest
@testable import Keyhop

final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()
    var name: String { "memory" }

    func read(_ account: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return items[account]
    }

    func write(_ data: Data, account: String) throws {
        lock.lock()
        items[account] = data
        lock.unlock()
    }

    func delete(_ account: String) {
        lock.lock()
        items[account] = nil
        lock.unlock()
    }
}

/// A tool whose login is a dictionary, so the switching rules run without real apps.
final class FakeTool: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Secret?

    init(_ login: Secret? = nil) {
        current = login
    }

    var login: Secret? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return current
        }
        set {
            lock.lock()
            current = newValue
            lock.unlock()
        }
    }

    /// Changes the login under the lock, so logins read at once never lose each other's note.
    func update(_ change: (inout Secret) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var secret = current ?? [:]
        change(&secret)
        current = secret
    }
}

struct FakeAdapter: ProviderAdapter {
    let provider: Provider
    let tool: FakeTool

    func readLive() async throws -> LiveLogin? {
        guard let secret = tool.login, let user = secret["user"] else { return nil }
        return LiveLogin(identity: user, email: "\(user)@example.com", plan: "Pro", secret: secret)
    }

    func apply(_ secret: Secret) async throws { tool.login = secret }

    func signOutLocally() async throws { tool.login = nil }

    func anthropicAccount(of secret: Secret) async -> String? { secret["anthropic"] }

    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        guard let used = secret["used"].flatMap(Double.init) else { throw KeyhopError("No usage for this login") }
        return LimitReport(windows: [UsageWindow(label: "5h", usedPercent: used, resetsAt: nil, windowSeconds: 18000)], plan: "Max")
    }
}

struct UnconfirmedAdapter: ProviderAdapter {
    let provider: Provider = .codex
    let tool: FakeTool
    let result: Secret?

    func readLive() async throws -> LiveLogin? {
        guard let secret = tool.login, let user = secret["user"] else { return nil }
        return LiveLogin(identity: user, email: "\(user)@example.com", plan: nil, secret: secret)
    }

    func apply(_ secret: Secret) async throws { tool.login = result }
    func signOutLocally() async throws { tool.login = nil }
    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        LimitReport(windows: [], plan: nil)
    }
}

final class AccountServiceTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-service-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func service(_ tool: FakeTool) -> AccountService {
        AccountService(directory: directory, adapters: [.codex: FakeAdapter(provider: .codex, tool: tool)], vault: Vault(store: MemorySecretStore()))
    }

    private func savedID(_ outcome: AccountService.SyncOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> UUID {
        guard case .saved(let id) = outcome else {
            XCTFail("Expected a newly saved account, got \(outcome)", file: file, line: line)
            throw KeyhopError("not saved")
        }
        return id
    }

    func testTheSignedInLoginIsSavedOnFirstSync() async throws {
        let tool = FakeTool(["user": "ada", "token": "a1"])
        let service = service(tool)
        let ada = try savedID(await service.syncLive(.codex))

        let accounts = await service.accounts
        XCTAssertEqual(accounts.map(\.email), ["ada@example.com"])
        let active = await service.active
        XCTAssertEqual(active[.codex], ada)
        let again = await service.syncLive(.codex)
        XCTAssertEqual(again, .current(ada))
        XCTAssertEqual(AccountService.loadAccounts(from: directory).map(\.id), [ada])
    }

    func testAnOldLoginWrittenBackRightAfterAHopIsMovedAgainOnce() async throws {
        let tool = FakeTool(["user": "ada", "token": "a1"])
        let service = service(tool)
        let ada = try savedID(await service.syncLive(.codex))
        tool.login = ["user": "bob", "token": "b1"]
        let bob = try savedID(await service.syncLive(.codex))
        try await service.switchTo(ada)

        // An open session started on Bob saves its refreshed token over the hop.
        tool.login = ["user": "bob", "token": "b2"]
        let outcome = await service.syncLive(.codex)
        XCTAssertEqual(outcome, .current(ada))
        XCTAssertEqual(tool.login?["user"], "ada")
        let kept = await service.secret(for: bob)
        XCTAssertEqual(kept?["token"], "b2")
        let notes = await service.takeNotes()
        XCTAssertEqual(notes.count, 1)
        let again = await service.takeNotes()
        XCTAssertTrue(again.isEmpty)

        // Only once: a second write-back is taken as meant.
        tool.login = ["user": "bob", "token": "b3"]
        let second = await service.syncLive(.codex)
        XCTAssertEqual(second, .current(bob))
    }

    func testOpenCodeAndPiFollowAClaudeHopToTheirOwnProfileForThatAccount() async throws {
        let claude = FakeTool(["user": "ada", "token": "c1"])
        let opencode = FakeTool(["user": "oc-ada", "anthropic": "ada", "token": "o1"])
        let pi = FakeTool(["user": "pi-ada", "anthropic": "ada", "token": "p1"])
        let service = AccountService(directory: directory, adapters: [
            .claude: FakeAdapter(provider: .claude, tool: claude),
            .opencode: FakeAdapter(provider: .opencode, tool: opencode),
            .pi: FakeAdapter(provider: .pi, tool: pi),
        ], vault: Vault(store: MemorySecretStore()), sessions: { _ in [] })
        _ = try savedID(await service.syncLive(.claude))
        _ = try savedID(await service.syncLive(.opencode))
        _ = try savedID(await service.syncLive(.pi))
        claude.login = ["user": "bob", "token": "c2"]
        let bob = try savedID(await service.syncLive(.claude))
        opencode.login = ["user": "oc-bob", "anthropic": "bob", "token": "o2"]
        let openBob = try savedID(await service.syncLive(.opencode))
        claude.login = ["user": "ada", "token": "c1"]
        opencode.login = ["user": "oc-ada", "anthropic": "ada", "token": "o1"]
        _ = await service.syncLive(.claude)
        _ = await service.syncLive(.opencode)

        let switched = try await service.switchTo(bob)
        XCTAssertEqual(claude.login?["user"], "bob")
        XCTAssertEqual(opencode.login?["user"], "oc-bob")
        // Its own profile, never Claude Code's token.
        XCTAssertEqual(opencode.login?["token"], "o2")
        XCTAssertEqual(switched.followed.map(\.id), [openBob])
        // Pi has no profile for Bob, so it stays where it was and says so.
        XCTAssertEqual(pi.login?["user"], "pi-ada")
        XCTAssertEqual(switched.notes.count, 2)
        XCTAssertTrue(switched.notes[1].contains("Pi stays on"))
        XCTAssertEqual(AccountService.loadAccounts(from: directory).first { $0.id == openBob }?.anthropicAccount, "bob")
    }

    func testAProfileOnAnotherProvidersSignInDoesNotFollowClaude() async throws {
        let claude = FakeTool(["user": "ada", "token": "c1"])
        let opencode = FakeTool(["user": "oc-openai", "token": "o1"])
        let service = AccountService(directory: directory, adapters: [
            .claude: FakeAdapter(provider: .claude, tool: claude),
            .opencode: FakeAdapter(provider: .opencode, tool: opencode),
        ], vault: Vault(store: MemorySecretStore()), sessions: { _ in [] })
        _ = try savedID(await service.syncLive(.claude))
        _ = try savedID(await service.syncLive(.opencode))
        claude.login = ["user": "bob", "token": "c2"]
        _ = try savedID(await service.syncLive(.claude))
        opencode.login = ["user": "oc-bob", "anthropic": "bob", "token": "o2"]
        _ = try savedID(await service.syncLive(.opencode))
        claude.login = ["user": "ada", "token": "c1"]
        opencode.login = ["user": "oc-openai", "token": "o1"]
        _ = await service.syncLive(.claude)
        _ = await service.syncLive(.opencode)

        let accounts = await service.accounts
        let bob = try XCTUnwrap(accounts.first { $0.provider == .claude && $0.identity == "bob" })
        let switched = try await service.switchTo(bob.id)
        XCTAssertEqual(opencode.login?["user"], "oc-openai")
        XCTAssertTrue(switched.followed.isEmpty)
        XCTAssertTrue(switched.notes.isEmpty)
    }

    func testSwitchingSavesTheRotatedLoginBeforeReplacingIt() async throws {
        let tool = FakeTool(["user": "ada", "token": "a1"])
        let service = service(tool)
        let ada = try savedID(await service.syncLive(.codex))
        tool.login = ["user": "bob", "token": "b1"]
        let bob = try savedID(await service.syncLive(.codex))

        try await service.switchTo(ada)
        XCTAssertEqual(tool.login?["user"], "ada")

        // Ada's session refreshes its token without Keyhop seeing it, then Keyhop moves to Bob.
        tool.login = ["user": "ada", "token": "a2"]
        try await service.switchTo(bob)

        XCTAssertEqual(tool.login?["user"], "bob")
        let adaSecret = await service.secret(for: ada)
        XCTAssertEqual(adaSecret?["token"], "a2")
        let active = await service.active
        XCTAssertEqual(active[.codex], bob)
    }

    func testSwitchingFailsWhenTheToolDoesNotApplyTheChosenLogin() async throws {
        let tool = FakeTool(["user": "ada"])
        let vault = Vault(store: MemorySecretStore())
        let service = AccountService(directory: directory, adapters: [.codex: FakeAdapter(provider: .codex, tool: tool)], vault: vault)
        let ada = try savedID(await service.syncLive(.codex))
        tool.login = ["user": "bob"]
        _ = try savedID(await service.syncLive(.codex))

        let broken = AccountService(directory: directory,
                                    adapters: [.codex: UnconfirmedAdapter(tool: tool, result: ["user": "bob"])], vault: vault)
        do {
            try await broken.switchTo(ada)
            XCTFail("An unconfirmed switch should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("reports"))
        }
    }

    func testSwitchingFailsWhenTheToolAppearsSignedOutAfterApply() async throws {
        let tool = FakeTool(["user": "ada"])
        let vault = Vault(store: MemorySecretStore())
        let service = AccountService(directory: directory, adapters: [.codex: FakeAdapter(provider: .codex, tool: tool)], vault: vault)
        let ada = try savedID(await service.syncLive(.codex))
        tool.login = ["user": "bob"]
        _ = try savedID(await service.syncLive(.codex))

        let broken = AccountService(directory: directory,
                                    adapters: [.codex: UnconfirmedAdapter(tool: tool, result: nil)], vault: vault)
        do {
            try await broken.switchTo(ada)
            XCTFail("A signed-out readback should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("appears signed out"))
        }
    }

    func testAddingSignsOutLocallyAndSavesTheNextLogin() async throws {
        let tool = FakeTool(["user": "ada"])
        let service = service(tool)
        let ada = try savedID(await service.syncLive(.codex))

        let previous = try await service.signOutForAdding(.codex)
        XCTAssertEqual(previous, ada)
        XCTAssertNil(tool.login)

        tool.login = ["user": "cy"]
        let result = await service.waitForLogin(.codex, attempts: 5, interval: .milliseconds(5))
        XCTAssertEqual(result?.alreadySaved, false)
        _ = try savedID(try XCTUnwrap(result?.outcome))
        let accounts = await service.accounts
        XCTAssertEqual(accounts.count, 2)
    }

    func testWaitingGivesUpWhenNoLoginArrives() async throws {
        let service = service(FakeTool())
        let result = await service.waitForLogin(.codex, attempts: 2, interval: .milliseconds(5))
        XCTAssertNil(result)
    }

    func testTheAccountInUseCantBeRemoved() async throws {
        let tool = FakeTool(["user": "ada"])
        let service = service(tool)
        let ada = try savedID(await service.syncLive(.codex))
        tool.login = ["user": "bob"]
        _ = try savedID(await service.syncLive(.codex))

        do {
            try await service.remove(tool.login?["user"] == "bob" ? (await service.active[.codex])! : ada)
            XCTFail("Removing the account in use should fail")
        } catch {}
        try await service.remove(ada)
        let accounts = await service.accounts
        XCTAssertEqual(accounts.map(\.email), ["bob@example.com"])
        let adaSecret = await service.secret(for: ada)
        XCTAssertNil(adaSecret)
    }

    func testLimitsUseEachAccountsOwnLoginAndKeepTheLastReadingOnFailure() async throws {
        let tool = FakeTool(["user": "ada", "used": "30"])
        let service = service(tool)
        let ada = try savedID(await service.syncLive(.codex))
        tool.login = ["user": "bob", "used": "70"]
        let bob = try savedID(await service.syncLive(.codex))

        let first = await service.fetchUsage(previous: [:])
        XCTAssertEqual(first[ada]?.windows.first?.usedPercent, 30)
        XCTAssertEqual(first[bob]?.windows.first?.usedPercent, 70)
        let plans = await service.accounts.map(\.plan)
        XCTAssertEqual(plans, ["Max", "Max"])

        // Bob's login stops returning usage: the error shows, the last reading stays.
        tool.login = ["user": "bob"]
        _ = await service.syncLive(.codex)
        let second = await service.fetchUsage(previous: first)
        XCTAssertEqual(second[bob]?.windows.first?.usedPercent, 70)
        XCTAssertNotNil(second[bob]?.error)
    }

    func testRenamingTrimsAndClears() async throws {
        let service = service(FakeTool(["user": "ada"]))
        let ada = try savedID(await service.syncLive(.codex))
        await service.rename(ada, to: "  Personal  ")
        var label = await service.account(ada)?.label
        XCTAssertEqual(label, "Personal")
        await service.rename(ada, to: " ")
        label = await service.account(ada)?.label
        XCTAssertNil(label)
    }
}

/// Says which logins it was allowed to refresh, and that a token is past its hour when it wasn't.
struct RefreshWatchingAdapter: ProviderAdapter {
    let provider: Provider = .codex
    let tool: FakeTool
    let allowed: FakeTool

    func readLive() async throws -> LiveLogin? {
        guard let secret = tool.login, let user = secret["user"] else { return nil }
        return LiveLogin(identity: user, email: "\(user)@example.com", plan: nil, secret: secret)
    }

    func apply(_ secret: Secret) async throws { tool.login = secret }
    func signOutLocally() async throws { tool.login = nil }
    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        allowed.update { $0[secret["user"] ?? "?"] = allowRefresh ? "yes" : "no" }
        guard allowRefresh || secret["user"] == "ada" else { throw LimitsWaitForTool(tool: "Codex") }
        return LimitReport(windows: [UsageWindow(label: "5h", usedPercent: 10, resetsAt: nil, windowSeconds: 18000)], plan: nil)
    }
}

final class RefreshRuleTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-refresh-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    private func twoLogins(sessionRunning: Bool) async throws -> (AccountService, FakeTool, UUID, UUID) {
        let tool = FakeTool(["user": "bob"]), allowed = FakeTool(nil)
        let service = AccountService(directory: directory, adapters: [.codex: RefreshWatchingAdapter(tool: tool, allowed: allowed)],
                                     vault: Vault(store: MemorySecretStore()),
                                     sessions: { _ in sessionRunning ? [ToolSession(pid: 1, place: .usual, startedAt: .distantPast, directory: nil)] : [] })
        guard case .saved(let bob) = await service.syncLive(.codex) else { throw KeyhopError("bob") }
        tool.login = ["user": "ada"]
        guard case .saved(let ada) = await service.syncLive(.codex) else { throw KeyhopError("ada") }
        return (service, allowed, ada, bob)
    }

    func testOnlyALoginNotInUseIsRefreshedWhileNoSessionRuns() async throws {
        let (service, allowed, _, bob) = try await twoLogins(sessionRunning: false)
        let usage = await service.fetchUsage(previous: [:])
        XCTAssertEqual(allowed.login, ["ada": "no", "bob": "yes"])
        XCTAssertNil(usage[bob]?.error)
    }

    func testARunningSessionKeepsEveryLoginsTokenAndTheLastReadingStays() async throws {
        let (service, allowed, _, bob) = try await twoLogins(sessionRunning: true)
        let earlier = UsageSnapshot(windows: [UsageWindow(label: "5h", usedPercent: 40, resetsAt: nil, windowSeconds: 18000)],
                                    error: "Login expired.", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let usage = await service.fetchUsage(previous: [bob: earlier])
        XCTAssertEqual(allowed.login, ["ada": "no", "bob": "no"])
        XCTAssertEqual(usage[bob]?.windows, earlier.windows)
        XCTAssertEqual(usage[bob]?.fetchedAt, earlier.fetchedAt)
        XCTAssertNil(usage[bob]?.error, "a token past its hour is not a signed-out login")
    }

    func testASessionStartedAfterTheLoginWasLeftDoesNotHoldIt() async throws {
        let tool = FakeTool(["user": "bob"]), allowed = FakeTool(nil)
        let later = Date().addingTimeInterval(60)
        let service = AccountService(directory: directory, adapters: [.codex: RefreshWatchingAdapter(tool: tool, allowed: allowed)],
                                     vault: Vault(store: MemorySecretStore()),
                                     sessions: { _ in [ToolSession(pid: 1, place: .usual, startedAt: later, directory: nil)] })
        guard case .saved = await service.syncLive(.codex) else { throw KeyhopError("bob") }
        tool.login = ["user": "ada"]
        guard case .saved = await service.syncLive(.codex) else { throw KeyhopError("ada") }
        let bob = await service.accounts.first { $0.email.hasPrefix("bob") }
        XCTAssertNotNil(bob?.leftAt, "the hop away from bob is noted")
        _ = await service.fetchUsage(previous: [:])
        XCTAssertEqual(allowed.login, ["ada": "no", "bob": "yes"])
    }

    func testWhichSessionsMayHoldALogin() {
        let left = Date(timeIntervalSince1970: 1_800_000_000)
        let account = Account(id: UUID(), provider: .claude, identity: "a", email: "a@x.dev", label: nil, plan: nil, addedAt: left, leftAt: left)
        func session(_ place: ToolSession.Place, _ offset: TimeInterval?) -> ToolSession {
            ToolSession(pid: 1, place: place, startedAt: offset.map { left.addingTimeInterval($0) }, directory: nil)
        }
        XCTAssertTrue(ToolSessions.holds(session(.usual, -60), account, hasOwnFolder: false))
        XCTAssertFalse(ToolSessions.holds(session(.usual, 60), account, hasOwnFolder: false))
        XCTAssertTrue(ToolSessions.holds(session(.usual, nil), account, hasOwnFolder: false), "an unknown start counts as early")
        XCTAssertTrue(ToolSessions.holds(session(.own(account.id), 60), account, hasOwnFolder: true))
        XCTAssertFalse(ToolSessions.holds(session(.own(UUID()), -60), account, hasOwnFolder: true))
        XCTAssertTrue(ToolSessions.holds(session(.unknown, 60), account, hasOwnFolder: true))
        XCTAssertFalse(ToolSessions.holds(session(.unknown, 60), account, hasOwnFolder: false))
        var never = account
        never.leftAt = nil
        XCTAssertTrue(ToolSessions.holds(session(.usual, 3600), never, hasOwnFolder: false), "a login never seen leaving may be held")
    }

    func testProcessAgesAreRead() {
        XCTAssertEqual(ToolSessions.age("05:09"), 309)
        XCTAssertEqual(ToolSessions.age("01:00:00"), 3600)
        XCTAssertEqual(ToolSessions.age("2-03:00:01"), 2 * 86400 + 10801)
        XCTAssertNil(ToolSessions.age("soon"))
    }

    func testNotedClaudeSessionsCountOnlyWhileTheirProcessRuns() throws {
        #if os(Windows)
        throw XCTSkip("Windows has no process list or file lock for Keyhop to read sessions with")
        #endif
        let folder = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let me = getpid()
        try Data(#"{"pid":\#(me),"startedAt":1800000000000,"cwd":"/work"}"#.utf8).write(to: folder.appendingPathComponent("\(me).json"))
        try Data(#"{"pid":2147483000,"startedAt":1800000000000}"#.utf8).write(to: folder.appendingPathComponent("2147483000.json"))
        let found = ToolSessions.noted(in: folder, place: .usual)
        XCTAssertEqual(found, [ToolSession(pid: me, place: .usual, startedAt: Date(timeIntervalSince1970: 1_800_000_000), directory: "/work")])
    }

    func testTheCopyAToolRefreshedInTheLoginsOwnFolderWins() async throws {
        let vault = Vault(store: MemorySecretStore())
        let account = Account(id: UUID(), provider: .claude, identity: "u|o", email: "a@x.dev", label: nil, plan: nil, addedAt: Date())
        let saved: Secret = ["oauth": #"{"accessToken":"old","refreshToken":"r1","expiresAt":1000}"#, "account": #"{"accountUuid":"u"}"#]
        _ = await vault.write(saved, for: account.id)
        let folder = RunDirectories.folder(provider: .claude, account: account.id, base: directory.appendingPathComponent("run"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"claudeAiOauth":{"accessToken":"new","refreshToken":"r2","expiresAt":2000}}"#.utf8).write(to: folder.appendingPathComponent(".credentials.json"))

        let fresh = await AccountService.freshest(account, vault: vault, directory: directory)
        XCTAssertEqual(JSON.object(fresh?["oauth"])?["refreshToken"] as? String, "r2")
        let kept = await vault.read(account.id)
        XCTAssertEqual(JSON.object(kept?["oauth"])?["refreshToken"] as? String, "r2", "the newer copy becomes the saved one")

        // A sign-in inside the folder as someone else is not this login's copy.
        try Data(#"{"claudeAiOauth":{"accessToken":"other","refreshToken":"r3","expiresAt":3000}}"#.utf8).write(to: folder.appendingPathComponent(".credentials.json"))
        try Data(#"{"oauthAccount":{"accountUuid":"someone-else"}}"#.utf8).write(to: folder.appendingPathComponent(".claude.json"))
        let still = await AccountService.freshest(account, vault: vault, directory: directory)
        XCTAssertEqual(JSON.object(still?["oauth"])?["refreshToken"] as? String, "r2")
    }

    func testAHopToALoginRunningInItsOwnTerminalIsRefused() async throws {
        let tool = FakeTool(["user": "bob"]), allowed = FakeTool(nil)
        let target = UUIDBox()
        let service = AccountService(directory: directory, adapters: [.codex: RefreshWatchingAdapter(tool: tool, allowed: allowed)],
                                     vault: Vault(store: MemorySecretStore()),
                                     sessions: { _ in target.id.map { [ToolSession(pid: 1, place: .own($0), startedAt: nil, directory: "/work")] } ?? [] })
        guard case .saved(let bob) = await service.syncLive(.codex) else { throw KeyhopError("bob") }
        tool.login = ["user": "ada"]
        guard case .saved(let ada) = await service.syncLive(.codex) else { throw KeyhopError("ada") }
        target.id = bob
        do {
            try await service.switchTo(bob)
            XCTFail("the hop should be refused")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("its own terminal"), error.localizedDescription)
        }
        XCTAssertEqual(tool.login?["user"], "ada")
        let runHere = try await service.prepareRun(ada)
        XCTAssertNil(runHere, "the login in use runs from its usual folder")
    }

    func testOnlyATurnedDownLoginIsSignedOutAndAFailedReadingKeepsTheLastOne() async throws {
        struct Failing: ProviderAdapter {
            let provider: Provider = .cursor
            let tool: FakeTool
            func readLive() async throws -> LiveLogin? {
                guard let secret = tool.login, let user = secret["user"] else { return nil }
                return LiveLogin(identity: user, email: "\(user)@example.com", plan: nil, secret: secret)
            }
            func apply(_ secret: Secret) async throws { tool.login = secret }
            func signOutLocally() async throws { tool.login = nil }
            func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
                if secret["user"] == "ada" { throw KeyhopError("Cursor rejected this login. Sign in again.", signedOut: true) }
                throw URLError(.timedOut)
            }
        }
        let tool = FakeTool(["user": "bob"])
        let service = AccountService(directory: directory, adapters: [.cursor: Failing(tool: tool)], vault: Vault(store: MemorySecretStore()), sessions: { _ in [] })
        guard case .saved(let bob) = await service.syncLive(.cursor) else { throw KeyhopError("bob") }
        tool.login = ["user": "ada"]
        guard case .saved(let ada) = await service.syncLive(.cursor) else { throw KeyhopError("ada") }
        let earlier = UsageSnapshot(windows: [UsageWindow(label: "Month", usedPercent: 30, resetsAt: nil, windowSeconds: nil)], error: nil, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let usage = await service.fetchUsage(previous: [bob: earlier])
        XCTAssertEqual(usage[ada]?.signedOut, true)
        XCTAssertNil(usage[bob]?.signedOut)
        XCTAssertNotNil(usage[bob]?.error)
        XCTAssertEqual(usage[bob]?.windows, earlier.windows)
    }

    func testAKeyhopRunNoteBlocksAHopToThatLoginForCodexToo() async throws {
        #if os(Windows)
        throw XCTSkip("Windows has no process list or file lock for Keyhop to read sessions with")
        #endif
        let tool = FakeTool(["user": "bob"]), allowed = FakeTool(nil)
        // The default session reader, pointed at this service's own run folders.
        let service = AccountService(directory: directory, adapters: [.codex: RefreshWatchingAdapter(tool: tool, allowed: allowed)],
                                     vault: Vault(store: MemorySecretStore()))
        guard case .saved(let bob) = await service.syncLive(.codex) else { throw KeyhopError("bob") }
        tool.login = ["user": "ada"]
        guard case .saved = await service.syncLive(.codex) else { throw KeyhopError("ada") }
        let folder = RunDirectories.folder(provider: .codex, account: bob, base: directory.appendingPathComponent("run"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let note = try XCTUnwrap(RunDirectories.markRunning(in: folder, directory: "/work"))
        let found = ToolSessions.running(.codex, runBase: directory.appendingPathComponent("run")) ?? []
        XCTAssertTrue(found.contains { $0.place == .own(bob) && $0.directory == "/work" })
        do {
            try await service.switchTo(bob)
            XCTFail("the hop should wait for the run to end")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("its own terminal"), error.localizedDescription)
        }
        try FileManager.default.removeItem(at: note)
        XCTAssertFalse((ToolSessions.running(.codex, runBase: directory.appendingPathComponent("run")) ?? []).contains { $0.place == .own(bob) })
    }

    func testALeaveIsKeptToTheSecondAboveAndTheLatestOneWins() async throws {
        XCTAssertEqual(AccountService.leaveTime(Date(timeIntervalSince1970: 100.2)), Date(timeIntervalSince1970: 101))
        let tool = FakeTool(["user": "bob"]), allowed = FakeTool(nil)
        let make = { AccountService(directory: self.directory, adapters: [.codex: RefreshWatchingAdapter(tool: tool, allowed: allowed)],
                                    vault: Vault(store: MemorySecretStore()), sessions: { _ in [] }) }
        let first = make()
        guard case .saved(let bob) = await first.syncLive(.codex) else { throw KeyhopError("bob") }
        tool.login = ["user": "ada"]
        _ = await first.syncLive(.codex)
        let early = await first.accounts.first { $0.id == bob }?.leftAt
        // Another process loads the file, and a later leave of bob lands on disk from elsewhere.
        var onDisk = AccountService.loadAccounts(from: directory)
        let later = Date(timeIntervalSince1970: ((early ?? Date()).timeIntervalSince1970 + 120).rounded(.up))
        if let index = onDisk.firstIndex(where: { $0.id == bob }) { onDisk[index].leftAt = later }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(onDisk).write(to: directory.appendingPathComponent("accounts.json"))
        _ = await first.fetchUsage(previous: [:])
        tool.login = ["user": "ada", "token": "2"]
        _ = await first.syncLive(.codex)
        XCTAssertEqual(AccountService.loadAccounts(from: directory).first { $0.id == bob }?.leftAt, later)
    }

    func testSessionsAreToldFromTheirCommandLines() {
        XCTAssertTrue(ToolSessions.isSession(of: .claude, commandLine: "claude --resume"))
        XCTAssertTrue(ToolSessions.isSession(of: .claude, commandLine: "/Users/a/.local/share/claude/versions/2.1.3 -p hi"))
        XCTAssertTrue(ToolSessions.isSession(of: .claude, commandLine: "node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"))
        XCTAssertFalse(ToolSessions.isSession(of: .claude, commandLine: "/Applications/Claude.app/Contents/MacOS/Claude"))
        XCTAssertFalse(ToolSessions.isSession(of: .claude, commandLine: "vim claude.md"))
        XCTAssertTrue(ToolSessions.isSession(of: .codex, commandLine: "/Users/a/.vscode/extensions/openai.chatgpt-1/bin/codex app-server"))
        XCTAssertTrue(ToolSessions.isSession(of: .codex, commandLine: "codex-aarch64-apple-darwin exec"))
        XCTAssertFalse(ToolSessions.isSession(of: .codex, commandLine: "keyhop switch codex"))
        XCTAssertFalse(ToolSessions.isSession(of: .gemini, commandLine: "gemini"))
    }

    func testTwoProcessesNeverRefreshTheSameLoginAtOnce() async throws {
        #if os(Windows)
        throw XCTSkip("Windows has no process list or file lock for Keyhop to read sessions with")
        #endif
        let id = UUID(), dir = directory!
        let inside = FakeTool(["n": "0", "max": "0"])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await RefreshLock.holding(id, in: dir) {
                        let n = Int(inside.login?["n"] ?? "0")! + 1
                        inside.login = ["n": "\(n)", "max": "\(max(n, Int(inside.login?["max"] ?? "0")!))"]
                        try await Task.sleep(for: .milliseconds(30))
                        inside.login = ["n": "\(n - 1)", "max": inside.login?["max"] ?? "0"]
                    }
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(inside.login?["max"], "1")
    }
}

final class UUIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UUID?
    var id: UUID? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}
