import XCTest
@testable import Keyhop

final class QuotaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func account(_ index: Int, _ provider: Provider, _ email: String, label: String? = nil) -> Account {
        Account(id: UUID(uuidString: String(format: "0000AAAA-0000-4000-8000-%012d", index))!, provider: provider,
                identity: email, email: email, label: label, plan: "Pro", addedAt: now)
    }

    private func window(_ label: String, _ used: Double, in seconds: TimeInterval?, length: TimeInterval?) -> UsageWindow {
        UsageWindow(label: label, usedPercent: used, resetsAt: seconds.map { now.addingTimeInterval($0) }, windowSeconds: length)
    }

    private func input(_ account: Account, _ windows: [UsageWindow], error: String? = nil) -> QuotaInput {
        QuotaInput(account: account, snapshot: UsageSnapshot(windows: windows, error: error, fetchedAt: now), active: false)
    }

    func testPoolsAddUpTheCountedLogins() {
        let personal = account(1, .claude, "me@personal.dev")
        let work = account(2, .claude, "work@studio.dev")
        let codex = account(3, .codex, "me@personal.dev")
        let report = QuotaReport.build(accounts: [
            input(codex, [window("5h", 10, in: 3600, length: 18000)]),
            input(personal, [window("5h", 40, in: 3600, length: 18000), window("Week", 20, in: 86400, length: 604_800)]),
            input(work, [window("Week", 70, in: 86400, length: 604_800)]),
        ], samples: [], now: now)

        XCTAssertEqual(report.pools.map(\.tool), ["all", "claude", "codex"])
        XCTAssertEqual(report.pools[0].capacity, 300)
        XCTAssertEqual(report.pools[0].remaining, 180)
        XCTAssertEqual(report.pools[1].name, "Claude Code")
        XCTAssertEqual(report.pools[1].capacity, 200)
        XCTAssertEqual(report.pools[1].remaining, 90)
        XCTAssertEqual(report.pools[2].remaining, 90)
        // By tool, then the login with the least left first.
        XCTAssertEqual(report.accounts.map(\.email), ["work@studio.dev", "me@personal.dev", "me@personal.dev"])
        XCTAssertEqual(report.accounts[1].binding, "5h")
        XCTAssertEqual(report.step, 1800)
        XCTAssertEqual(report.pools[0].past.count, 7 * 48 + 1)
        XCTAssertEqual(report.pools[0].forecast.count, 7 * 48 + 1)
        XCTAssertEqual(report.pools[0].forecast.first, 180)
        XCTAssertEqual(report.pools[0].past.last, 180)
        XCTAssertEqual(report.pastStart, now.addingTimeInterval(-7 * 86400))
    }

    func testAResetStepsTheForecastUpAndIsTheNextReset() throws {
        let personal = account(1, .claude, "me@personal.dev", label: "Personal")
        // Four hours into the window at 90%: 22.5% an hour, so it fills in under half an hour, then resets at one hour.
        let report = QuotaReport.build(accounts: [
            input(personal, [window("5h", 90, in: 3600, length: 18000), window("Week", 30, in: 3 * 86400, length: 604_800)]),
        ], samples: [], now: now)
        let login = try XCTUnwrap(report.accounts.first)
        XCTAssertEqual(login.drainPerHour, 22.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(login.emptyAt).timeIntervalSince(now), 10 / 22.5 * 3600, accuracy: 1)
        XCTAssertEqual(login.forecast[0], 10)
        XCTAssertEqual(login.forecast[1], 0)
        XCTAssertGreaterThan(login.forecast[2], 69)

        let pool = report.pools[0]
        let reset = try XCTUnwrap(pool.nextReset)
        XCTAssertEqual(reset.at, now.addingTimeInterval(3600))
        XCTAssertEqual(reset.account, "Personal")
        XCTAssertEqual(reset.tool, "claude")
        // The weekly window has climbed a little by then and now binds.
        XCTAssertEqual(reset.gain, 100 - 30 - 30.0 / 96, accuracy: 0.2)
        XCTAssertEqual(try XCTUnwrap(pool.emptyAt).timeIntervalSince(now), 10 / 22.5 * 3600, accuracy: 1)
    }

    func testASlowPoolOfOneEmptiesWhenItsLoginDoes() throws {
        let codex = account(1, .codex, "me@personal.dev")
        // 99% four days into a week: about 1% an hour, so the last half point takes half an hour.
        let report = QuotaReport.build(accounts: [input(codex, [window("Week", 99, in: 3 * 86400, length: 604_800)])], samples: [], now: now)
        let login = try XCTUnwrap(report.accounts.first)
        XCTAssertEqual(try XCTUnwrap(login.emptyAt).timeIntervalSince(now), 1 / (99.0 / 96) * 3600, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(report.pools[0].emptyAt).timeIntervalSince(try XCTUnwrap(login.emptyAt)), 0, accuracy: 1)
    }

    func testAnExpiredLoginIsListedButNotCounted() {
        let good = account(1, .cursor, "me@personal.dev")
        let expired = account(2, .cursor, "spare@personal.dev")
        let report = QuotaReport.build(accounts: [
            input(good, [window("Auto", 60, in: 86400, length: 2_592_000)]),
            input(expired, [window("Auto", 10, in: 86400, length: 2_592_000)], error: "Login expired."),
        ], samples: [], now: now)
        XCTAssertEqual(report.accounts.count, 2)
        XCTAssertEqual(report.accounts.first { $0.email == "spare@personal.dev" }?.counted, false)
        XCTAssertEqual(report.accounts.first { $0.email == "spare@personal.dev" }?.error, "Login expired.")
        XCTAssertEqual(report.pools[0].accounts, 1)
        XCTAssertEqual(report.pools[0].capacity, 100)
        XCTAssertEqual(report.pools[0].remaining, 40)
    }

    func testAFullWindowIsBackAtItsReset() throws {
        let codex = account(1, .codex, "me@personal.dev")
        let report = QuotaReport.build(accounts: [
            input(codex, [window("5h", 20, in: 7200, length: 18000), window("Week", 100, in: 2 * 86400, length: 604_800)]),
        ], samples: [], now: now)
        let login = try XCTUnwrap(report.accounts.first)
        XCTAssertEqual(login.remaining, 0)
        XCTAssertEqual(login.binding, "Week")
        XCTAssertEqual(login.backAt, now.addingTimeInterval(2 * 86400))
        XCTAssertNil(login.emptyAt)
        XCTAssertNil(report.pools[0].emptyAt)
        XCTAssertEqual(report.pools[0].nextReset?.at, now.addingTimeInterval(2 * 86400))
        // By then the 5-hour window is an hour into another cycle at 20 over 3 hours.
        XCTAssertEqual(report.pools[0].nextReset?.gain ?? 0, 100 - 20.0 / 3, accuracy: 0.2)
    }

    func testThePastReadsSamplesAndAPassedResetEmptiesTheWindow() throws {
        let personal = account(1, .claude, "me@personal.dev")
        let samples = [
            LimitSample(account: personal.id, label: "5h", used: 30, resets: now.addingTimeInterval(-5 * 3600), ts: now.addingTimeInterval(-6 * 3600)),
            LimitSample(account: personal.id, label: "5h", used: 50, resets: now.addingTimeInterval(2 * 3600), ts: now.addingTimeInterval(-3 * 3600)),
        ]
        let report = QuotaReport.build(accounts: [input(personal, [window("5h", 60, in: 2 * 3600, length: 18000)])],
                                       samples: samples, now: now, past: 8 * 3600, ahead: 3600)
        XCTAssertEqual(report.pastStart, now.addingTimeInterval(-8 * 3600))
        let login = try XCTUnwrap(report.accounts.first)
        let pool = report.pools[0]
        func at(_ hoursAgo: Double) -> Int { Int((8 - hoursAgo) * 2) }
        XCTAssertNil(login.past[at(7)])
        XCTAssertNil(pool.past[at(7)])
        XCTAssertEqual(login.past[at(6)], 70)
        XCTAssertEqual(login.past[at(5.5)], 70)
        XCTAssertEqual(login.past[at(5)], 100)
        XCTAssertEqual(login.past[at(3)], 50)
        XCTAssertEqual(login.past.last, 40)
        XCTAssertEqual(pool.past[at(5)], 100)
        XCTAssertEqual(pool.past.last, 40)
        // Climbing from 0 to 50 in half an hour is 100% an hour; the reset itself drains nothing.
        XCTAssertEqual(pool.drain[at(3)], 100)
        XCTAssertEqual(pool.drain[at(5)], 0)
        XCTAssertNil(pool.drain[at(7)])
        XCTAssertEqual(report.forecastStart, now)
        XCTAssertEqual(pool.forecast.count, 3)
    }

    func testTheRateNowComesFromRecentSamplesSinceTheLastReset() throws {
        let personal = account(1, .claude, "me@personal.dev")
        var samples = [LimitSample(account: personal.id, label: "5h", used: 95, resets: nil, ts: now.addingTimeInterval(-2 * 3600))]
        for minute in stride(from: 60, through: 0, by: -10) {
            samples.append(LimitSample(account: personal.id, label: "5h", used: 32 - Double(minute) / 5, resets: nil,
                                       ts: now.addingTimeInterval(-Double(minute) * 60)))
        }
        let report = QuotaReport.build(accounts: [input(personal, [window("5h", 32, in: 3 * 3600, length: 18000)])],
                                       samples: samples, now: now)
        let login = try XCTUnwrap(report.accounts.first)
        XCTAssertEqual(login.windows[0].drainPerHour, 12, accuracy: 0.01)
        XCTAssertEqual(login.drainPerHour, 12, accuracy: 0.01)
        XCTAssertEqual(login.forecast[2], 100 - 32 - 12, accuracy: 0.1)
        XCTAssertEqual(login.lastSeen, now)
    }

    func testTheJSONCarriesEveryKeyTheWindowReads() throws {
        let personal = account(1, .claude, "me@personal.dev")
        let report = QuotaReport.build(accounts: [input(personal, [window("Week", 10, in: nil, length: nil)])], samples: [], now: now)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Output.encoder.encode(report)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["generatedAt", "step", "pastStart", "forecastStart", "pools", "accounts"])
        let pool = try XCTUnwrap((object["pools"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(pool.keys), ["tool", "name", "accounts", "capacity", "remaining", "drainPerHour", "emptyAt", "nextReset",
                                        "past", "forecast", "drain"])
        XCTAssertTrue(pool["nextReset"] is NSNull)
        let login = try XCTUnwrap((object["accounts"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(login.keys), ["id", "tool", "toolName", "name", "email", "plan", "active", "error", "counted", "remaining",
                                         "binding", "drainPerHour", "emptyAt", "backAt", "lastSeen", "windows", "past", "forecast"])
        let window = try XCTUnwrap((login["windows"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(window.keys), ["label", "usedPercent", "resetsAt", "windowSeconds", "drainPerHour", "emptyAt"])
        XCTAssertTrue((pool["past"] as? [Any])?.first is NSNull)
    }

    func testTheSampleEndsOnItsOwnSnapshot() throws {
        let report = SampleData.quota(now: now)
        let overview = SampleData.overview(now: now)
        for login in report.accounts where login.counted {
            let used = try XCTUnwrap(overview.usage[login.id]).windows.map(\.usedPercent).max() ?? 0
            XCTAssertEqual(login.remaining, 100 - used, accuracy: 0.05)
            XCTAssertEqual(login.past.last ?? nil, login.remaining)
            XCTAssertNotNil(login.past.first ?? nil, "\(login.name) has a week of history")
        }
        XCTAssertEqual(report.accounts.filter { !$0.counted }.map(\.email), ["spare@personal.dev"])
        XCTAssertEqual(report.pools[0].past.last ?? nil, report.pools[0].remaining)
        XCTAssertNotNil(report.pools[0].nextReset)
        XCTAssertFalse(Reports.forecast(report, tool: nil).isEmpty)
    }

    func testTheTrackerHandsBackItsKeptSamples() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-quota-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tracker = try TrackerEngine(url: folder.appendingPathComponent("usage.sqlite"))
        let id = UUID()
        let time = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())
        try await tracker.addSamples(account: id, windows: [UsageWindow(label: "5h", usedPercent: 12, resetsAt: time.addingTimeInterval(3600), windowSeconds: 18000),
                                                            UsageWindow(label: "Week", usedPercent: 40, resetsAt: nil, windowSeconds: nil)],
                                     at: time.addingTimeInterval(-600))
        try await tracker.addSamples(account: id, windows: [UsageWindow(label: "5h", usedPercent: 15, resetsAt: time.addingTimeInterval(3600), windowSeconds: 18000)],
                                     at: time)
        let samples = try await tracker.limitSamples(since: time.addingTimeInterval(-3600))
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.last, LimitSample(account: id, label: "5h", used: 15, resets: time.addingTimeInterval(3600), ts: time))
        XCTAssertEqual(samples.first { $0.label == "Week" }?.resets, nil)
        let recent = try await tracker.limitSamples(since: time.addingTimeInterval(-60))
        XCTAssertEqual(recent.count, 1)
    }
}
