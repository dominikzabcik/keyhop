import XCTest
@testable import Keyhop

/// Copilot and Windsurf, two tools Keyhop switches without local token transcripts.
///
/// Neither is driven by a real install here: Copilot runs against a stand-in `gh` so no real login
/// is touched, and Windsurf runs against a temporary `.codeium` folder. Both are checked hardest on
/// the thing that matters most, which is that they stay quiet when there is nothing to read.
final class NewProviderTests: XCTestCase {
    // MARK: Copilot

    /// A stand-in `gh`: it records what it was asked and answers with whatever the test sets.
    private final class FakeGH: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [String: (Int32, String)] = [:]
        private(set) var calls: [[String]] = []
        private(set) var stdins: [Data?] = []

        func answer(_ match: String, status: Int32 = 0, stdout: String = "") {
            lock.lock(); answers[match] = (status, stdout); lock.unlock()
        }

        var run: @Sendable ([String], Data?) throws -> ShellResult {
            { [self] arguments, stdin in
                lock.lock()
                calls.append(arguments)
                stdins.append(stdin)
                let key = answers.keys.first { arguments.joined(separator: " ").contains($0) }
                let (status, stdout) = key.flatMap { answers[$0] } ?? (1, "")
                lock.unlock()
                return ShellResult(status: status, stdout: Data(stdout.utf8), stderr: "")
            }
        }
    }

    /// The exact shape `gh auth status` prints, checked against a real gh holding two accounts.
    private let statusWithTwoAccounts = """
    github.com
      ✓ Logged in to github.com account octocat (keyring)
      - Active account: false
      - Git operations protocol: https
      - Token: gho_************************************
      - Token scopes: 'gist', 'read:org', 'repo'

      ✓ Logged in to github.com account hubot (keyring)
      - Active account: true
      - Git operations protocol: https
      - Token: gho_************************************
      - Token scopes: 'gist', 'read:org', 'repo', 'workflow'
    """

    func testTheActiveGitHubAccountIsTheOneMarkedActive() {
        XCTAssertEqual(CopilotAdapter.activeLogin(in: statusWithTwoAccounts), "hubot")
        // Signed out, or a status that names nobody, must read as nothing rather than as a guess.
        XCTAssertNil(CopilotAdapter.activeLogin(in: "You are not logged into any GitHub hosts."))
        XCTAssertNil(CopilotAdapter.activeLogin(in: ""))
        XCTAssertNil(CopilotAdapter.activeLogin(in: "  ✓ Logged in to github.com account octocat (keyring)"))
    }

    func testCopilotReadsTheLiveLoginThroughTheGitHubCLI() async throws {
        let gh = FakeGH()
        gh.answer("auth status", stdout: statusWithTwoAccounts)
        gh.answer("auth token", stdout: "gho_example\n")
        let live = try await CopilotAdapter(gh: gh.run).readLive()
        XCTAssertEqual(live?.identity, "hubot")
        XCTAssertEqual(live?.email, "@hubot")
        XCTAssertEqual(live?.secret["token"], "gho_example")
        XCTAssertEqual(live?.secret["login"], "hubot")
    }

    func testCopilotReadsNothingWhenGitHubHasNoLogin() async throws {
        let gh = FakeGH()
        gh.answer("auth status", status: 1)
        let quiet = try await CopilotAdapter(gh: gh.run).readLive()
        XCTAssertNil(quiet)

        // Signed in but with no token to hand back is still nothing, not a half-built account.
        let tokenless = FakeGH()
        tokenless.answer("auth status", stdout: statusWithTwoAccounts)
        tokenless.answer("auth token", status: 1)
        let half = try await CopilotAdapter(gh: tokenless.run).readLive()
        XCTAssertNil(half)
    }

    func testSwitchingToAnAccountGhAlreadyHoldsOnlySwitches() async throws {
        let gh = FakeGH()
        gh.answer("auth token", stdout: "gho_example\n")
        gh.answer("auth switch", stdout: "")
        try await CopilotAdapter(gh: gh.run).apply(["login": "hubot", "token": "gho_example"])
        XCTAssertFalse(gh.calls.contains { $0.contains("login") }, "a token gh already has must not be re-added")
        XCTAssertTrue(gh.calls.contains { $0.contains("switch") && $0.contains("hubot") })
    }

    func testSwitchingToAnAccountGhHasLostAddsTheTokenOnStandardInput() async throws {
        let gh = FakeGH()
        gh.answer("auth token", status: 1)
        gh.answer("auth login", stdout: "")
        gh.answer("auth switch", stdout: "")
        try await CopilotAdapter(gh: gh.run).apply(["login": "hubot", "token": "gho_example"])

        guard let index = gh.calls.firstIndex(where: { $0.contains("login") }) else {
            return XCTFail("the token should have been added back")
        }
        XCTAssertTrue(gh.calls[index].contains("--with-token"))
        // Never as an argument: that would put it in the process list for anyone to read.
        XCTAssertFalse(gh.calls[index].contains("gho_example"))
        XCTAssertEqual(gh.stdins[index], Data("gho_example".utf8))
    }

    func testADamagedCopilotLoginIsRefusedBeforeAnythingRuns() async {
        let gh = FakeGH()
        for broken in [["login": "hubot"], ["token": "gho_example"], ["login": "", "token": "gho_example"]] {
            do {
                try await CopilotAdapter(gh: gh.run).apply(broken)
                XCTFail("\(broken) should have been refused")
            } catch {
                XCTAssertTrue(gh.calls.isEmpty, "nothing should reach gh")
            }
        }
    }

    func testCopilotReadsReportedQuotaWithoutInventingMissingLanes() async throws {
        let body = #"{"copilot_plan":"pro","quota_reset_date":"2026-10-01","quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":225,"percent_remaining":75,"quota_id":"premium_interactions"},"chat":{"unlimited":true}}}"#
        let adapter = CopilotAdapter(gh: FakeGH().run, request: { _ in (Data(body.utf8), 200) })
        let report = try await adapter.fetchUsage(["token": "gho_example"], allowRefresh: true) { _ in }
        XCTAssertEqual(report.windows.map(\.label), ["Premium"])
        XCTAssertEqual(report.windows.first?.usedPercent, 25)
        XCTAssertNotNil(report.windows.first?.resetsAt)
        XCTAssertEqual(report.plan, "pro")
        XCTAssertEqual(Provider.copilot.limitsNote, "Token history stays with GitHub; Keyhop reads available plan quotas.")
    }

    // MARK: Windsurf

    private func windsurfFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-windsurf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testWindsurfStaysQuietWhenThereIsNothingToRead() async throws {
        let folder = try windsurfFolder()
        let adapter = WindsurfAdapter(directory: folder)
        let file = folder.appendingPathComponent("config.json")
        func read() async throws -> LiveLogin? { try await adapter.readLive() }

        // No file at all.
        var live = try await read()
        XCTAssertNil(live)
        // A file that isn't JSON.
        try Data("not json".utf8).write(to: file)
        live = try await read()
        XCTAssertNil(live)
        // Settings, but no login in them: Windsurf simply doesn't appear.
        try Data(#"{"telemetry": false}"#.utf8).write(to: file)
        live = try await read()
        XCTAssertNil(live)
        try Data(#"{"apiKey": ""}"#.utf8).write(to: file)
        live = try await read()
        XCTAssertNil(live)
    }

    func testWindsurfReadsALoginAndSwitchesItBack() async throws {
        let folder = try windsurfFolder()
        let adapter = WindsurfAdapter(directory: folder)
        let file = folder.appendingPathComponent("config.json")
        try Data(#"{"apiKey":"key-one","email":"me@example.com","planName":"Pro","telemetry":false}"#.utf8).write(to: file)

        let live = try await adapter.readLive()
        XCTAssertEqual(live?.identity, "me@example.com")
        XCTAssertEqual(live?.email, "me@example.com")
        XCTAssertEqual(live?.plan, "Pro")
        XCTAssertTrue(live?.emailTrusted == true)

        try Data(#"{"apiKey":"key-two"}"#.utf8).write(to: file)
        try await adapter.apply(live!.secret)
        let back = JSON.object(try Data(contentsOf: file))
        XCTAssertEqual(back?["apiKey"] as? String, "key-one")
        // Everything else in the file comes back with it, not just the key.
        XCTAssertEqual(back?["telemetry"] as? Bool, false)
    }

    func testAWindsurfLoginWithNoAddressIsNamedWithoutClaimingOne() async throws {
        let folder = try windsurfFolder()
        try Data(#"{"apiKey":"key-one"}"#.utf8).write(to: folder.appendingPathComponent("config.json"))
        let live = try await WindsurfAdapter(directory: folder).readLive()
        XCTAssertEqual(live?.identity, WindsurfAdapter.fingerprint("key-one"))
        XCTAssertEqual(live?.email, "Windsurf account")
        XCTAssertFalse(live?.emailTrusted == true)
        // The name is a digest, never the key itself.
        XCTAssertFalse(live!.identity.contains("key-one"))
        XCTAssertTrue(live!.identity.hasPrefix("windsurf-"))
    }

    func testSigningOutOfWindsurfTakesOnlyTheKey() async throws {
        let folder = try windsurfFolder()
        let file = folder.appendingPathComponent("config.json")
        try Data(#"{"apiKey":"key-one","telemetry":false}"#.utf8).write(to: file)
        try await WindsurfAdapter(directory: folder).signOutLocally()

        let left = JSON.object(try Data(contentsOf: file))
        XCTAssertNil(left?["apiKey"])
        XCTAssertEqual(left?["telemetry"] as? Bool, false, "settings this person chose must survive")
    }

    func testADamagedWindsurfLoginIsRefused() async throws {
        let folder = try windsurfFolder()
        let adapter = WindsurfAdapter(directory: folder)
        for broken in [["credentials": "not json"], ["credentials": #"{"apiKey":""}"#], [:]] {
            do {
                try await adapter.apply(broken)
                XCTFail("\(broken) should have been refused")
            } catch {}
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("config.json").path))
    }

    // MARK: Both

    func testEveryToolHasAnAdapterAndAMark() {
        for provider in Provider.allCases {
            XCTAssertNotNil(Adapters.all[provider], "\(provider.rawValue) needs an adapter")
            XCTAssertFalse(ProviderMarks.path(for: provider).isEmpty, "\(provider.rawValue) needs a mark")
            XCTAssertFalse(provider.name.isEmpty)
            XCTAssertFalse(provider.shortName.isEmpty)
        }
    }
}

// MARK: Tools that hold several logins at once

/// A stand-in for gh: several logins held together, one of them active, and signing out does nothing.
final class ManyLogins: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [String] = []
    private var current: String?

    func add(_ user: String, active: Bool = true) {
        lock.lock(); held.append(user); if active { current = user }; lock.unlock()
    }

    func snapshot() -> (held: [String], active: String?) {
        lock.lock(); defer { lock.unlock() }
        return (held, current)
    }

    func activate(_ user: String) {
        lock.lock(); current = user; lock.unlock()
    }
}

struct ManyLoginsAdapter: ProviderAdapter {
    let provider = Provider.copilot
    let tool: ManyLogins

    private func live(_ user: String) -> LiveLogin {
        LiveLogin(identity: user, email: "@\(user)", plan: nil, secret: ["login": user, "token": "t-\(user)"])
    }

    func readLive() async throws -> LiveLogin? { tool.snapshot().active.map(live) }
    func readAllLogins() async throws -> [LiveLogin] { tool.snapshot().held.map(live) }
    func apply(_ secret: Secret) async throws { if let user = secret["login"] { tool.activate(user) } }
    func signOutLocally() async throws {}
    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        LimitReport(windows: [], plan: nil)
    }
}

final class ManyLoginsServiceTests: XCTestCase {
    private func service(_ tool: ManyLogins) throws -> AccountService {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-many-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AccountService(directory: directory, adapters: [.copilot: ManyLoginsAdapter(tool: tool)],
                              vault: Vault(store: MemorySecretStore()))
    }

    func testEveryLoginTheToolHoldsIsSavedWithoutChangingTheActiveOne() async throws {
        let tool = ManyLogins()
        tool.add("octocat", active: false)
        tool.add("hubot")
        let service = try service(tool)

        _ = await service.syncLive(.copilot)
        let saved = await service.accounts.map(\.identity).sorted()
        XCTAssertEqual(saved, ["hubot", "octocat"])
        let activeID = await service.active[.copilot]
        let active = await service.accounts.first { $0.id == activeID }
        XCTAssertEqual(active?.identity, "hubot")

        // A second refresh finds nothing new and saves nothing twice.
        _ = await service.syncLive(.copilot)
        let count = await service.accounts.count
        XCTAssertEqual(count, 2)
    }

    func testAddingWaitsForANewLoginRatherThanReturningTheOneAlreadyInUse() async throws {
        let tool = ManyLogins()
        tool.add("hubot")
        let service = try service(tool)
        _ = await service.syncLive(.copilot)

        // gh keeps hubot active the whole time, so "signing out" changes nothing here.
        _ = try await service.signOutForAdding(.copilot)
        let waiting = Task { await service.waitForLogin(.copilot, attempts: 50, interval: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        tool.add("octocat")   // what `gh auth login` does: a new account, now active
        let result = await waiting.value

        guard case .saved(let id)? = result?.outcome else { return XCTFail("expected the new login, got \(String(describing: result))") }
        let account = await service.accounts.first { $0.id == id }
        XCTAssertEqual(account?.identity, "octocat")
        XCTAssertEqual(result?.alreadySaved, false)
    }

    func testAddingGivesUpQuietlyWhenNoNewLoginArrives() async throws {
        let tool = ManyLogins()
        tool.add("hubot")
        let service = try service(tool)
        _ = await service.syncLive(.copilot)
        let result = await service.waitForLogin(.copilot, attempts: 3, interval: .milliseconds(10))
        XCTAssertNil(result, "the account already in use must not be reported as the one just added")
    }
}

final class CopilotParsingTests: XCTestCase {
    func testEveryGitHubAccountIsListedWithTheActiveOneMarked() {
        let status = """
        github.com
          ✓ Logged in to github.com account octocat (keyring)
          - Active account: false
          ✓ Logged in to github.com account hubot (keyring)
          - Active account: true
        """
        let logins = CopilotAdapter.logins(in: status)
        XCTAssertEqual(logins.map(\.login), ["octocat", "hubot"])
        XCTAssertEqual(logins.map(\.active), [false, true])
    }

    func testOnlyRealGitHubNamesAreEverHandedToGh() {
        for good in ["hubot", "octo-cat", "a", "A1", String(repeating: "x", count: 39)] {
            XCTAssertTrue(CopilotAdapter.isGitHubLogin(good), good)
        }
        // A leading dash would read as an option on gh's command line.
        for bad in ["", "-rf", "--user", "trail-", "has space", "semi;colon", "dot.name", "ünïcode",
                    String(repeating: "x", count: 40), "a\nb"] {
            XCTAssertFalse(CopilotAdapter.isGitHubLogin(bad), bad)
        }
        let status = "  ✓ Logged in to github.com account --user (keyring)\n  - Active account: true"
        XCTAssertTrue(CopilotAdapter.logins(in: status).isEmpty, "a name gh could misread must be dropped")
    }

    func testAnOptionShapedLoginIsRefusedBeforeGhRuns() async {
        var ran = false
        let adapter = CopilotAdapter(gh: { _, _ in ran = true; return ShellResult(status: 0, stdout: Data(), stderr: "") })
        do {
            try await adapter.apply(["login": "--help", "token": "t"])
            XCTFail("should have been refused")
        } catch {}
        XCTAssertFalse(ran)
    }

    func testSigningOutOfCopilotTouchesNothing() async throws {
        var calls = 0
        let adapter = CopilotAdapter(gh: { _, _ in calls += 1; return ShellResult(status: 0, stdout: Data(), stderr: "") })
        try await adapter.signOutLocally()
        XCTAssertEqual(calls, 0, "gh auth logout would revoke the saved token")
    }
}

final class BlockerTests: XCTestCase {
    private struct BlockedAdapter: ProviderAdapter {
        let provider = Provider.copilot
        func readLive() async throws -> LiveLogin? { nil }
        func apply(_ secret: Secret) async throws {}
        func signOutLocally() async throws {}
        func blocker() -> String? { "Install gh, then run `gh auth login`." }
        func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
            LimitReport(windows: [], plan: nil)
        }
    }

    func testAddingAToolThatCannotWorkFailsAtOnceAndSaysWhy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-blocked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = AccountService(directory: directory, adapters: [.copilot: BlockedAdapter()], vault: Vault(store: MemorySecretStore()))
        do {
            _ = try await service.signOutForAdding(.copilot)
            XCTFail("a blocked tool must not start a ten-minute wait")
        } catch {
            // Backticks are for Markdown; a plain message reads cleanly in a terminal and a notice.
            XCTAssertEqual(error.localizedDescription, "Install gh, then run gh auth login.")
        }
    }

    func testOnlyToolsThatHoldManyLoginsSaySo() async {
        XCTAssertTrue(CopilotAdapter().holdsManyLogins)
        XCTAssertFalse(WindsurfAdapter().holdsManyLogins)
        XCTAssertFalse(GeminiAdapter().holdsManyLogins)
        // A stand-in gh is never "missing".
        XCTAssertNil(CopilotAdapter(gh: { _, _ in ShellResult(status: 0, stdout: Data(), stderr: "") }).blocker())
        XCTAssertNil(WindsurfAdapter().blocker())
    }

    func testDoctorOwnsUpWhenWindsurfMayBeKeyhopsMiss() {
        XCTAssertTrue(ToolDetection.note(.windsurf)?.contains("doesn't read yet") == true)
        for provider in Provider.allCases where provider != .windsurf {
            XCTAssertNil(ToolDetection.note(provider))
        }
    }
}
