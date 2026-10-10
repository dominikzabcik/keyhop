import XCTest
@testable import Keyhop

final class MergeTests: XCTestCase {
    private var urlA: URL!
    private var urlB: URL!

    override func setUp() {
        let base = FileManager.default.temporaryDirectory
        urlA = base.appendingPathComponent("keyhop-merge-a-\(UUID().uuidString).sqlite")
        urlB = base.appendingPathComponent("keyhop-merge-b-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        for url in [urlA!, urlB!] {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
    }

    private func record(_ key: String, output: Int, at date: Date, account: UUID? = nil, project: String? = nil) -> UsageRecord {
        UsageRecord(key: key, provider: .claude, account: account, session: "s1", kind: .request, timestamp: date,
                    model: "claude-opus-5", tokens: TokenCounts(output: output), cost: 1, billed: nil, project: project)
    }

    func testEventsRoundTripWithAccountsMatchedByIdentity() async throws {
        let sender = try TrackerEngine(url: urlA)
        let receiver = try TrackerEngine(url: urlB)
        let start = Date().addingTimeInterval(-3600)
        let remote = UUID(), local = UUID()

        // The sender attributes by its switch history; the export carries the resolved identity.
        try await sender.noteActive(.claude, account: remote, at: start)
        try await sender.store([record("a", output: 100, at: start.addingTimeInterval(60), project: "keyhop"),
                                record("b", output: 300, at: start.addingTimeInterval(120))])
        let batch = try await sender.exportMergeEvents(after: 0, identities: [remote.uuidString: "anthropic-uuid-1|org"])
        XCTAssertEqual(batch.lines.count, 2)
        XCTAssertTrue(batch.lines[0].contains("anthropic-uuid-1|org"))

        let imported = try await receiver.importMergeLines(batch.lines, origin: "mac-studio",
                                                           accountsByIdentity: ["claude|anthropic-uuid-1|org": local.uuidString])
        XCTAssertEqual(imported, 2)
        let totals = try await receiver.accountTotals(in: DateInterval(start: start, end: Date()), sole: [:])
        XCTAssertEqual(totals.all.tokens.output, 400)
        XCTAssertEqual(totals.byAccount[local]?.tokens.output, 400)
    }

    func testASecondImportCountsNothingTwice() async throws {
        let sender = try TrackerEngine(url: urlA)
        let receiver = try TrackerEngine(url: urlB)
        try await sender.store([record("a", output: 100, at: Date())])
        let batch = try await sender.exportMergeEvents(after: 0, identities: [:])
        let first = try await receiver.importMergeLines(batch.lines, origin: "m", accountsByIdentity: [:])
        let second = try await receiver.importMergeLines(batch.lines, origin: "m", accountsByIdentity: [:])
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
    }

    func testImportedRowsAreNeverExportedAgain() async throws {
        let sender = try TrackerEngine(url: urlA)
        let receiver = try TrackerEngine(url: urlB)
        try await sender.store([record("remote", output: 100, at: Date())])
        let batch = try await sender.exportMergeEvents(after: 0, identities: [:])
        try await receiver.importMergeLines(batch.lines, origin: "m", accountsByIdentity: [:])
        try await receiver.store([record("local", output: 50, at: Date())])

        let out = try await receiver.exportMergeEvents(after: 0, identities: [:])
        XCTAssertEqual(out.lines.count, 1)
        XCTAssertTrue(out.lines[0].contains("\"local\""))
    }

    func testImportedRowsNeverFallBackToLocalSwitchHistory() async throws {
        let sender = try TrackerEngine(url: urlA)
        let receiver = try TrackerEngine(url: urlB)
        let start = Date().addingTimeInterval(-3600)
        let mine = UUID()
        // The receiving machine was on its own account the whole time.
        try await receiver.noteActive(.claude, account: mine, at: start)

        try await sender.store([record("foreign", output: 100, at: start.addingTimeInterval(60))])
        let batch = try await sender.exportMergeEvents(after: 0, identities: [:])
        try await receiver.importMergeLines(batch.lines, origin: "m", accountsByIdentity: [:])

        let totals = try await receiver.accountTotals(in: DateInterval(start: start, end: Date()), sole: [:])
        XCTAssertEqual(totals.all.tokens.output, 100)
        XCTAssertNil(totals.byAccount[mine], "foreign usage must not inherit this machine's switch history")
    }

    func testAnUnknownProviderSurvivesTheTripWithoutBreakingReports() async throws {
        let receiver = try TrackerEngine(url: urlB)
        let line = #"{"key":"future:1","provider":"somefuturetool","kind":"request","ts":\#(Date().timeIntervalSince1970),"model":"m","input":1,"cacheWrite":0,"cacheWrite1h":0,"cacheRead":0,"output":5,"reasoning":0,"cost":0}"#
        let imported = try await receiver.importMergeLines([line], origin: "m", accountsByIdentity: [:])
        XCTAssertEqual(imported, 1)
        let digest = try await receiver.digest(interval: DateInterval(start: Date().addingTimeInterval(-60), end: Date().addingTimeInterval(60)),
                                               previous: DateInterval(start: Date().addingTimeInterval(-120), duration: 60),
                                               bucket: .day, provider: nil, sole: [:])
        // Reports only count tools this build knows, and nothing crashes.
        XCTAssertTrue(digest.byProvider.isEmpty)
    }

    func testMalformedLinesAreSkipped() async throws {
        let receiver = try TrackerEngine(url: urlB)
        let lines = ["not json", #"{"provider":"claude"}"#, ""]
        let imported = try await receiver.importMergeLines(lines, origin: "m", accountsByIdentity: [:])
        XCTAssertEqual(imported, 0)
    }

    func testExportResumesFromTheLastRow() async throws {
        let sender = try TrackerEngine(url: urlA)
        try await sender.store([record("a", output: 1, at: Date())])
        let first = try await sender.exportMergeEvents(after: 0, identities: [:])
        try await sender.store([record("b", output: 2, at: Date())])
        let second = try await sender.exportMergeEvents(after: first.lastRow, identities: [:])
        XCTAssertEqual(second.lines.count, 1)
        XCTAssertTrue(second.lines[0].contains("\"b\""))
    }
}
