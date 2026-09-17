import XCTest
@testable import Keyhop

final class KeyhopTests: XCTestCase {
    func testTokenFormatting() {
        XCTAssertEqual(Format.tokens(999), "999")
        XCTAssertEqual(Format.tokens(1_000), "1K")
        XCTAssertEqual(Format.tokens(1_500_000), "1.5M")
        XCTAssertEqual(Format.tokens(4_140_000_000), "4.1B")
    }

    func testTierFormatting() {
        XCTAssertEqual(Format.tier(.init(key: "platinum", name: "Platinum", division: 2)), "Platinum II")
        XCTAssertEqual(Format.tier(.init(key: "master", name: "Master", division: nil)), "Master")
    }

    func testProfileURL() {
        let link = PhoneLink(server: "https://keyhop.app", login: "mira", name: nil)
        XCTAssertEqual(link.profileURL?.absoluteString, "https://keyhop.app/u/mira")
    }

    @MainActor
    func testVerificationURLStaysOnTheConfiguredServer() {
        XCTAssertEqual(
            Store.verificationURL("https://keyhop.app/link?code=ABCD-2345", server: "https://keyhop.app")?.host,
            "keyhop.app"
        )
        XCTAssertNil(Store.verificationURL("https://example.com/link", server: "https://keyhop.app"))
        XCTAssertNil(Store.verificationURL("javascript:alert(1)", server: "https://keyhop.app"))
    }

    // MARK: Limits

    private func limit(_ account: String, _ tool: String, _ label: String?, _ window: String,
                       _ used: Double, resetsIn: TimeInterval?, from now: Date) -> CloudLimit {
        CloudLimit(accountKey: account, tool: tool, label: label, windowLabel: window, usedPercent: used,
                   resetsAt: resetsIn.map { Int(now.addingTimeInterval($0).timeIntervalSince1970) })
    }

    func testAccountsReadFullestFirstAndNameThemselvesWithoutAnEmail() {
        let now = Date()
        let accounts = LimitAccount.group([
            limit("roomy", "claude", "Studio", "Week", 41, resetsIn: 400_000, from: now),
            limit("roomy", "claude", "Studio", "5h", 18, resetsIn: 9_000, from: now),
            limit("tight", "codex", nil, "5h", 96, resetsIn: 1_400, from: now),
            limit("tight", "codex", nil, "Week", 62, resetsIn: 190_000, from: now),
        ])
        XCTAssertEqual(accounts.map(\.key), ["tight", "roomy"])
        XCTAssertEqual(accounts.first?.name, "Codex")
        XCTAssertEqual(accounts.last?.name, "Claude Code · Studio")
        // Within an account the tightest window leads, so the one that stops work reads first.
        XCTAssertEqual(accounts.first?.windows.map(\.windowLabel), ["5h", "Week"])
        XCTAssertEqual(accounts.first?.tightest?.usedPercent, 96)
    }

    func testOnlyANearlySpentLimitIsWorthAnnouncing() {
        let now = Date()
        let alerts = AlertPlan.alerts(
            limits: [
                limit("tight", "codex", "Work", "5h", 96, resetsIn: 1_400, from: now),
                // Room to spare: nothing to wait for.
                limit("roomy", "claude", nil, "5h", 30, resetsIn: 1_400, from: now),
                // Nearly spent, but it never says when it turns over.
                limit("quiet", "cursor", nil, "Auto", 99, resetsIn: nil, from: now),
                // Too far out to still be true by then.
                limit("far", "claude", nil, "Month", 97, resetsIn: 30 * 86400, from: now),
                // So close it would land after the fact.
                limit("now", "gemini", nil, "Day", 97, resetsIn: 20, from: now),
            ],
            season: nil, quests: nil, wantsLimits: true, wantsSeason: false, now: now)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.title, "Codex · Work is ready")
        XCTAssertEqual(alerts.first?.body, "The 5h limit just reset.")
    }

    func testNothingIsScheduledWhileTheAlertsAreOff() {
        let now = Date()
        let quests = CloudQuests(quests: [.init(key: "today", name: "Get going", note: "", period: "day", done: 0, target: 1, complete: false)], badges: [])
        let season = CloudSeason(season: "2026-09", label: "September 2026", daysLeft: 1, over: false, players: 4, you: nil)
        XCTAssertTrue(AlertPlan.alerts(limits: [limit("a", "codex", nil, "5h", 99, resetsIn: 1_400, from: now)],
                                       season: season, quests: quests,
                                       wantsLimits: false, wantsSeason: false, now: now).isEmpty)
    }

    func testTheSeasonIsAnnouncedOnItsLastEveningOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 9))!
        func season(daysLeft: Int, over: Bool = false) -> CloudSeason {
            CloudSeason(season: "2026-09", label: "September 2026", daysLeft: daysLeft, over: over, players: 4,
                        you: .init(rank: 3, tokens: 4_000_000_000, tier: .init(key: "platinum", name: "Platinum", division: 2),
                                   next: .init(label: "Platinum I", tokens: 940_000_000)))
        }
        func alerts(_ season: CloudSeason?, at now: Date = Date()) -> [PlannedAlert] {
            AlertPlan.alerts(limits: [], season: season, quests: nil, wantsLimits: false, wantsSeason: true,
                             now: now, calendar: calendar)
        }

        let soon = alerts(season(daysLeft: 3), at: morning)
        XCTAssertEqual(soon.count, 1)
        XCTAssertEqual(soon.first?.title, "September 2026 ends tonight")
        XCTAssertEqual(soon.first?.body, "You're Platinum II, 940M tokens from Platinum I.")
        XCTAssertEqual(soon.first?.at, calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 18)))

        XCTAssertTrue(alerts(season(daysLeft: 9), at: morning).isEmpty)
        XCTAssertTrue(alerts(season(daysLeft: 1, over: true), at: morning).isEmpty)
        XCTAssertTrue(alerts(nil, at: morning).isEmpty)
        // The last evening has already passed.
        let night = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 21))!
        XCTAssertTrue(alerts(season(daysLeft: 1), at: night).isEmpty)
    }

    func testTonightsRemindercountsOnlyTodaysOpenGoals() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 15))!
        func quest(_ key: String, _ name: String, _ period: String, complete: Bool) -> CloudQuests.Quest {
            .init(key: key, name: name, note: "", period: period, done: complete ? 1 : 0, target: 1, complete: complete)
        }
        func alerts(_ quests: CloudQuests?, at now: Date) -> [PlannedAlert] {
            AlertPlan.alerts(limits: [], season: nil, quests: quests, wantsLimits: false, wantsSeason: true,
                             now: now, calendar: calendar)
        }

        let open = CloudQuests(quests: [
            quest("today", "Get going", "day", complete: true),
            quest("two-tools", "Two tools", "day", complete: false),
            quest("five-days", "Five days", "week", complete: false),
        ], badges: [])
        let tonight = alerts(open, at: afternoon)
        XCTAssertEqual(tonight.count, 1)
        XCTAssertEqual(tonight.first?.title, "One quest still open")
        XCTAssertEqual(tonight.first?.body, "Two tools.")
        XCTAssertEqual(tonight.first?.at, calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 20)))

        let done = CloudQuests(quests: [quest("today", "Get going", "day", complete: true)], badges: [])
        XCTAssertTrue(alerts(done, at: afternoon).isEmpty)
        // Past eight in the evening there is no point setting one for today.
        let late = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 22))!
        XCTAssertTrue(alerts(open, at: late).isEmpty)
    }

    func testAnAlertKeepsOneIdentityPerResetSoItIsNeverScheduledTwice() {
        let now = Date()
        let one = AlertPlan.alerts(limits: [limit("a", "codex", "Work", "5h", 96, resetsIn: 1_400, from: now)],
                                   season: nil, quests: nil, wantsLimits: true, wantsSeason: false, now: now)
        let again = AlertPlan.alerts(limits: [limit("a", "codex", "Work", "5h", 98, resetsIn: 1_400, from: now)],
                                     season: nil, quests: nil, wantsLimits: true, wantsSeason: false, now: now)
        XCTAssertEqual(one.first?.id, again.first?.id)
        // A new window means a new reset, and a different alert.
        let moved = AlertPlan.alerts(limits: [limit("a", "codex", "Work", "5h", 96, resetsIn: 20_000, from: now)],
                                     season: nil, quests: nil, wantsLimits: true, wantsSeason: false, now: now)
        XCTAssertNotEqual(one.first?.id, moved.first?.id)
    }

    func testAServerSuppliedLabelCannotSpoofANotification() {
        let now = Date()
        func nameFor(_ label: String) -> String {
            LimitAccount.group([limit("a", "codex", label, "5h", 96, resetsIn: 900, from: now)]).first?.name ?? ""
        }
        // These arrive over the network and go straight into a notification title, so the phone
        // cleans them again rather than trusting that the website already did.
        XCTAssertEqual(nameFor("Work\u{0A}is ready"), "Codex · Work is ready")
        XCTAssertEqual(nameFor("Work\u{00}x"), "Codex · Work x")
        XCTAssertEqual(nameFor("Work\u{1B}[31m"), "Codex · Work [31m")
        // A bidi override would reverse what the words appear to say.
        XCTAssertEqual(nameFor("a\u{202E}b"), "Codex · a b")
        XCTAssertEqual(nameFor("   "), "Codex")
        XCTAssertEqual(nameFor("Work"), "Codex · Work")

        // The window name lands in the notification body and is cleaned the same way.
        let alerts = AlertPlan.alerts(limits: [limit("a", "codex", "Work", "5h\u{0A}evil", 96, resetsIn: 900, from: now)],
                                      season: nil, quests: nil, wantsLimits: true, wantsSeason: false, now: now)
        XCTAssertEqual(alerts.first?.body, "The 5h evil limit just reset.")
        for alert in alerts {
            XCTAssertFalse(alert.title.contains("\u{0A}"))
            XCTAssertFalse(alert.body.contains("\u{0A}"))
        }
    }

    func testCountdownWords() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Format.until(now.addingTimeInterval(-5), from: now), "now")
        XCTAssertEqual(Format.until(now.addingTimeInterval(30), from: now), "1m")
        XCTAssertEqual(Format.until(now.addingTimeInterval(24 * 60), from: now), "24m")
        XCTAssertEqual(Format.until(now.addingTimeInterval(3 * 3600 + 10 * 60), from: now), "3h 10m")
        XCTAssertEqual(Format.until(now.addingTimeInterval(2 * 86400), from: now), "2d")
        XCTAssertEqual(Format.until(now.addingTimeInterval(2 * 86400 + 5 * 3600), from: now), "2d 5h")
    }

    func testToolNames() {
        XCTAssertEqual(Format.tool("gemini"), "Gemini CLI")
        XCTAssertEqual(Format.tool("claude"), "Claude Code")
        XCTAssertEqual(Format.tool("something"), "Something")
    }

    func testTokenStoreRoundTrip() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? TokenStore.clear(account: account) }

        try TokenStore.write("first-token", account: account)
        XCTAssertEqual(TokenStore.read(account: account), "first-token")
        try TokenStore.write("replacement-token", account: account)
        XCTAssertEqual(TokenStore.read(account: account), "replacement-token")
        try TokenStore.clear(account: account)
        XCTAssertNil(TokenStore.read(account: account))
    }
}
