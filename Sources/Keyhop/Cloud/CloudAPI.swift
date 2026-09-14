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

    func startLink(label: String) async throws -> LinkStart {
        let (data, status) = try await send("POST", "/api/device/start", body: ["label": label])
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
            return try await HTTP.send(request)
        } catch {
            throw CloudError(kind: .server, message: "Couldn't reach Keyhop cloud: \(error.localizedDescription)")
        }
    }

    private func send(_ method: String, _ path: String) async throws -> (Data, Int) {
        try await send(method, path, body: Optional<[String: String]>.none)
    }

    private func problem(_ data: Data, _ status: Int) -> Error {
        if status == 401 { return CloudError.unlinked }
        struct Message: Decodable { let error: String }
        let message = (try? JSONDecoder().decode(Message.self, from: data))?.error ?? "Keyhop cloud answered with status \(status)."
        return CloudError(kind: .server, message: message)
    }
}
