import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Keyhop cloud as anything can read it: the shapes the website answers with, and the client that
/// asks. Nothing here touches a disk, a keychain or a desktop, so the iOS app compiles the same file
/// the Mac app does. What is saved on this computer lives next door in Cloud.swift.

struct CloudError: LocalizedError {
    enum Kind { case unlinked, expired, server }
    let kind: Kind
    let message: String

    var errorDescription: String? { message }

    static let unlinked = CloudError(kind: .unlinked, message: "This computer isn't linked to Keyhop cloud anymore. Run keyhop cloud login.")
}

/// One day's totals for one tool, as the website stores them.
struct CloudDay: Codable, Equatable {
    let day: String
    let tool: String
    let tokens: Int
    let cost: Double
    let requests: Int
}

/// One commit, as the website stores it. Only the subject line travels: never the body, the diff
/// or the file names. Sent only while subject sharing is on.
struct CloudWorkCommit: Codable, Equatable {
    let sha: String
    let subject: String
    let insertions: Int
    let deletions: Int
    /// When it was authored, in seconds, so a day can be read in the order it happened.
    let at: Int
    /// Seconds east of UTC where it was authored, so the clock reads as that person's own.
    let offset: Int
}

/// One day's commits in one repository. `subjects` is left out entirely unless sharing is on, and
/// leaving it out is what clears the subjects the website already holds for that day.
struct CloudWorkDay: Codable, Equatable {
    let day: String
    let repo: String
    var commits: Int
    var insertions: Int
    var deletions: Int
    var subjects: [CloudWorkCommit]?
}

/// How far this computer has got through its repositories.
///
/// Sent with the commits so the website can tell a half-indexed day from a quiet one. A day still
/// filling in has real numbers that are not yet the whole truth, and saying so is the difference
/// between a teammate reading "nothing yet" and reading "they did less than me".
struct CloudWorkIndex: Codable, Equatable {
    let done: Int
    let total: Int
    let complete: Bool
}

/// One window of one account's limits, as a linked phone reads them. Sent only while limit sharing
/// is on, and only ever the current reading: the website keeps no history of these.
struct CloudLimit: Codable, Equatable, Identifiable {
    /// Opaque per-account key from the computer. Stable across uploads, meaningless off this row.
    let accountKey: String
    let tool: String
    /// Only a label a person typed for the account. Emails and account names are never sent.
    let label: String?
    /// The window's own name, as the provider draws it: "5h", "Week", "Auto".
    let windowLabel: String
    let usedPercent: Double
    /// Unix seconds, or nil for a window whose provider doesn't say when it turns over.
    let resetsAt: Int?

    var id: String { "\(accountKey)|\(windowLabel)" }

    var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    init(accountKey: String, tool: String, label: String?, windowLabel: String, usedPercent: Double, resetsAt: Int?) {
        self.accountKey = accountKey
        self.tool = tool
        self.label = label
        self.windowLabel = windowLabel
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Every current reading, soonest reset first, with when the computer last sent them.
struct CloudLimits: Codable, Equatable {
    let limits: [CloudLimit]
    let updatedAt: Int?

    var updated: Date? { updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    static let none = CloudLimits(limits: [], updatedAt: nil)
}

/// A leaderboard as the website ranks it.
struct CloudBoard: Codable {
    struct Entry: Codable {
        let rank: Int
        let login: String
        let name: String?
        let avatarUrl: String?
        let isPublic: Bool
        let tokens: Int
        let cost: Double
        let requests: Int
        let activeDays: Int
        let tools: [String: Int]
        let isYou: Bool

        enum CodingKeys: String, CodingKey {
            case rank, login, name, avatarUrl, tokens, cost, requests, activeDays, tools, isYou
            case isPublic = "public"
        }
    }

    let period: String
    let metric: String
    let entries: [Entry]
}

/// A ranked season: one calendar month, with the tier your tokens earned in it.
struct CloudSeason: Codable {
    struct Tier: Codable {
        let key: String
        let name: String
        /// 3, 2 or 1 inside a tier. Master has none.
        let division: Int?
    }

    struct Step: Codable {
        let label: String
        let tokens: Int
    }

    struct You: Codable {
        let rank: Int?
        let tokens: Int
        let tier: Tier
        let next: Step?
    }

    let season: String
    let label: String
    let daysLeft: Int
    let over: Bool
    let players: Int
    let you: You?
}

/// This week's goals and the badges earned, as the website counts them.
struct CloudQuests: Codable {
    struct Quest: Codable {
        let key: String
        let name: String
        let note: String
        /// "day" or "week".
        let period: String
        let done: Int
        let target: Int
        let complete: Bool
    }

    struct Badge: Codable {
        let key: String
        let name: String
        let note: String
        let earned: Bool
        let day: String?
    }

    let quests: [Quest]
    let badges: [Badge]
}

struct CloudTeam: Codable {
    let slug: String
    let name: String
    let role: String
    let members: Int
}

struct CloudUser: Codable, Equatable {
    let login: String
    let name: String?
    let avatarUrl: String?
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case login, name, avatarUrl
        case isPublic = "public"
    }
}

struct CloudClient {
    let server: String
    var token: String?

    struct LinkStart: Decodable, Equatable {
        let deviceCode: String
        let userCode: String
        let verifyUrl: String
        let interval: Int
        let expiresIn: Int
    }

    struct Granted: Decodable {
        let token: String
        let user: CloudUser
    }

    enum Poll {
        case pending
        case expired
        case granted(Granted)
    }

    func startLink(label: String, readOnly: Bool = false) async throws -> LinkStart {
        let (data, status) = try await send(
            "POST", "/api/device/start", body: ["label": label, "access": readOnly ? "read" : "write"]
        )
        guard status == 200 else { throw problem(data, status) }
        return try JSONDecoder().decode(LinkStart.self, from: data)
    }

    func poll(_ deviceCode: String) async throws -> Poll {
        let (data, status) = try await send("POST", "/api/device/token", body: ["deviceCode": deviceCode])
        switch status {
        case 200: return .granted(try JSONDecoder().decode(Granted.self, from: data))
        case 428: return .pending
        case 410: return .expired
        default: throw problem(data, status)
        }
    }

    func me() async throws -> CloudUser {
        struct Response: Decodable { let user: CloudUser }
        let (data, status) = try await send("GET", "/api/me")
        guard status == 200 else { throw problem(data, status) }
        return try JSONDecoder().decode(Response.self, from: data).user
    }

    /// Replaces the website's totals for each day and tool sent.
    func upload(_ days: [CloudDay]) async throws -> Int {
        struct Response: Decodable { let saved: Int }
        var saved = 0
        // The website takes up to 1200 entries per request.
        for start in stride(from: 0, to: days.count, by: 1000) {
            let chunk = Array(days[start..<min(start + 1000, days.count)])
            let (data, status) = try await send("POST", "/api/usage", body: ["days": chunk])
            guard status == 200 else { throw problem(data, status) }
            saved += try JSONDecoder().decode(Response.self, from: data).saved
        }
        return saved
    }

    /// Replaces the website's commits for each day and repository sent.
    ///
    /// The index state rides on the last batch, so it only ever says "complete" once everything it
    /// describes has actually arrived.
    @discardableResult
    func upload(_ work: [CloudWorkDay], index: CloudWorkIndex? = nil) async throws -> Int {
        struct Response: Decodable { let saved: Int }
        struct Body: Encodable {
            let days: [CloudWorkDay]
            let index: CloudWorkIndex?
        }
        var saved = 0
        // Subjects make these rows much larger than usage rows, so they go in smaller batches.
        let batches = max(1, Int(ceil(Double(work.count) / 200)))
        for batch in 0..<batches {
            let start = batch * 200
            let chunk = start < work.count ? Array(work[start..<min(start + 200, work.count)]) : []
            let last = batch == batches - 1
            let (data, status) = try await send("POST", "/api/work", body: Body(days: chunk, index: last ? index : nil))
            guard status == 200 else { throw problem(data, status) }
            saved += try JSONDecoder().decode(Response.self, from: data).saved
        }
        return saved
    }

    /// Takes the subjects down, for when subject sharing is turned off.
    func clearWorkSubjects() async throws {
        let (data, status) = try await send("DELETE", "/api/work/subjects")
        guard status == 200 || status == 401 else { throw problem(data, status) }
    }

    /// Replaces the readings the website holds for this person with these.
    @discardableResult
    func upload(_ limits: [CloudLimit]) async throws -> Int {
        struct Response: Decodable { let saved: Int }
        let (data, status) = try await send("POST", "/api/limits", body: ["limits": limits])
        guard status == 200 else { throw problem(data, status) }
        return try JSONDecoder().decode(Response.self, from: data).saved
    }

    /// Every current reading, for a linked phone.
    func limits() async throws -> CloudLimits {
        let (data, status) = try await send("GET", "/api/limits")
        guard status == 200 else { throw problem(data, status) }
        return try JSONDecoder().decode(CloudLimits.self, from: data)
    }

    /// Takes the readings down, for when limit sharing is turned off.
    func clearLimits() async throws {
        let (data, status) = try await send("DELETE", "/api/limits")
        guard status == 204 || status == 401 else { throw problem(data, status) }
    }

    func unlink() async throws {
        let (data, status) = try await send("DELETE", "/api/session")
        guard status == 204 || status == 401 else { throw problem(data, status) }
    }

    func leaderboard(period: String, metric: String, team: String?) async throws -> CloudBoard {
        var query = "period=\(period)&metric=\(metric)"
        if let team, let encoded = team.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) {
            query += "&team=\(encoded)"
        }
        let (data, status) = try await send("GET", "/api/leaderboard?\(query)")
        guard status == 200 else { throw problem(data, status) }
        return try JSONDecoder().decode(CloudBoard.self, from: data)
    }

    func season(team: String?) async throws -> CloudSeason {
        var query = ""
        if let team, let encoded = team.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) {
            query = "?team=\(encoded)"
        }
        let (data, status) = try await send("GET", "/api/season\(query)")
        guard status == 200 else { throw problem(data, status) }
        return try JSONDecoder().decode(CloudSeason.self, from: data)
    }

    func quests() async throws -> CloudQuests {
        let (data, status) = try await send("GET", "/api/quests")
        guard status == 200 else { throw problem(data, status) }
        return try JSONDecoder().decode(CloudQuests.self, from: data)
    }

    func teams() async throws -> [CloudTeam] {
        struct Response: Decodable { let teams: [CloudTeam] }
        let (data, status) = try await send("GET", "/api/teams")
        guard status == 200 else { throw problem(data, status) }
        return try JSONDecoder().decode(Response.self, from: data).teams
    }

    private func send<Body: Encodable>(_ method: String, _ path: String, body: Body?) async throws -> (Data, Int) {
        guard let url = URL(string: server.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw CloudError(kind: .server, message: "\(server) isn't a valid address.")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Keyhop/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        do {
            return try await Self.send(request)
        } catch {
            throw CloudError(kind: .server, message: "Couldn't reach Keyhop cloud: \(error.localizedDescription)")
        }
    }

    private func send(_ method: String, _ path: String) async throws -> (Data, Int) {
        try await send(method, path, body: Optional<[String: String]>.none)
    }

    /// The one request this file makes, on the completion-handler API every Foundation has. The Mac
    /// app's HTTP helper carries a curl fallback for static Linux builds; nothing here needs it, and
    /// keeping the call local is what lets another platform compile this file alone.
    private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
                }
            }.resume()
        }
    }

    private func problem(_ data: Data, _ status: Int) -> Error {
        if status == 401 { return CloudError.unlinked }
        struct Message: Decodable { let error: String }
        let message = (try? JSONDecoder().decode(Message.self, from: data))?.error ?? "Keyhop cloud answered with status \(status)."
        return CloudError(kind: .server, message: message)
    }
}
