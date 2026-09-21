import XCTest
@testable import Keyhop

/// Usage filed under the repository it happened in.
final class ProjectTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        // Under the temporary folder rather than home, so the walk can't meet a real repository.
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyhop-projects-\(UUID().uuidString)").standardizedFileURL
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func make(_ path: String) throws -> URL {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testWorkDeepInARepositoryIsFiledUnderTheRepository() throws {
        let repository = try make("atlas")
        try make("atlas/.git")
        let deep = try make("atlas/Sources/Importer")
        XCTAssertEqual(Projects.root(for: deep.path), repository.path)
        XCTAssertEqual(Projects.root(for: repository.path), repository.path)
    }

    func testAWorktreeIsItsOwnProject() throws {
        // A worktree marks itself with a `.git` file pointing back at the main clone.
        let worktree = try make("atlas-feature")
        try Data("gitdir: ../atlas/.git/worktrees/feature".utf8).write(to: worktree.appendingPathComponent(".git"))
        let inside = try make("atlas-feature/cloud")
        XCTAssertEqual(Projects.root(for: inside.path), worktree.path)
    }

    func testAFolderOutsideAnyRepositoryIsItsOwnProject() throws {
        let loose = try make("scratch/notes")
        XCTAssertEqual(Projects.root(for: loose.path), loose.path)
    }

    func testAFolderThatNoLongerExistsKeepsItsOwnPath() {
        let gone = folder.appendingPathComponent("deleted/long/ago").path
        XCTAssertEqual(Projects.root(for: gone), gone)
    }

    func testNothingRecordedMeansNoProject() {
        XCTAssertNil(Projects.root(for: nil))
        XCTAssertNil(Projects.root(for: "   "))
    }

    func testTwoProjectsWithOneNameAreToldApartByTheirParent() {
        let names = Projects.names(for: ["/work/app", "/side/app", "/work/atlas"])
        XCTAssertEqual(names["/work/app"], "work/app")
        XCTAssertEqual(names["/side/app"], "side/app")
        XCTAssertEqual(names["/work/atlas"], "atlas")
    }

    func testWorkFromTheHomeFolderIsCalledThatRatherThanAPersonsName() {
        let home = Files.home.standardizedFileURL.path
        XCTAssertEqual(Projects.names(for: [home, "/work/atlas"])[home], "Home folder")
        XCTAssertEqual(Projects.root(for: home), home)
    }

    func testClaudeCodeRecordsTheProjectItRanIn() throws {
        let repository = try make("keyhop")
        try make("keyhop/.git")
        let inside = try make("keyhop/cloud")
        let line = #"{"type":"assistant","cwd":"\#(inside.path)","requestId":"r","sessionId":"s","timestamp":"2026-09-10T08:00:00Z","message":{"id":"m","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        var state: [String: String] = [:]
        let record = try XCTUnwrap(LogFeed.claudeCode.parse(object, URL(fileURLWithPath: "/tmp/s.jsonl"), &state))
        XCTAssertEqual(record.project, repository.path)
    }

    func testCodexCarriesTheProjectFromTheTurnToItsUsage() throws {
        let repository = try make("keyhop")
        try make("keyhop/.git")
        let lines = [
            #"{"type":"turn_context","payload":{"model":"gpt-5","cwd":"\#(repository.path)"}}"#,
            #"{"type":"token_usage_record","timestamp":"2026-09-10T08:00:00Z","payload":{"response_id":"r1","usage":{"input_tokens":100,"output_tokens":20}}}"#,
        ]
        var state: [String: String] = [:]
        var records: [UsageRecord] = []
        for line in lines {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            if let record = LogFeed.codex.parse(object, URL(fileURLWithPath: "/tmp/rollout-x.jsonl"), &state) { records.append(record) }
        }
        XCTAssertEqual(records.first?.project, repository.path)
    }
}

/// The database side: the column, the history filled in after it, and the totals by project.
final class ProjectStorageTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-projects-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    private func record(_ key: String, project: String?, output: Int, at date: Date = Date().addingTimeInterval(-60)) -> UsageRecord {
        UsageRecord(key: key, provider: .claude, account: nil, session: nil, kind: .request, timestamp: date,
                    model: "claude-opus-5", tokens: TokenCounts(output: output), cost: 0, billed: nil, project: project)
    }

    func testUsageIsTotalledByProject() async throws {
        let engine = try TrackerEngine(url: url)
        try await engine.store([
            record("a", project: "/work/atlas", output: 100),
            record("b", project: "/work/atlas", output: 50),
            record("c", project: "/work/keyhop", output: 30),
            record("d", project: nil, output: 7),
        ])
        let now = Date()
        let day = DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(60))
        let digest = try await engine.digest(interval: day, previous: day, bucket: .hour, provider: nil, sole: [:])
        XCTAssertEqual(digest.byProject["/work/atlas"]?.tokens.output, 150)
        XCTAssertEqual(digest.byProject["/work/keyhop"]?.tokens.output, 30)
        XCTAssertEqual(digest.byProject[""]?.tokens.output, 7, "usage no tool placed in a folder is kept, under no project")
        XCTAssertEqual(digest.byProject.values.reduce(0) { $0 + $1.tokens.output }, digest.total.tokens.output)
    }

    /// History stored before projects existed gets its project on the next read, and nothing is
    /// counted twice or taken away by a read that knows less.
    func testAReadAgainFillsInTheProjectAndNothingElse() async throws {
        let engine = try TrackerEngine(url: url)
        try await engine.store([record("a", project: nil, output: 100)])
        try await engine.store([record("a", project: "/work/atlas", output: 999)])
        try await engine.store([record("a", project: nil, output: 1)])

        let now = Date()
        let day = DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(60))
        let digest = try await engine.digest(interval: day, previous: day, bucket: .hour, provider: nil, sole: [:])
        XCTAssertEqual(digest.total.tokens.output, 100, "a record seen again keeps its first counts")
        XCTAssertEqual(digest.byProject["/work/atlas"]?.tokens.output, 100)
        XCTAssertNil(digest.byProject[""], "a later read that knows no project doesn't take it away")
    }

    /// A database from before projects gains the column and forgets how far it had read, so the
    /// next pass fills its history in.
    func testAnOldDatabaseIsUpgradedAndReadAgain() async throws {
        let old = try Database(url: url)
        try old.script("""
            CREATE TABLE events (key TEXT PRIMARY KEY, provider TEXT NOT NULL, account TEXT, session TEXT, kind TEXT NOT NULL,
                ts REAL NOT NULL, model TEXT NOT NULL, input INTEGER NOT NULL, cache_write INTEGER NOT NULL,
                cache_write_1h INTEGER NOT NULL, cache_read INTEGER NOT NULL, output INTEGER NOT NULL, reasoning INTEGER NOT NULL,
                cost REAL NOT NULL, billed REAL);
            CREATE TABLE sources (path TEXT PRIMARY KEY, size INTEGER NOT NULL, offset INTEGER NOT NULL, state TEXT NOT NULL);
            INSERT INTO sources VALUES ('/logs/a.jsonl', 100, 100, '{}');
            INSERT INTO events VALUES ('a', 'claude', NULL, NULL, 'request', \(Date().timeIntervalSince1970 - 60), 'claude-opus-5', 0, 0, 0, 0, 40, 0, 0, NULL);
            """)

        let engine = try TrackerEngine(url: url)
        try await engine.store([record("a", project: "/work/atlas", output: 40)])
        let now = Date()
        let day = DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(60))
        let digest = try await engine.digest(interval: day, previous: day, bucket: .hour, provider: nil, sole: [:])
        XCTAssertEqual(digest.byProject["/work/atlas"]?.tokens.output, 40)

        let check = try Database(url: url, readOnly: true)
        var remembered = 0
        try check.query("SELECT COUNT(*) FROM sources") { remembered = Int($0.int(0)) }
        XCTAssertEqual(remembered, 0, "the logs are read again once, from the start")
    }

    /// Project paths are this computer's business. What goes to a linked website is per tool and
    /// per day, and never names a folder.
    func testDailyTotalsForTheWebsiteNeverCarryAProject() async throws {
        let engine = try TrackerEngine(url: url)
        try await engine.store([record("a", project: "/Users/someone/secret-client-work", output: 100)])
        let days = try await CloudSync.days(tracker: engine, since: Date().addingTimeInterval(-86400))
        let sent = String(decoding: try JSONEncoder().encode(days), as: UTF8.self)
        XCTAssertFalse(sent.contains("secret-client-work"))
        XCTAssertFalse(sent.contains("project"))
    }
}

/// Usage by the company that made the model, across tools.
final class MakerTests: XCTestCase {
    func testModelsAreFiledUnderTheirMaker() {
        XCTAssertEqual(Makers.maker(of: "claude-opus-5"), "Anthropic")
        XCTAssertEqual(Makers.maker(of: "anthropic/claude-sonnet-5"), "Anthropic")
        XCTAssertEqual(Makers.maker(of: "gpt-5.6-sol"), "OpenAI")
        XCTAssertEqual(Makers.maker(of: "openrouter/openai/o3"), "OpenAI")
        XCTAssertEqual(Makers.maker(of: "gemini-3.1-pro-preview"), "Google")
        XCTAssertEqual(Makers.maker(of: "glm-5"), "Z.ai")
        XCTAssertEqual(Makers.maker(of: "kimi-k2"), "Moonshot AI")
        XCTAssertEqual(Makers.maker(of: "composer-2"), "Cursor")
        XCTAssertEqual(Makers.maker(of: "something-new"), "Other")
    }

    func testOneModelThroughTwoToolsCountsOnceUnderItsMaker() {
        var digest = UsageDigest()
        let a = Totals(tokens: TokenCounts(output: 100), cost: 1, requests: 1)
        digest.byModel[ModelKey(provider: .claude, model: "claude-sonnet-5")] = a
        digest.byModel[ModelKey(provider: .opencode, model: "anthropic/claude-sonnet-5")] = a
        digest.byModel[ModelKey(provider: .opencode, model: "openai/gpt-5.6-sol")] = a
        let makers = Reports.makers(digest)
        XCTAssertEqual(makers.first?.maker, "Anthropic")
        XCTAssertEqual(makers.first?.models, ["claude-sonnet-5"])
        XCTAssertEqual(makers.first?.totals.tokens.output, 200)
        XCTAssertEqual(makers.last?.maker, "OpenAI")
    }
}
