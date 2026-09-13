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
