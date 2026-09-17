import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Keyhop

final class AuthProfileAdapterTests: XCTestCase {
    private func folder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func jwt(_ claims: [String: Any]) throws -> String {
        let payload = try JSON.data(claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    func testOpenCodeProfileIdentitySurvivesOAuthRotationAndRoundTripsExactly() async throws {
        let directory = try folder("opencode-profile")
        let file = directory.appendingPathComponent("auth.json")
        let first = try JSON.string([
            "openai": ["type": "oauth", "access": jwt(["sub": "user-1", "email": "me@example.com"]),
                       "refresh": "refresh-one", "expires": 100] as [String: Any],
            "anthropic": ["type": "api", "key": "sk-ant-example"] as [String: Any],
        ], pretty: true)
        try Data(first.utf8).write(to: file)
        let adapter = OpenCodeAdapter(directory: directory)
        let read = try await adapter.readLive()
        let live = try XCTUnwrap(read)
        XCTAssertEqual(live.email, "me@example.com")
        XCTAssertFalse(live.identity.contains("refresh-one"))

        let rotated = try JSON.string([
            "openai": ["type": "oauth", "access": jwt(["sub": "user-1", "email": "me@example.com"]),
                       "refresh": "refresh-two", "expires": 200] as [String: Any],
            "anthropic": ["type": "api", "key": "sk-ant-example"] as [String: Any],
        ], pretty: true)
        try Data(rotated.utf8).write(to: file)
        let afterRotation = try await adapter.readLive()
        XCTAssertEqual(afterRotation?.identity, live.identity)

        try await adapter.apply(live.secret)
        XCTAssertEqual(String(decoding: try Data(contentsOf: file), as: UTF8.self), first)
        try await adapter.signOutLocally()
        XCTAssertEqual(JSON.object(try Data(contentsOf: file))?.count, 0)
    }

    func testPiRejectsMalformedOrEmptyProfiles() async throws {
        let directory = try folder("pi-profile")
        let file = directory.appendingPathComponent("auth.json")
        let adapter = PiAdapter(directory: directory)
        try Data("{}".utf8).write(to: file)
        let empty = try await adapter.readLive()
        XCTAssertNil(empty)
        try Data(#"{"openai":"not-a-credential"}"#.utf8).write(to: file)
        let malformed = try await adapter.readLive()
        XCTAssertNil(malformed)
        do {
            try await adapter.apply(["credentials": "{}"])
            XCTFail("an empty profile must not replace Pi's auth file")
        } catch {}
    }

    func testCodebuffSwitchesOnlyTheDefaultProfileAndKeepsOtherSettings() async throws {
        let directory = try folder("codebuff-profile")
        let file = directory.appendingPathComponent("credentials.json")
        try Data(#"{"default":{"id":"user-1","name":"Me","email":"me@example.com","authToken":"token-one"},"theme":"quiet"}"#.utf8)
            .write(to: file)
        let adapter = CodebuffAdapter(directory: directory)
        let result = try await adapter.readLive()
        let live = try XCTUnwrap(result)
        XCTAssertEqual(live.identity, "user-1")
        XCTAssertEqual(live.email, "me@example.com")
        XCTAssertFalse(live.secret["profile", default: ""].contains("theme"))

        try Data(#"{"default":{"id":"user-2","name":"Other","email":"other@example.com","authToken":"token-two"},"theme":"new"}"#.utf8)
            .write(to: file)
        try await adapter.apply(live.secret)
        let restored = try XCTUnwrap(JSON.object(try Data(contentsOf: file)))
        XCTAssertEqual((restored["default"] as? [String: Any])?["authToken"] as? String, "token-one")
        XCTAssertEqual(restored["theme"] as? String, "new", "unrelated current settings must survive a switch")

        try await adapter.signOutLocally()
        let signedOut = try XCTUnwrap(JSON.object(try Data(contentsOf: file)))
        XCTAssertNil(signedOut["default"])
        XCTAssertEqual(signedOut["theme"] as? String, "new")
    }

    func testCodebuffAcceptsLegacyCredentialsWithoutExposingTheToken() async throws {
        let directory = try folder("codebuff-legacy")
        try Data(#"{"name":"Legacy","authToken":"secret-token","setting":true}"#.utf8)
            .write(to: directory.appendingPathComponent("credentials.json"))
        let result = try await CodebuffAdapter(directory: directory).readLive()
        let live = try XCTUnwrap(result)
        XCTAssertEqual(live.email, "Codebuff account")
        XCTAssertFalse(live.emailTrusted)
        XCTAssertEqual(live.identity, CodebuffAdapter.fingerprint("secret-token"))
        XCTAssertFalse(live.identity.contains("secret-token"))
    }
}

final class ExtendedUsageSourceTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/2026-08-03T12-00-00-000Z_019fc5a9-c3d4-7e5f-8a9b-0c1d2e3f4a5b.jsonl")

    private func records(_ feed: LogFeed, _ lines: [String]) -> [UsageRecord] {
        var state: [String: String] = [:]
        return lines.compactMap { line in
            guard let object = JSON.object(line) else { return nil }
            return feed.parse(object, file, &state)
        }
    }

    func testPiCountsAssistantCompactionAndReportedCostButNotToolResults() {
        let lines = [
            #"{"type":"session","id":"session-1","timestamp":"2026-08-03T12:00:00Z","cwd":"/tmp/project"}"#,
            #"{"type":"message","id":"response-1","timestamp":"2026-08-03T12:00:01Z","message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-5","usage":{"input":100,"output":20,"cacheRead":300,"cacheWrite":40,"totalTokens":460,"cost":{"total":0.42}},"timestamp":1785758401000}}"#,
            #"{"type":"message","id":"tool-1","timestamp":"2026-08-03T12:00:02Z","message":{"role":"toolResult","usage":{"input":999}}}"#,
            #"{"type":"compaction","id":"compact-1","timestamp":"2026-08-03T12:00:03Z","usage":{"input":50,"output":10,"cacheRead":20,"cacheWrite":0,"totalTokens":80,"cost":{"total":0.08}}}"#,
        ]
        let result = records(.pi, lines)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].provider, .pi)
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 100, cacheWrite: 40, cacheRead: 300, output: 20))
        XCTAssertEqual(result[0].cost, 0.42, accuracy: 1e-9)
        XCTAssertEqual(result[1].model, "anthropic/claude-sonnet-5")
        XCTAssertEqual(result.map(\.key), ["pi:response-1:2026-08-03T12:00:01Z", "pi:compact-1:2026-08-03T12:00:03Z"])
    }

    func testOpenCodeReadsReasoningAsAnOutputSubsetAndKeepsReportedCost() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-opencode-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("opencode.db")
        let database = try Database(url: url)
        try database.script(Self.openCodeSchema)
        let data = #"{"role":"assistant","providerID":"openai","modelID":"gpt-5.6-sol","cost":0.123,"time":{"created":1785758401000,"completed":1785758401000},"tokens":{"input":100,"output":30,"reasoning":20,"cache":{"read":400,"write":10}}}"#
        try database.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [.text("msg_1"), .text("ses_1"), .int(1_785_758_401_000), .int(1_785_758_401_000), .text(data)])

        let result = try OpenCodeFeed.records(databaseURL: url, since: 0)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.watermark, 1_785_758_401_000)
        XCTAssertEqual(result.records[0].tokens, TokenCounts(input: 100, cacheWrite: 10, cacheRead: 400, output: 50, reasoning: 20))
        XCTAssertEqual(result.records[0].tokens.total, 560, "reasoning is already included in output and must not be counted twice")
        XCTAssertEqual(result.records[0].cost, 0.123, accuracy: 1e-9)
        XCTAssertEqual(result.records[0].model, "openai/gpt-5.6-sol")
    }

    /// The `message` table as OpenCode writes it, checked against a real install.
    static let openCodeSchema = """
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL,
                              time_updated INTEGER NOT NULL, data TEXT NOT NULL)
        """

    func testOpenCodeCountsAResponseThatFinishesAfterALaterOneStarted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-opencode-race-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("opencode.db")
        let database = try Database(url: url)
        try database.script(Self.openCodeSchema)
        func message(done: Bool, output: Int) -> String {
            let time = done ? #"{"created":1,"completed":2}"# : #"{"created":1}"#
            return #"{"role":"assistant","providerID":"anthropic","modelID":"claude","cost":0,"time":\#(time),"tokens":{"input":10,"output":\#(output),"reasoning":0,"cache":{"read":0,"write":0}}}"#
        }

        // A long response starts in one session and is still streaming with partial counts...
        try database.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [.text("slow"), .text("s1"), .int(1_000), .int(1_000), .text(message(done: false, output: 3))])
        // ...while a quick one in another session starts later and finishes.
        try database.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [.text("quick"), .text("s2"), .int(2_000), .int(2_500), .text(message(done: true, output: 7))])

        let first = try OpenCodeFeed.records(databaseURL: url, since: 0)
        XCTAssertEqual(first.records.map(\.key), ["opencode:quick"], "a response still streaming must not be stored with partial counts")
        XCTAssertEqual(first.watermark, 2_500)

        // The slow one finishes after the quick one: created earlier, updated later.
        try database.execute("UPDATE message SET time_updated = ?, data = ? WHERE id = 'slow'", [.int(9_000), .text(message(done: true, output: 400))])
        let second = try OpenCodeFeed.records(databaseURL: url, since: first.watermark)
        let slow = try XCTUnwrap(second.records.first { $0.key == "opencode:slow" }, "it was created before the watermark, but finished after it")
        XCTAssertEqual(slow.tokens.output, 400, "the finished count, not the partial one")
        XCTAssertEqual(second.watermark, 9_000)
    }

    func testOpenCodeHonoursCustomDatabasePaths() {
        let directory = URL(fileURLWithPath: "/tmp/opencode-data", isDirectory: true)
        XCTAssertEqual(OpenCodeAdapter.databaseURL(environment: [:], directory: directory),
                       directory.appendingPathComponent("opencode.db"))
        XCTAssertEqual(OpenCodeAdapter.databaseURL(environment: ["OPENCODE_DB": "preview.db"], directory: directory),
                       directory.appendingPathComponent("preview.db"))
        XCTAssertEqual(OpenCodeAdapter.databaseURL(environment: ["OPENCODE_DB": "/var/tmp/custom.db"], directory: directory).path,
                       "/var/tmp/custom.db")
    }
}

final class ExtendedQuotaTests: XCTestCase {
    /// The shape GitHub returned for a real gh login, values replaced.
    func testCopilotReadsTheSnapshotsGitHubActuallySends() {
        func snapshot(_ remaining: Double, entitlement: Int, unlimited: Bool = false) -> [String: Any] {
            ["overage_count": 0, "overage_permitted": false, "percent_remaining": remaining, "quota_id": "x",
             "quota_remaining": remaining, "unlimited": unlimited, "timestamp_utc": "2026-09-17T08:00:00Z",
             "has_quota": true, "quota_reset_at": 0, "token_based_billing": false, "credits_used": 0,
             "remaining": Int(remaining), "entitlement": entitlement]
        }
        let report = CopilotAdapter.limitReport([
            "copilot_plan": "individual",
            "quota_reset_date": "2026-10-01",
            "quota_reset_date_utc": "2026-10-01T00:00:00.000Z",
            "quota_snapshots": [
                "premium_interactions": snapshot(53, entitlement: 300),
                "chat": snapshot(100, entitlement: 0, unlimited: true),
                "completions": snapshot(100, entitlement: 0, unlimited: true),
            ],
        ])
        XCTAssertEqual(report.windows.map(\.label), ["Premium"], "unlimited lanes are not limits")
        XCTAssertEqual(report.windows.first?.usedPercent ?? 0, 47, accuracy: 1e-9)
        // The full UTC timestamp wins, and a zero `quota_reset_at` is never read as 1970.
        XCTAssertEqual(report.windows.first?.resetsAt, Dates.parse("2026-10-01T00:00:00Z"))
        XCTAssertEqual(report.plan, "individual")
    }

    func testCopilotIdentifiesItselfAsKeyhop() async throws {
        final class Seen: @unchecked Sendable { var request: URLRequest? }
        let seen = Seen()
        let adapter = CopilotAdapter(gh: { _, _ in ShellResult(status: 1, stdout: Data(), stderr: "") }) { request in
            seen.request = request
            return (Data(#"{"quota_snapshots":{}}"#.utf8), 200)
        }
        _ = try await adapter.fetchUsage(["token": "gho_example"], allowRefresh: false) { _ in }
        let request = try XCTUnwrap(seen.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Keyhop/\(AppVersion.current)")
        XCTAssertNil(request.value(forHTTPHeaderField: "Editor-Version"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Editor-Plugin-Version"))
        XCTAssertEqual(request.url?.host, "api.github.com")
    }

    func testCopilotFallsBackToLegacyMonthlyCountersOnlyWithBothNumbers() {
        let report = CopilotAdapter.limitReport([
            "copilot_plan": "free",
            "monthly_quotas": ["chat": 500, "completions": 300],
            "limited_user_quotas": ["chat": 125],
        ])
        XCTAssertEqual(report.windows.map(\.label), ["Chat"])
        XCTAssertEqual(report.windows.first?.usedPercent, 75)
    }

    func testCopilotPrefersDirectQuotaAndPreservesOverage() {
        let report = CopilotAdapter.limitReport([
            "quota_snapshots": [
                "premium_interactions": ["entitlement": 500, "remaining": -75, "percent_remaining": -15],
            ],
            "monthly_quotas": ["completions": 300],
            "limited_user_quotas": ["completions": 75],
        ])
        XCTAssertEqual(report.windows.map(\.label), ["Premium"], "the legacy fallback must not duplicate a direct lane")
        XCTAssertEqual(report.windows.first?.usedPercent, 115)
    }

    func testWindsurfReadsDailyWeeklyAndCountFallbacks() {
        let quota = WindsurfAdapter.limitReport([
            "planName": "Pro",
            "quotaUsage": ["dailyRemainingPercent": 9, "weeklyRemainingPercent": 54,
                           "dailyResetAtUnix": 1_774_080_000, "weeklyResetAtUnix": 1_774_166_400],
        ])
        XCTAssertEqual(quota.windows.map(\.label), ["Day", "Week"])
        XCTAssertEqual(quota.windows.map(\.usedPercent), [91, 46])
        XCTAssertEqual(quota.plan, "Pro")

        let counts = WindsurfAdapter.limitReport([
            "usage": ["messages": 100, "remainingMessages": 25, "flowActions": 200, "usedFlowActions": 50],
        ])
        XCTAssertEqual(counts.windows.map(\.label), ["Messages", "Flow actions"])
        XCTAssertEqual(counts.windows.map(\.usedPercent), [75, 25])
    }

    func testCodebuffSendsItsTokenOnlyAsABearerHeader() async throws {
        final class Seen: @unchecked Sendable { var requests: [URLRequest] = [] }
        let seen = Seen()
        let adapter = CodebuffAdapter(directory: FileManager.default.temporaryDirectory) { request in
            seen.requests.append(request)
            return (Data(#"{"usage":10,"quota":100}"#.utf8), 200)
        }
        _ = try await adapter.fetchUsage(["profile": #"{"authToken":"cb-token"}"#], allowRefresh: false) { _ in }
        XCTAssertEqual(seen.requests.count, 2)
        for request in seen.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cb-token")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"), "a CLI token is never presented as a browser session")
            XCTAssertEqual(request.url?.host, "codebuff.com")
        }
    }

    func testCodebuffUsesExactCreditBlockAndWeeklyDenominators() {
        let report = CodebuffAdapter.limitReport(
            usage: ["usage": 250, "remainingBalance": 750, "next_quota_reset": "2026-10-01T00:00:00Z"],
            subscription: [
                "hasSubscription": true,
                "displayName": "Strong",
                "rateLimit": ["blockUsed": 120, "blockLimit": 400, "blockResetsAt": "2026-09-18T00:00:00Z",
                              "weeklyUsed": 900, "weeklyLimit": 3_000, "weeklyResetsAt": "2026-09-21T00:00:00Z"],
                "limits": ["blockDurationHours": 5],
            ]
        )
        XCTAssertEqual(report.windows.map(\.label), ["Credits", "Block", "Week"])
        XCTAssertEqual(report.windows.map(\.usedPercent), [25, 30, 30])
        XCTAssertEqual(report.windows[1].windowSeconds, 18_000)
        XCTAssertEqual(report.windows[2].windowSeconds, 604_800)
        XCTAssertEqual(report.plan, "Strong")
    }

    func testCodebuffDoesNotInventCreditUseWithoutADenominator() {
        let report = CodebuffAdapter.limitReport(usage: ["remainingBalance": 750], subscription: nil)
        XCTAssertTrue(report.windows.isEmpty)
    }
}
