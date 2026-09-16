import XCTest
@testable import Keyhop

/// Copilot and Windsurf, the two tools Keyhop switches without counting their usage.
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

    func testCopilotReportsNoLimitsRatherThanGuessingAtOne() async throws {
        let report = try await CopilotAdapter(gh: FakeGH().run)
            .fetchUsage(["token": "gho_example"], allowRefresh: true) { _ in }
        XCTAssertTrue(report.windows.isEmpty)
        XCTAssertNil(report.plan)
        XCTAssertEqual(Provider.copilot.limitsNote, "Usage and quota stay with GitHub; Keyhop switches the account.")
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
