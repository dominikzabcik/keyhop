import XCTest
@testable import Keyhop

final class CloudTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-cloud-tests-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    func testDecodesTheWebsitesLeaderboard() throws {
        let json = """
        {"period":"week","metric":"tokens","entries":[{"rank":1,"login":"mira","name":null,"avatarUrl":null,"public":true,
        "tokens":1200,"requests":3,"activeDays":2,"tools":{"claude":1000,"cursor":200,"codex":0},"cost":1.25,"isYou":false}]}
        """
        let board = try JSONDecoder().decode(CloudBoard.self, from: Data(json.utf8))
        XCTAssertEqual(board.entries.first?.login, "mira")
        XCTAssertEqual(board.entries.first?.isPublic, true)
        XCTAssertEqual(board.entries.first?.tools["claude"], 1000)
        XCTAssertEqual(board.entries.first?.cost ?? 0, 1.25, accuracy: 1e-9)

        let user = try JSONDecoder().decode(CloudUser.self, from: Data(#"{"login":"mira","name":"Mira","avatarUrl":null,"public":false}"#.utf8))
        XCTAssertFalse(user.isPublic)
    }

    func testDailyTotalsAddUpPerToolAndLocalDay() async throws {
        let engine = try TrackerEngine(url: url)
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let yesterday = today.addingTimeInterval(-3600)
        func record(_ key: String, _ provider: Provider, at date: Date, output: Int, cost: Double) -> UsageRecord {
            UsageRecord(key: key, provider: provider, account: nil, session: nil, kind: .request, timestamp: date,
                        model: "model", tokens: TokenCounts(output: output), cost: cost, billed: nil)
        }
        try await engine.store([
            record("a", .claude, at: today.addingTimeInterval(1), output: 100, cost: 1),
            record("b", .claude, at: today.addingTimeInterval(2), output: 100, cost: 1.004),
            record("c", .codex, at: today.addingTimeInterval(3), output: 50, cost: 0.5),
            record("d", .claude, at: yesterday, output: 30, cost: 0.3),
        ])

        let days = try await CloudSync.days(tracker: engine, since: Calendar.current.startOfDay(for: yesterday), now: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let todayLabel = formatter.string(from: today), yesterdayLabel = formatter.string(from: yesterday)

        XCTAssertEqual(days, [
            CloudDay(day: yesterdayLabel, tool: "claude", tokens: 30, cost: 0.3, requests: 1),
            CloudDay(day: todayLabel, tool: "claude", tokens: 200, cost: 2, requests: 2),
            CloudDay(day: todayLabel, tool: "codex", tokens: 50, cost: 0.5, requests: 1),
        ])
    }

    func testSharedLimitsCarryLabelsButNeverEmails() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func account(_ provider: Provider, _ email: String, label: String?) -> Account {
            Account(id: UUID(), provider: provider, identity: email, email: email, label: label, plan: nil, addedAt: now)
        }
        let named = account(.codex, "me@example.com", label: " Work ")
        let unnamed = account(.claude, "personal@example.com", label: nil)
        let blank = account(.cursor, "blank@example.com", label: "   ")
        let broken = account(.gemini, "broken@example.com", label: "Broken")
        let usage: [UUID: UsageSnapshot] = [
            named.id: UsageSnapshot(windows: [
                UsageWindow(label: "5h", usedPercent: 96.4, resetsAt: now.addingTimeInterval(1500), windowSeconds: 18000),
                // Already turned over: a reading waiting to be refreshed, not a countdown.
                UsageWindow(label: "Week", usedPercent: 40, resetsAt: now.addingTimeInterval(-60), windowSeconds: 604_800),
            ], fetchedAt: now),
            unnamed.id: UsageSnapshot(windows: [UsageWindow(label: "5h", usedPercent: 12, resetsAt: nil, windowSeconds: nil)], fetchedAt: now),
            blank.id: UsageSnapshot(windows: [UsageWindow(label: "Auto", usedPercent: 3, resetsAt: nil, windowSeconds: nil)], fetchedAt: now),
            broken.id: UsageSnapshot(windows: [UsageWindow(label: "Day", usedPercent: 50, resetsAt: nil, windowSeconds: nil)],
                                     error: "The saved login is missing.", fetchedAt: now),
        ]

        let limits = CloudSync.limits(accounts: [named, unnamed, blank, broken], usage: usage, now: now)
        XCTAssertEqual(limits.count, 4)
        XCTAssertEqual(limits.first, CloudLimit(accountKey: named.id.uuidString, tool: "codex", label: "Work",
                                                windowLabel: "5h", usedPercent: 96.4, resetsAt: 1_800_001_500))
        XCTAssertNil(limits.first { $0.windowLabel == "Week" }?.resetsAt)
        XCTAssertNil(limits.first { $0.accountKey == unnamed.id.uuidString }?.label)
        XCTAssertNil(limits.first { $0.accountKey == blank.id.uuidString }?.label)
        // An account Keyhop couldn't read sends nothing rather than a stale guess.
        XCTAssertFalse(limits.contains { $0.accountKey == broken.id.uuidString })
        let sent = String(decoding: try! JSONEncoder().encode(limits), as: UTF8.self)
        for account in [named, unnamed, blank, broken] {
            XCTAssertFalse(sent.contains(account.email), "\(account.email) must never be sent")
        }
    }

    func testLimitSharingStaysOffUntilItIsTurnedOn() throws {
        let json = #"{"server":"https://keyhop.example","login":"mira","isPublic":false,"linkedAt":"2027-01-15T08:00:00Z"}"#
        var link = try DashboardJSON.decoder.decode(CloudLink.self, from: Data(json.utf8))
        XCTAssertFalse(link.sharesLimits)
        XCTAssertNil(link.lastLimitSync)
        link.sharesLimits = true
        let round = try DashboardJSON.decoder.decode(CloudLink.self, from: DashboardJSON.encoder.encode(link))
        XCTAssertTrue(round.sharesLimits)
    }

    /// A website older than limit sharing answers /api/limits with 404. That must cost the phone its
    /// countdown and nothing more: daily totals still go, and the refusal is said, not hidden.
    func testDailyTotalsStillSyncWhenTheWebsiteRefusesLimits() async throws {
        #if os(Windows)
        throw XCTSkip("Uses setenv to move the data folder, which Windows doesn't have.")
        #else
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-cloud-order-\(UUID().uuidString)")
        setenv("KEYHOP_DATA_DIR", folder.path, 1)
        defer {
            unsetenv("KEYHOP_DATA_DIR")
            try? FileManager.default.removeItem(at: folder)
        }

        final class Hits: @unchecked Sendable {
            private let lock = NSLock()
            private var paths: [String] = []
            func add(_ path: String) { lock.lock(); paths.append(path); lock.unlock() }
            var all: [String] { lock.lock(); defer { lock.unlock() }; return paths }
        }
        let hits = Hits()
        let server = try LoopbackServer()
        server.start { request in
            hits.add("\(request.method) \(request.path)")
            switch request.path {
            case "/api/usage": return .json(["saved": 0])
            default: return .json(["error": "Not found."], status: 404)
            }
        }
        defer { server.stop() }

        let store = MemorySecretStore()
        try CloudLink(server: "http://127.0.0.1:\(server.port)", token: "secret", login: "mira", name: nil, isPublic: false,
                      linkedAt: Date(), sharesLimits: true).save(store: store)
        let engine = try TrackerEngine(url: url)
        let now = Date()
        // A day of usage, so there is something to send.
        try await engine.store([UsageRecord(key: "a", provider: .claude, account: nil, session: nil, kind: .request,
                                            timestamp: now.addingTimeInterval(-60), model: "model",
                                            tokens: TokenCounts(output: 10), cost: 0.01, billed: nil)])
        await CloudSync.syncIfDue(tracker: engine, now: now, store: store)

        XCTAssertTrue(hits.all.contains("POST /api/usage"), "daily totals must go even though limits are refused")
        XCTAssertTrue(hits.all.contains("POST /api/limits"))
        let after = try XCTUnwrap(CloudLink.load(store: store), "a refusal is not an unlink")
        XCTAssertEqual(after.lastSync?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(after.lastSyncError?.hasPrefix("Sharing limits failed") == true)
        XCTAssertNotNil(after.lastLimitSync)

        // Refused a moment ago, so a quick second refresh leaves the website alone.
        let before = hits.all.count
        await CloudSync.syncIfDue(tracker: engine, now: now.addingTimeInterval(60), store: store)
        XCTAssertEqual(hits.all.count, before)
        #endif
    }

    func testTheLinkKeepsItsTokenInTheSecretStore() throws {
        #if os(Windows)
        throw XCTSkip("Uses setenv to move the data folder, which Windows doesn't have.")
        #else
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-cloud-link-\(UUID().uuidString)")
        setenv("KEYHOP_DATA_DIR", folder.path, 1)
        defer {
            unsetenv("KEYHOP_DATA_DIR")
            try? FileManager.default.removeItem(at: folder)
        }
        let link = CloudLink(server: "https://keyhop.example", token: "secret", login: "mira", name: nil, isPublic: false,
                             linkedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let store = MemorySecretStore()
        try link.save(store: store)
        XCTAssertEqual(CloudLink.load(store: store), link)
        XCTAssertEqual(link.profileURL, "https://keyhop.example/u/mira")
        XCTAssertFalse(String(decoding: try Data(contentsOf: CloudLink.url), as: UTF8.self).contains("secret"))
        XCTAssertEqual(store.read("session"), Data("secret".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: CloudLink.url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        CloudLink.remove(store: store)
        XCTAssertNil(CloudLink.load(store: store))
        XCTAssertNil(store.read("session"))
        #endif
    }

    func testExistingCloudFilesMoveTheirTokenIntoTheSecretStore() throws {
        #if os(Windows)
        throw XCTSkip("Uses setenv to move the data folder, which Windows doesn't have.")
        #else
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-cloud-migration-\(UUID().uuidString)")
        setenv("KEYHOP_DATA_DIR", folder.path, 1)
        defer {
            unsetenv("KEYHOP_DATA_DIR")
            try? FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = """
        {"server":"https://keyhop.example","token":"old-secret","login":"mira","isPublic":false,"linkedAt":"2027-01-15T08:00:00Z"}
        """
        try Data(legacy.utf8).write(to: CloudLink.url)
        let store = MemorySecretStore()
        XCTAssertEqual(CloudLink.load(store: store)?.token, "old-secret")
        XCTAssertEqual(store.read("session"), Data("old-secret".utf8))
        XCTAssertFalse(String(decoding: try Data(contentsOf: CloudLink.url), as: UTF8.self).contains("old-secret"))
        #endif
    }
}
