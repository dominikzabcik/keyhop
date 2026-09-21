import XCTest
@testable import Keyhop

/// The ranges usage can be read over, and how each one is cut into chart steps.
final class RangeTests: XCTestCase {
    private func day(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    func testWordsAndDatesAreRead() {
        XCTAssertEqual(InsightsRange(argument: "90d"), .ninetyDays)
        XCTAssertEqual(InsightsRange(argument: "year"), .year)
        XCTAssertEqual(InsightsRange(argument: "all"), .all(since: nil))
        let picked = InsightsRange(argument: "2026-03-31..2026-01-01")
        XCTAssertEqual(picked?.argument, "2026-01-01..2026-03-31", "dates in either order are the same days")
        XCTAssertEqual(InsightsRange(argument: "2026-02-10")?.argument, "2026-02-10..2026-02-10")
        XCTAssertNil(InsightsRange(argument: "2026-02-30..2026-03-01"), "a day that doesn't exist isn't quietly moved")
        XCTAssertNil(InsightsRange(argument: "soon"))
    }

    func testChosenDaysIncludeBothEnds() {
        let range = InsightsRange(argument: "2026-01-01..2026-01-31")!
        let interval = range.interval(now: day("2026-09-21 12:00"))
        XCTAssertEqual(interval.start, day("2026-01-01 00:00"))
        XCTAssertEqual(interval.end, day("2026-02-01 00:00"))
        XCTAssertEqual(range.bucket, .day)
        XCTAssertEqual(range.title, "Jan 1 to Jan 31, 2026")
    }

    func testLongRangesUseWeeksThenMonths() {
        XCTAssertEqual(InsightsRange(argument: "2026-01-01..2026-01-02")!.bucket, .hour)
        XCTAssertEqual(InsightsRange(argument: "2025-01-01..2026-01-01")!.bucket, .week)
        XCTAssertEqual(InsightsRange(argument: "2021-01-01..2026-01-01")!.bucket, .month)
        XCTAssertEqual(InsightsRange.year.bucket, .week)
    }

    func testWeeklyRangesStartOnAMonday() {
        let interval = InsightsRange.year.interval(now: day("2026-09-21 12:00"))
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        XCTAssertEqual(calendar.component(.weekday, from: interval.start), 2)
        XCTAssertEqual(interval.start, calendar.startOfDay(for: interval.start))
    }

    func testEverythingHasNothingBeforeIt() {
        let now = day("2026-09-21 12:00")
        let range = InsightsRange.all(since: nil).resolved(firstUse: day("2026-06-10 09:30"))
        XCTAssertEqual(range.since, day("2026-06-10 00:00"))
        // Fifteen weeks of history is charted by the week, from that week's Monday.
        XCTAssertEqual(range.interval(now: now).start, day("2026-06-08 00:00"))
        XCTAssertEqual(range.previous(now: now).duration, 0)
        XCTAssertFalse(range.hasPrevious)
        XCTAssertEqual(range.argument, "all")
        XCTAssertEqual(InsightsRange.all(since: nil).resolved(firstUse: nil).interval(now: now).start,
                       Calendar.current.startOfDay(for: Date()), "no history yet is just today")
    }

    func testUsageIsGroupedByWeekAndMonthInTheDatabase() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-ranges-\(UUID().uuidString).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let engine = try TrackerEngine(url: url)
        func record(_ key: String, _ when: String) -> UsageRecord {
            UsageRecord(key: key, provider: .claude, account: nil, session: nil, kind: .request, timestamp: day(when),
                        model: "claude-opus-5", tokens: TokenCounts(output: 10), cost: 0, billed: nil)
        }
        // Wednesday and Sunday of one week, the Monday after, and a day in the next month.
        try await engine.store([record("a", "2026-09-16 10:00"), record("b", "2026-09-20 22:00"),
                                record("c", "2026-09-21 08:00"), record("d", "2026-10-02 08:00")])
        let span = DateInterval(start: day("2026-09-01 00:00"), end: day("2026-11-01 00:00"))

        let weeks = try await engine.digest(interval: span, previous: span, bucket: .week, provider: nil, sole: [:])
        let byWeek = Dictionary(grouping: weeks.points, by: \.start).mapValues { $0.reduce(0) { $0 + $1.totals.tokens.output } }
        XCTAssertEqual(byWeek[day("2026-09-14 00:00")], 20, "Wednesday and Sunday share their Monday")
        XCTAssertEqual(byWeek[day("2026-09-21 00:00")], 10)
        XCTAssertEqual(byWeek[day("2026-09-28 00:00")], 10)

        let months = try await engine.digest(interval: span, previous: span, bucket: .month, provider: nil, sole: [:])
        let byMonth = Dictionary(grouping: months.points, by: \.start).mapValues { $0.reduce(0) { $0 + $1.totals.tokens.output } }
        XCTAssertEqual(byMonth[day("2026-09-01 00:00")], 30)
        XCTAssertEqual(byMonth[day("2026-10-01 00:00")], 10)

        let first = try await engine.firstUse(provider: nil)
        XCTAssertEqual(first, day("2026-09-16 10:00"))
        let none = try await engine.firstUse(provider: .codex)
        XCTAssertNil(none)
    }
}
