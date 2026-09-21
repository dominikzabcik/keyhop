import XCTest
@testable import Keyhop

final class TrackerEngineTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-tests-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    private func record(_ key: String, provider: Provider = .claude, kind: UsageRecord.Kind = .request, session: String? = nil,
                        model: String = "claude-opus-5", at date: Date, output: Int, cost: Double = 0, account: UUID? = nil) -> UsageRecord {
        UsageRecord(key: key, provider: provider, account: account, session: session, kind: kind, timestamp: date,
                    model: model, tokens: TokenCounts(output: output), cost: cost, billed: nil)
    }

    func testUsageIsCreditedToTheAccountInUseAtTheTime() async throws {
        let engine = try TrackerEngine(url: url)
        let first = UUID(), second = UUID()
        let start = Date().addingTimeInterval(-3600)
        try await engine.noteActive(.claude, account: first, at: start)
        try await engine.noteActive(.claude, account: second, at: start.addingTimeInterval(1800))
        try await engine.store([
            record("a", at: start.addingTimeInterval(60), output: 100, cost: 1),
            record("b", at: start.addingTimeInterval(1900), output: 300, cost: 3),
        ])
        let totals = try await engine.accountTotals(in: DateInterval(start: start, end: Date()), sole: [:])
        XCTAssertEqual(totals.byAccount[first]?.tokens.output, 100)
        XCTAssertEqual(totals.byAccount[second]?.tokens.output, 300)
        XCTAssertEqual(totals.all.cost, 4, accuracy: 1e-9)
    }

    func testRepeatedSwitchesToTheSameAccountAddNoPeriods() async throws {
        let engine = try TrackerEngine(url: url)
        let account = UUID()
        let start = Date().addingTimeInterval(-600)
        try await engine.noteActive(.claude, account: account, at: start)
        try await engine.noteActive(.claude, account: account, at: start.addingTimeInterval(60))
        try await engine.store([record("a", at: start.addingTimeInterval(30), output: 10)])
        let totals = try await engine.accountTotals(in: DateInterval(start: start, end: Date()), sole: [:])
        XCTAssertEqual(totals.byAccount[account]?.requests, 1)
    }

    func testTheSameRecordIsStoredOnce() async throws {
        let engine = try TrackerEngine(url: url)
        let now = Date()
        try await engine.store([record("dup", at: now.addingTimeInterval(-10), output: 10)])
        try await engine.store([record("dup", at: now.addingTimeInterval(-10), output: 10)])
        let totals = try await engine.accountTotals(in: DateInterval(start: now.addingTimeInterval(-60), end: now), sole: [:])
        XCTAssertEqual(totals.all.requests, 1)
    }

    func testRunningTotalsAreSkippedWhereASessionHasPerResponseRecords() async throws {
        let engine = try TrackerEngine(url: url)
        let now = Date()
        try await engine.store([
            record("total-s", provider: .codex, kind: .runningTotal, session: "s", at: now.addingTimeInterval(-30), output: 500),
            record("resp-s", provider: .codex, kind: .request, session: "s", at: now.addingTimeInterval(-30), output: 400),
            record("total-t", provider: .codex, kind: .runningTotal, session: "t", at: now.addingTimeInterval(-30), output: 50),
        ])
        let totals = try await engine.accountTotals(in: DateInterval(start: now.addingTimeInterval(-60), end: now), sole: [:])
        XCTAssertEqual(totals.all.tokens.output, 450)
    }

    func testUnattributedUsageGoesToTheToolsOnlyAccount() async throws {
        let engine = try TrackerEngine(url: url)
        let only = UUID()
        let now = Date()
        try await engine.store([record("a", at: now.addingTimeInterval(-30), output: 70)])
        let totals = try await engine.accountTotals(in: DateInterval(start: now.addingTimeInterval(-60), end: now), sole: [.claude: only])
        XCTAssertEqual(totals.byAccount[only]?.tokens.output, 70)
    }

    func testDigestGroupsDatedModelNamesAndComparesThePreviousPeriod() async throws {
        let engine = try TrackerEngine(url: url)
        let now = Date()
        let interval = DateInterval(start: now.addingTimeInterval(-3600), end: now)
        let previous = DateInterval(start: now.addingTimeInterval(-7200), end: interval.start)
        try await engine.store([
            record("a", model: "claude-haiku-4-5-20251001", at: now.addingTimeInterval(-60), output: 5),
            record("b", model: "claude-haiku-4-5", at: now.addingTimeInterval(-120), output: 5),
            record("c", at: now.addingTimeInterval(-5000), output: 40),
        ])
        let digest = try await engine.digest(interval: interval, previous: previous, bucket: .hour, provider: nil, sole: [:])
        XCTAssertEqual(digest.byModel[ModelKey(provider: .claude, model: "claude-haiku-4-5")]?.tokens.output, 10)
        XCTAssertEqual(digest.byProvider[.claude]?.tokens.output, 10)
        XCTAssertEqual(digest.total.tokens.output, 10)
        XCTAssertEqual(digest.previous.tokens.output, 40)
        XCTAssertEqual(digest.points.count, 1)
        XCTAssertEqual(digest.points.first?.model, "claude-haiku-4-5")
        XCTAssertEqual(digest.points.first?.totals.tokens.output, 10)
    }

    func testSessionsAreNewestFirstAndSkipUnnamed() async throws {
        let engine = try TrackerEngine(url: url)
        let now = Date()
        try await engine.store([
            record("named", session: "chat-1", at: now.addingTimeInterval(-30), output: 20),
            record("anon", session: nil, at: now.addingTimeInterval(-20), output: 5),
        ])
        let found = try await engine.sessions(in: DateInterval(start: now.addingTimeInterval(-60), end: now), provider: nil, sole: [:])
        XCTAssertEqual(found.map(\.id), ["chat-1"])
        XCTAssertEqual(found.first?.totals.tokens.output, 20)
    }

    func testForecastProjectsWhenALimitRunsOut() async throws {
        let engine = try TrackerEngine(url: url)
        let account = UUID()
        let now = Date()
        func window(_ used: Double, resetsIn: TimeInterval = 5 * 3600) -> UsageWindow {
            UsageWindow(label: "5h", usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn), windowSeconds: 18000)
        }
        for (minutesAgo, used) in [(60.0, 40.0), (40, 50), (20, 60), (0, 70)] {
            try await engine.addSamples(account: account, windows: [window(used)], at: now.addingTimeInterval(-minutesAgo * 60))
        }
        let eta = try await engine.forecast(account: account, window: window(70), now: now)
        XCTAssertEqual(try XCTUnwrap(eta).timeIntervalSince(now), 3600, accuracy: 60)

        let resetsFirst = try await engine.forecast(account: account, window: window(70, resetsIn: 1800), now: now)
        XCTAssertNil(resetsFirst)
    }

    func testForecastIgnoresSamplesFromBeforeAReset() async throws {
        let engine = try TrackerEngine(url: url)
        let account = UUID()
        let now = Date()
        let window = UsageWindow(label: "5h", usedPercent: 12, resetsAt: now.addingTimeInterval(4 * 3600), windowSeconds: 18000)
        for (minutesAgo, used) in [(80.0, 90.0), (60, 97), (10, 5), (0, 12)] {
            try await engine.addSamples(account: account, windows: [UsageWindow(label: "5h", usedPercent: used, resetsAt: nil, windowSeconds: 18000)],
                                        at: now.addingTimeInterval(-minutesAgo * 60))
        }
        let eta = try await engine.forecast(account: account, window: window, now: now)
        XCTAssertNil(eta)
    }

    func testBudgetsRoundTrip() async throws {
        let engine = try TrackerEngine(url: url)
        let scope = Budget.scope(for: UUID())
        try await engine.setBudget(Budget(scope: scope, amount: 150, period: .week), scope: scope)
        let saved = try await engine.budgets()
        XCTAssertEqual(saved, [Budget(scope: scope, amount: 150, period: .week)])
        try await engine.setBudget(nil, scope: scope)
        let cleared = try await engine.budgets()
        XCTAssertTrue(cleared.isEmpty)
    }

    func testABudgetCountsWhatTheProviderChargedWhenItSaysSo() {
        // Cursor reports what it really charged for on-demand usage; the rest is valued at API prices.
        XCTAssertEqual(TrackerEngine.charged(Totals(cost: 4, billed: 11)), 11)
        XCTAssertEqual(TrackerEngine.charged(Totals(cost: 7, billed: 0)), 7)
        XCTAssertEqual(TrackerEngine.charged(Totals()), 0)
    }
}
