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

final class DigestAndPageTests: XCTestCase {
    func testBuiltInSHA256MatchesKnownDigests() {
        XCTAssertEqual(SHA256Digest.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Digest.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let long = Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
        XCTAssertEqual(SHA256Digest.hex(long), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        let million = Data(repeating: 0x61, count: 1_000_000)
        XCTAssertEqual(SHA256Digest.hex(million), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    func testChartScaleRoundsUpToReadableSteps() {
        XCTAssertEqual(InsightsPage.niceCeiling(0), 1)
        XCTAssertEqual(InsightsPage.niceCeiling(830), 1000)
        XCTAssertEqual(InsightsPage.niceCeiling(2_100_000), 2_500_000)
        XCTAssertEqual(InsightsPage.niceCeiling(4.2), 5)
    }

    func testPageEscapesAccountNamesAndKeepsEveryRangeReadable() {
        let now = Date()
        let account = Account(id: UUID(), provider: .claude, identity: "x", email: "a@x.dev", label: "<script>alert(1)</script>", plan: "Max", addedAt: now)
        var digest = UsageDigest()
        var totals = Totals()
        totals.tokens.input = 1200
        totals.cost = 0.4
        totals.requests = 3
        let key = AccountKey(provider: .claude, account: account.id)
        digest.byAccount[key] = totals
        digest.byModel["claude-opus-5"] = totals
        digest.total = totals
        digest.points = [UsageDigest.Point(start: Calendar.current.startOfDay(for: now), key: key, totals: totals)]
        let ranges = InsightsRange.allCases.map { InsightsPage.RangeData(range: $0, interval: $0.interval(now: now), digest: digest) }
        let html = InsightsPage.render(InsightsPage.Input(generatedAt: now, accounts: [account], active: [.claude: account.id],
                                                          usage: [:], ranges: ranges, budgets: [], budgetSpend: [:], initial: .week))
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertEqual(html.components(separatedBy: "<section class=\"range\"").count - 1, 4)
        XCTAssertTrue(html.contains("data-range=\"week\">"), "The chosen range is visible without JavaScript")
        XCTAssertTrue(html.contains("#C9821A"))
        XCTAssertFalse(html.contains("—"))
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
        #endif
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
