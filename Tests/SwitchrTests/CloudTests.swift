import XCTest
@testable import Switchr

final class CloudTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("switchr-cloud-tests-\(UUID().uuidString).sqlite")
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

    func testTheLinkIsSavedPrivately() throws {
        #if os(Windows)
        throw XCTSkip("Uses setenv to move the data folder, which Windows doesn't have.")
        #else
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("switchr-cloud-link-\(UUID().uuidString)")
        setenv("SWITCHR_DATA_DIR", folder.path, 1)
        defer {
            unsetenv("SWITCHR_DATA_DIR")
            try? FileManager.default.removeItem(at: folder)
        }
        let link = CloudLink(server: "https://switchr.example", token: "secret", login: "mira", name: nil, isPublic: false,
                             linkedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try link.save()
        XCTAssertEqual(CloudLink.load(), link)
        XCTAssertEqual(link.profileURL, "https://switchr.example/u/mira")
        let permissions = try FileManager.default.attributesOfItem(atPath: CloudLink.url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        CloudLink.remove()
        XCTAssertNil(CloudLink.load())
        #endif
    }
}
