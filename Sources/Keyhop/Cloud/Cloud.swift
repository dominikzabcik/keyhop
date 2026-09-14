import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Keyhop cloud: leaderboards, teams and public profiles. Linking signs in with GitHub in the
/// browser; after that Keyhop sends daily totals per tool (tokens, API value and requests) and
/// nothing else: no prompts, emails, account names or models.
enum Cloud {
    /// The deployed service. `KEYHOP_CLOUD_URL` points Keyhop at another one, like a local
    /// `npm run dev` in cloud/.
    static let defaultServer: String? = "https://keyhop.app"

    static var server: String? {
        if let override = ProcessInfo.processInfo.environment["KEYHOP_CLOUD_URL"], !override.isEmpty { return override }
        return CloudLink.load()?.server ?? defaultServer
    }

    /// How this computer shows up under Linked apps on the website.
    static var deviceLabel: String {
        var host = ProcessInfo.processInfo.hostName
        if host.hasSuffix(".local") { host.removeLast(6) }
        return host.isEmpty ? "Keyhop on \(Platform.name)" : "\(host) (\(Platform.name))"
    }
}

/// The link to a Keyhop cloud account. Metadata stays in `cloud.json`; the bearer token lives in
/// the system secret store alongside provider logins.
struct CloudLink: Codable, Equatable {
    private static let tokenService = "app.keyhop.cloud"
    private static let tokenAccount = "session"
    private static let standardStore: any SecretStore = SecretStores.standard(service: tokenService)

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

    init(server: String, token: String, login: String, name: String?, isPublic: Bool, linkedAt: Date,
         lastSync: Date? = nil, lastSyncError: String? = nil) {
        self.server = server
        self.token = token
        self.login = login
        self.name = name
        self.isPublic = isPublic
        self.linkedAt = linkedAt
        self.lastSync = lastSync
        self.lastSyncError = lastSyncError
    }

    private enum CodingKeys: String, CodingKey {
        case server, token, login, name, isPublic, linkedAt, lastSync, lastSyncError
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        server = try values.decode(String.self, forKey: .server)
        token = try values.decodeIfPresent(String.self, forKey: .token) ?? ""
        login = try values.decode(String.self, forKey: .login)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        isPublic = try values.decode(Bool.self, forKey: .isPublic)
        linkedAt = try values.decode(Date.self, forKey: .linkedAt)
        lastSync = try values.decodeIfPresent(Date.self, forKey: .lastSync)
        lastSyncError = try values.decodeIfPresent(String.self, forKey: .lastSyncError)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(server, forKey: .server)
        try values.encode(login, forKey: .login)
        try values.encodeIfPresent(name, forKey: .name)
        try values.encode(isPublic, forKey: .isPublic)
        try values.encode(linkedAt, forKey: .linkedAt)
        try values.encodeIfPresent(lastSync, forKey: .lastSync)
        try values.encodeIfPresent(lastSyncError, forKey: .lastSyncError)
    }

    static func load(store: (any SecretStore)? = nil) -> CloudLink? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard var link = try? DashboardJSON.decoder.decode(CloudLink.self, from: data) else { return nil }
        let credentials = store ?? standardStore
        if link.token.isEmpty {
            guard let saved = credentials.read(tokenAccount), !saved.isEmpty else { return nil }
            link.token = String(decoding: saved, as: UTF8.self)
            return link
        }
        do {
            try credentials.write(Data(link.token.utf8), account: tokenAccount)
            try link.writeMetadata()
        } catch {
            return link
        }
        return link
    }

    func save(store: (any SecretStore)? = nil) throws {
        let credentials = store ?? Self.standardStore
        try credentials.write(Data(token.utf8), account: Self.tokenAccount)
        try writeMetadata()
    }

    private func writeMetadata() throws {
        try FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
        try Files.writeAtomically(DashboardJSON.encoder.encode(self), to: Self.url)
        #if !os(Windows)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
        #endif
    }

    static func remove(store: (any SecretStore)? = nil) {
        (store ?? standardStore).delete(tokenAccount)
        try? FileManager.default.removeItem(at: url)
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
