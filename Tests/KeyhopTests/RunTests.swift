import XCTest
@testable import Keyhop

/// `keyhop run`: a config folder per login, a folder that picks a login, and logs counted against it.
final class RunTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func account(_ provider: Provider) -> Account {
        Account(id: UUID(), provider: provider, identity: "a", email: "work@studio.dev", label: "Work", plan: nil, addedAt: Date())
    }

    func testAFolderPicksTheLoginItIsOrIsInside() {
        var map = RunMap()
        let work = UUID(), home = UUID()
        map.set("/code/work", account: work)
        map.set("/code", account: home)
        XCTAssertEqual(map.account(for: "/code/work"), work)
        XCTAssertEqual(map.account(for: "/code/work/api/src"), work)
        XCTAssertEqual(map.account(for: "/code/play"), home)
        XCTAssertEqual(map.account(for: "/code/workbench"), home, "a sibling that merely starts with the name is not inside")
        XCTAssertNil(map.account(for: "/elsewhere"))
        XCTAssertTrue(map.remove("/code/work/"))
        XCTAssertEqual(map.account(for: "/code/work"), home)
        XCTAssertEqual(RunMap.normalise("/code/work/"), "/code/work")
    }

    func testAClaudeLoginIsPlacedInItsOwnFolderWithoutTouchingTheUsualOne() throws {
        let claude = account(.claude)
        let secret: Secret = ["oauth": #"{"accessToken":"tok","refreshToken":"ref"}"#, "account": #"{"emailAddress":"work@studio.dev"}"#]
        let folder = try RunDirectories.prepare(account: claude, secret: secret, base: base)
        XCTAssertEqual(folder, base.appendingPathComponent("claude").appendingPathComponent(claude.id.uuidString))
        let credentials = try XCTUnwrap(JSON.object(try Data(contentsOf: folder.appendingPathComponent(".credentials.json"))))
        XCTAssertEqual((credentials["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String, "tok")
        let config = try XCTUnwrap(JSON.object(try Data(contentsOf: folder.appendingPathComponent(".claude.json"))))
        XCTAssertEqual((config["oauthAccount"] as? [String: Any])?["emailAddress"] as? String, "work@studio.dev")
        XCTAssertEqual(RunDirectories.all(base: base).map(\.account), [claude.id])
        XCTAssertEqual(RunDirectories.logRoots(provider: .claude, folder: folder), [folder.appendingPathComponent("projects", isDirectory: true)])

        let codex = account(.codex)
        let home = try RunDirectories.prepare(account: codex, secret: ["auth": #"{"tokens":{"access_token":"x"}}"#], base: base)
        XCTAssertEqual(String(decoding: try Data(contentsOf: home.appendingPathComponent("auth.json")), as: UTF8.self), #"{"tokens":{"access_token":"x"}}"#)
        XCTAssertThrowsError(try RunDirectories.prepare(account: account(.cursor), secret: [:], base: base))
    }

    func testLogsInsideALoginsFolderCountAgainstThatLogin() async throws {
        let claude = account(.claude)
        let folder = try RunDirectories.prepare(account: claude, secret: ["oauth": #"{"accessToken":"tok"}"#], base: base)
        let projects = folder.appendingPathComponent("projects/-tmp-demo", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","requestId":"r1","sessionId":"s1","timestamp":"2026-10-11T10:00:00Z","cwd":"/tmp/demo","message":{"id":"m1","model":"claude-opus-4-5","usage":{"input_tokens":100,"output_tokens":40}}}"# + "\n"
        try line.write(to: projects.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)

        let engine = try TrackerEngine(url: base.appendingPathComponent("usage.sqlite"))
        await engine.useRunFolders(base)
        // The machine's own logs are read too, so only the login's own count is checked.
        let added = try await engine.ingestLocalLogs()
        XCTAssertGreaterThanOrEqual(added, 1)
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_790_000_000), end: Date(timeIntervalSince1970: 1_800_000_000))
        let digest = try await engine.digest(interval: interval, previous: interval, bucket: .day, provider: .claude, sole: [:])
        XCTAssertEqual(digest.byAccount[AccountKey(provider: .claude, account: claude.id)]?.tokens.total, 140)
    }
}
