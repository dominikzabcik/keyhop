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
        var seen = allowed.login ?? [:]
        seen[secret["user"] ?? "?"] = allowRefresh ? "yes" : "no"
        allowed.login = seen
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
                                     vault: Vault(store: MemorySecretStore()), sessionsRunning: { _ in sessionRunning })
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
