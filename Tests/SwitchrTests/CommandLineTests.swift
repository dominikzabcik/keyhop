import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Switchr

final class ArgumentsTests: XCTestCase {
    func testFlagsOptionsAndPositionalsInAnyOrder() throws {
        var args = Arguments(["switch", "--tool", "claude", "work@studio.dev", "--json"])
        XCTAssertEqual(args.nextPositional(), "switch")
        XCTAssertTrue(args.flag("--json"))
        XCTAssertFalse(args.flag("--json"))
        XCTAssertEqual(try args.option("--tool"), "claude")
        XCTAssertEqual(try args.positional("an account"), "work@studio.dev")
        XCTAssertNoThrow(try args.finish())
    }

    func testOptionsTakeEqualsAndRequireValues() throws {
        var args = Arguments(["usage", "--range=30d"])
        XCTAssertEqual(try args.option("--range"), "30d")
        var missing = Arguments(["usage", "--range"])
        XCTAssertThrowsError(try missing.option("--range"))
    }

    func testLeftoverArgumentsAreReported() {
        var args = Arguments(["status", "--nope"])
        _ = args.nextPositional()
        XCTAssertThrowsError(try args.finish())
    }

    func testRemainingWordsJoinNamesWithSpaces() {
        var args = Arguments(["rename", "ada@example.com", "Side", "project"])
        _ = args.nextPositional()
        _ = args.nextPositional()
        XCTAssertEqual(args.remainingWords(), "Side project")
    }

    func testRangeWords() {
        XCTAssertEqual(InsightsRange(argument: "30d"), .thirtyDays)
        XCTAssertEqual(InsightsRange(argument: "Week"), .week)
        XCTAssertNil(InsightsRange(argument: "year"))
    }

    func testAccountsResolveByEmailNameOrIDPrefix() throws {
        let now = Date()
        let ada = Account(id: UUID(), provider: .claude, identity: "a", email: "ada@example.com", label: "Personal", plan: nil, addedAt: now)
        let adaCursor = Account(id: UUID(), provider: .cursor, identity: "b", email: "ada@example.com", label: nil, plan: nil, addedAt: now)
        let accounts = [ada, adaCursor]

        XCTAssertEqual(try Commands.resolve("personal", tool: nil, in: accounts).id, ada.id)
        XCTAssertEqual(try Commands.resolve("ada@example.com", tool: .cursor, in: accounts).id, adaCursor.id)
        XCTAssertEqual(try Commands.resolve(String(ada.id.uuidString.prefix(8)), tool: nil, in: accounts).id, ada.id)
        XCTAssertThrowsError(try Commands.resolve("ada@example.com", tool: nil, in: accounts))
        XCTAssertThrowsError(try Commands.resolve("nobody", tool: nil, in: accounts))
    }
}

final class AlertRulesTests: XCTestCase {
    private let now = Date()

    private func account(_ email: String) -> Account {
        Account(id: UUID(), provider: .claude, identity: email, email: email, label: nil, plan: nil, addedAt: now)
    }

    private func reading(_ used: Double) -> UsageSnapshot {
        UsageSnapshot(windows: [UsageWindow(label: "5h", usedPercent: used, resetsAt: now.addingTimeInterval(3600), windowSeconds: 18000)], fetchedAt: now)
    }

    func testANearlyUsedUpLimitSuggestsTheAccountWithTheMostRoom() {
        let inUse = account("a@x.dev"), busy = account("b@x.dev"), roomy = account("c@x.dev")
        let alerts = AlertRules.evaluate(accounts: [inUse, busy, roomy], active: [.claude: inUse.id],
                                         usage: [inUse.id: reading(95), busy.id: reading(60), roomy.id: reading(20)],
                                         forecasts: [:], budgets: [], budgetSpend: [:], now: now)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.switchTo, roomy.id)
        XCTAssertTrue(alerts.first?.title.contains("95%") ?? false)
    }

    func testEarlyForecastsStayQuiet() {
        let inUse = account("a@x.dev")
        let forecasts = [AlertRules.forecastKey(inUse.id, "5h"): now.addingTimeInterval(1800)]
        let early = AlertRules.evaluate(accounts: [inUse], active: [.claude: inUse.id], usage: [inUse.id: reading(30)],
                                        forecasts: forecasts, budgets: [], budgetSpend: [:], now: now)
        XCTAssertTrue(early.isEmpty)
        let later = AlertRules.evaluate(accounts: [inUse], active: [.claude: inUse.id], usage: [inUse.id: reading(60)],
                                        forecasts: forecasts, budgets: [], budgetSpend: [:], now: now)
        XCTAssertEqual(later.count, 1)
    }

    func testBudgetsWarnAtEightyAndOneHundredPercent() {
        let budget = Budget(scope: Budget.everything, amount: 100, period: .month)
        let warned = AlertRules.evaluate(accounts: [], active: [:], usage: [:], forecasts: [:], budgets: [budget],
                                         budgetSpend: [Budget.everything: 85], now: now)
        XCTAssertTrue(warned.first?.title.contains("80%") ?? false)
        let over = AlertRules.evaluate(accounts: [], active: [:], usage: [:], forecasts: [:], budgets: [budget],
                                       budgetSpend: [Budget.everything: 120], now: now)
        XCTAssertTrue(over.first?.title.contains("over") ?? false)
        XCTAssertNotEqual(warned.first?.key, over.first?.key)
    }
}

/// The Linux and Windows trays read these fields from `switchr status --json`.
final class TrayContractTests: XCTestCase {
    private func object(_ any: Any?, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        try XCTUnwrap(any as? [String: Any], file: file, line: line)
    }

    private func first(_ any: Any?, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        try XCTUnwrap((any as? [[String: Any]])?.first, file: file, line: line)
    }

    func testStatusCarriesEverythingTheTraysRead() throws {
        let data = try Output.encoder.encode(StatusDocument(SampleData.overview()))
        let root = try object(JSONSerialization.jsonObject(with: data))
        for key in ["version", "refreshedAt", "today", "tools", "alerts", "notices", "budgets"] {
            XCTAssertNotNil(root[key], key)
        }
        let today = try object(root["today"])
        for key in ["tokens", "cost", "requests"] { XCTAssertNotNil(today[key], "today.\(key)") }

        let tool = try first(root["tools"])
        for key in ["id", "name", "signInHint", "accounts"] { XCTAssertNotNil(tool[key], "tool.\(key)") }
        let account = try first(tool["accounts"])
        for key in ["id", "email", "name", "plan", "active", "limits"] { XCTAssertNotNil(account[key], "account.\(key)") }
        let limit = try first(account["limits"])
        for key in ["label", "usedPercent", "resetsAt"] { XCTAssertNotNil(limit[key], "limit.\(key)") }

        let budget = try first(root["budgets"])
        for key in ["scope", "name", "amount", "period", "spent"] { XCTAssertNotNil(budget[key], "budget.\(key)") }
        let alert = try first(root["alerts"])
        for key in ["key", "title", "body"] { XCTAssertNotNil(alert[key], "alert.\(key)") }
    }

    func testSampleDataFillsEveryRangeWithoutRealLogins() {
        let now = Date()
        for range in InsightsRange.allCases {
            XCTAssertGreaterThan(SampleData.digest(range: range, accounts: SampleData.accounts(now: now), now: now).total.requests, 0, range.title)
        }
        XCTAssertTrue(SampleData.accounts().allSatisfy { $0.email.hasSuffix(".dev") })
    }

    func testSampleDataIsNeverEmptyEarlyInTheDay() {
        let justAfterMidnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(5 * 60)
        for range in InsightsRange.allCases {
            let digest = SampleData.digest(range: range, accounts: SampleData.accounts(), now: justAfterMidnight)
            XCTAssertGreaterThan(digest.total.requests, 0, range.title)
        }
    }
}

final class DigestAndPageTests: XCTestCase {
    func testBuiltInSHA256MatchesKnownDigests() {
        XCTAssertEqual(SHA256Digest.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Digest.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let long = Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
        XCTAssertEqual(SHA256Digest.hex(long), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        let million = Data(repeating: 0x61, count: 1_000_000)
        XCTAssertEqual(SHA256Digest.hex(million), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

}

final class DashboardTests: XCTestCase {
    private func request(_ method: String, _ headers: [String: String]) -> HTTPRequest {
        HTTPRequest(method: method, path: "/api/state", query: [:], headers: headers, body: Data())
    }

    func testRequestHeadsParseAndJunkIsRejected() throws {
        let head = try XCTUnwrap(LoopbackServer.parseHead(Data("POST /api/usage?range=30d&tool=claude HTTP/1.1\r\nHost: 127.0.0.1:8123\r\nContent-Type: application/json".utf8)))
        XCTAssertEqual(head.method, "POST")
        XCTAssertEqual(head.path, "/api/usage")
        XCTAssertEqual(head.query["range"], "30d")
        XCTAssertEqual(head.headers["host"], "127.0.0.1:8123")
        XCTAssertNil(LoopbackServer.parseHead(Data("GARBAGE".utf8)))
        XCTAssertNil(LoopbackServer.parseHead(Data("GET http://elsewhere.test/ HTTP/1.1".utf8)))
        XCTAssertNil(LoopbackServer.parseHead(Data("GET / HTTP/1.1\r\nno colon here".utf8)))
    }

    func testTheAPINeedsTheTokenTheLoopbackHostAndJSON() {
        let token = "0123abcd", port: UInt16 = 8123
        let good = ["host": "127.0.0.1:8123", "authorization": "Bearer 0123abcd"]
        XCTAssertNil(DashboardAccess.problem(with: request("GET", good), token: token, port: port))
        XCTAssertNotNil(DashboardAccess.problem(with: request("GET", good.merging(["authorization": "Bearer nope"]) { $1 }), token: token, port: port))
        XCTAssertNotNil(DashboardAccess.problem(with: request("GET", ["host": "127.0.0.1:8123"]), token: token, port: port))
        XCTAssertNotNil(DashboardAccess.problem(with: request("GET", good.merging(["host": "rebound.test:8123"]) { $1 }), token: token, port: port))
        XCTAssertNotNil(DashboardAccess.problem(with: request("GET", good.merging(["origin": "https://elsewhere.test"]) { $1 }), token: token, port: port))
        XCTAssertNotNil(DashboardAccess.problem(with: request("POST", good.merging(["content-type": "text/plain"]) { $1 }), token: token, port: port))
        XCTAssertNil(DashboardAccess.problem(with: request("POST", good.merging(["content-type": "application/json", "origin": "http://127.0.0.1:8123"]) { $1 }), token: token, port: port))
    }

    func testUsageDocumentFillsBucketsTheHeatmapAndStreaks() {
        let now = Date()
        let accounts = SampleData.accounts(now: now)
        let daily = SampleData.digest(interval: DashboardUsage.heatmapInterval(now: now), bucket: .day, accounts: accounts, now: now)
        let usage = DashboardUsage(range: .week, tool: nil, now: now, digest: SampleData.digest(range: .week, accounts: accounts, now: now),
                                   daily: daily, accounts: accounts, active: [:])
        XCTAssertEqual(usage.buckets.count, 7)
        XCTAssertEqual(usage.series.first?.color, "#C9821A")
        XCTAssertGreaterThanOrEqual(usage.heatmap.count, 176)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(usage.heatmap.last?.day, formatter.string(from: now))
        XCTAssertLessThanOrEqual(usage.streak.current, usage.streak.longest)
        XCTAssertGreaterThan(usage.streak.activeDays, 0)
    }

    func testStreaksCountBackFromTodayOrAQuietToday() {
        func day(_ name: String, _ requests: Int) -> DashboardUsage.Day { DashboardUsage.Day(day: name, tokens: requests * 10, cost: 0, requests: requests) }
        let days = [day("d1", 3), day("d2", 0), day("d3", 2), day("d4", 5), day("d5", 1), day("today", 0)]
        XCTAssertEqual(DashboardUsage.streak(days: days, today: "today"), DashboardUsage.Streak(current: 3, longest: 3, activeDays: 4))
        let broken = [day("d1", 2), day("d2", 0), day("today", 0)]
        XCTAssertEqual(DashboardUsage.streak(days: broken, today: "today").current, 0)
    }

    func testThePageEmbedsDataSafelyAndCarriesTheMarks() {
        let page = DashboardPage.render(boot: #"{"mode":"static","name":"</script><script>alert(1)</script>"}"#)
        XCTAssertFalse(page.contains("</script><script>alert(1)"))
        XCTAssertTrue(page.contains(#"</script>"#))
        XCTAssertFalse(page.contains("{{mark-"))
        XCTAssertFalse(page.contains("{{boot}}"))
        XCTAssertFalse(page.contains("—"))
    }

    func testStaticSampleExportHasEveryRange() async throws {
        let page = try await Dashboard.staticPage(sample: true, readLogs: false)
        for range in InsightsRange.allCases {
            XCTAssertTrue(page.contains(#""range":"\#(range.argument)""#), range.argument)
        }
        XCTAssertTrue(page.contains(#""mode":"static""#))
    }
}

#if os(Linux)
final class SystemCurlTests: XCTestCase {
    func testConfigQuotesHeadersAndBodies() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/token?a=1&b=2")), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer abc\"def", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"refresh_token":"x\y"}"#.utf8)
        let config = SystemCurl.config(for: request)
        XCTAssertTrue(config.contains(#"url = "https://example.com/token?a=1&b=2""#))
        XCTAssertTrue(config.contains(#"request = "POST""#))
        XCTAssertTrue(config.contains(#"header = "Authorization: Bearer abc\"def""#))
        XCTAssertTrue(config.contains(#"data-binary = "{\"refresh_token\":\"x\\y\"}""#))
        XCTAssertTrue(config.contains(#"write-out = "\n%{http_code}""#))
    }
}
#endif

final class StorageTests: XCTestCase {
    func testFileSecretsAreReadableOnlyByTheUser() throws {
        #if os(Windows)
        throw XCTSkip("Windows files have no POSIX permissions; logins are DPAPI-encrypted instead.")
        #else
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("switchr-secrets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSecretStore(directory: directory)

        try store.write(Data("secret".utf8), account: "one")
        XCTAssertEqual(store.read("one"), Data("secret".utf8))
        let file = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("one").path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        store.delete("one")
        XCTAssertNil(store.read("one"))
        #endif
    }

    func testVaultRoundTripsThroughAnyStore() async {
        let vault = Vault(store: MemorySecretStore())
        let id = UUID()
        let saved = await vault.write(["token": "abc", "account": "{\"email\":\"a@b\"}"], for: id)
        XCTAssertTrue(saved)
        let secret = await vault.read(id)
        XCTAssertEqual(secret?["token"], "abc")
        await vault.delete(id)
        let gone = await vault.read(id)
        XCTAssertNil(gone)
    }

    func testCommandLineStateRoundTrips() throws {
        let id = UUID()
        var state = CLIState()
        state.usage[id.uuidString] = UsageSnapshot(windows: [UsageWindow(label: "Week", usedPercent: 41, resetsAt: Date(timeIntervalSince1970: 2_000_000_000), windowSeconds: 604_800)],
                                                   fetchedAt: Date(timeIntervalSince1970: 1_900_000_000))
        state.active[Provider.codex.rawValue] = id.uuidString

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CLIState.self, from: encoder.encode(state))
        XCTAssertEqual(decoded.usageByID[id]?.windows.first?.usedPercent, 41)
        XCTAssertEqual(decoded.activeByTool[.codex], id)
    }
}
