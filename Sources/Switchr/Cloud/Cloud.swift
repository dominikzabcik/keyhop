import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Switchr cloud: leaderboards, teams and public profiles. Linking signs in with GitHub in the
/// browser; after that Switchr sends daily totals per tool (tokens, API value and requests) and
/// nothing else: no prompts, emails, account names or models.
enum Cloud {
    /// The deployed service. `SWITCHR_CLOUD_URL` points Switchr at another one, like a local
    /// `npm run dev` in cloud/.
    static let defaultServer: String? = nil

    static var server: String? {
        if let override = ProcessInfo.processInfo.environment["SWITCHR_CLOUD_URL"], !override.isEmpty { return override }
        return CloudLink.load()?.server ?? defaultServer
    }

    /// How this computer shows up under Linked apps on the website.
    static var deviceLabel: String {
        var host = ProcessInfo.processInfo.hostName
        if host.hasSuffix(".local") { host.removeLast(6) }
        return host.isEmpty ? "Switchr on \(Platform.name)" : "\(host) (\(Platform.name))"
    }
}

struct CloudError: LocalizedError {
    enum Kind { case unlinked, expired, server }
    let kind: Kind
    let message: String

    var errorDescription: String? { message }

    static let unlinked = CloudError(kind: .unlinked, message: "This computer isn't linked to Switchr cloud anymore. Run switchr cloud login.")
}

/// The link to a Switchr cloud account, kept next to Switchr's other data and readable only by you.
struct CloudLink: Codable, Equatable {
    var server: String
    var token: String
    var login: String
    var name: String?
    var isPublic: Bool
    var linkedAt: Date
    var lastSync: Date?
    var lastSyncError: String?

    static var url: URL { Platform.dataDirectory.appendingPathComponent("cloud.json") }

    var profileURL: String { "\(server)/u/\(login)" }

    static func load() -> CloudLink? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? DashboardJSON.decoder.decode(CloudLink.self, from: data)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
        try Files.writeAtomically(DashboardJSON.encoder.encode(self), to: Self.url)
        #if !os(Windows)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
        #endif
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }
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
        request.setValue("Switchr/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        do {
            return try await HTTP.send(request)
        } catch {
            throw CloudError(kind: .server, message: "Couldn't reach Switchr cloud: \(error.localizedDescription)")
        }
    }

    private func send(_ method: String, _ path: String) async throws -> (Data, Int) {
        try await send(method, path, body: Optional<[String: String]>.none)
    }

    private func problem(_ data: Data, _ status: Int) -> Error {
        if status == 401 { return CloudError.unlinked }
        struct Message: Decodable { let error: String }
        let message = (try? JSONDecoder().decode(Message.self, from: data))?.error ?? "Switchr cloud answered with status \(status)."
        return CloudError(kind: .server, message: message)
    }
}

enum CloudSync {
    /// Daily totals per tool, in this computer's local days.
    static func days(tracker: TrackerEngine, since: Date, now: Date = Date()) async throws -> [CloudDay] {
        let interval = DateInterval(start: since, end: max(since, now).addingTimeInterval(60))
        let digest = try await tracker.digest(interval: interval, previous: interval, bucket: .day, provider: nil, sole: [:])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        var sums: [String: (tokens: Int, cost: Double, requests: Int)] = [:]
        for point in digest.points {
            let key = "\(formatter.string(from: point.start))|\(point.key.provider.rawValue)"
            var sum = sums[key] ?? (0, 0, 0)
            sum.tokens += point.totals.tokens.total
            sum.cost += point.totals.cost
            sum.requests += point.totals.requests
            sums[key] = sum
        }
        return sums
            .filter { $0.value.tokens > 0 || $0.value.requests > 0 }
            .map { key, sum in
                let parts = key.split(separator: "|")
                return CloudDay(day: String(parts[0]), tool: String(parts[1]), tokens: sum.tokens,
                                cost: (sum.cost * 100).rounded() / 100, requests: sum.requests)
            }
            .sorted { ($0.day, $0.tool) < ($1.day, $1.tool) }
    }

    /// Sends a year the first time, then the last eight days, since logs can arrive late.
    @discardableResult
    static func run(_ link: inout CloudLink, tracker: TrackerEngine, now: Date = Date()) async throws -> Int {
        let lookback = Double(link.lastSync == nil ? 370 : 8) * 86400
        let since = Calendar.current.startOfDay(for: now.addingTimeInterval(-lookback))
        let days = try await days(tracker: tracker, since: since, now: now)
        let saved = try await CloudClient(server: link.server, token: link.token).upload(days)
        link.lastSync = now
        link.lastSyncError = nil
        try link.save()
        return saved
    }

    /// After a refresh: at most once an hour, and never in the way of the refresh itself.
    static func syncIfDue(tracker: TrackerEngine, now: Date = Date()) async {
        guard var link = CloudLink.load() else { return }
        if let last = link.lastSync, now.timeIntervalSince(last) < 3600 { return }
        do {
            try await run(&link, tracker: tracker, now: now)
        } catch let error as CloudError where error.kind == .unlinked {
            CloudLink.remove()
        } catch {
            link.lastSyncError = error.localizedDescription
            try? link.save()
        }
    }
}
