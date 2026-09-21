import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Keyhop cloud: leaderboards, teams and public profiles. Linking signs in with GitHub in the
/// browser; after that Keyhop sends daily totals per tool (tokens, API value and requests) and
/// nothing else: no prompts, emails, account names or models.
///
/// Turning limit sharing on adds one thing to that, for people who want a phone to tell them when a
/// limit comes back: where each account stands right now against its limits, with the label they
/// typed for it. Still no emails, and still nothing about what was asked or written.
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
    /// Off until it is turned on. While it is on, Keyhop also sends where each account stands
    /// against its limits, so a linked phone can count down to the next reset.
    var sharesLimits: Bool
    var lastLimitSync: Date?

    static var url: URL { Platform.dataDirectory.appendingPathComponent("cloud.json") }

    var profileURL: String { "\(server)/u/\(login)" }

    init(server: String, token: String, login: String, name: String?, isPublic: Bool, linkedAt: Date,
         lastSync: Date? = nil, lastSyncError: String? = nil, sharesLimits: Bool = false, lastLimitSync: Date? = nil) {
        self.server = server
        self.token = token
        self.login = login
        self.name = name
        self.isPublic = isPublic
        self.linkedAt = linkedAt
        self.lastSync = lastSync
        self.lastSyncError = lastSyncError
        self.sharesLimits = sharesLimits
        self.lastLimitSync = lastLimitSync
    }

    private enum CodingKeys: String, CodingKey {
        case server, token, login, name, isPublic, linkedAt, lastSync, lastSyncError, sharesLimits, lastLimitSync
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
        sharesLimits = try values.decodeIfPresent(Bool.self, forKey: .sharesLimits) ?? false
        lastLimitSync = try values.decodeIfPresent(Date.self, forKey: .lastLimitSync)
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
        try values.encode(sharesLimits, forKey: .sharesLimits)
        try values.encodeIfPresent(lastLimitSync, forKey: .lastLimitSync)
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
    static func run(_ link: inout CloudLink, tracker: TrackerEngine, now: Date = Date(),
                    store: (any SecretStore)? = nil) async throws -> Int {
        let lookback = Double(link.lastSync == nil ? 370 : 8) * 86400
        let since = Calendar.current.startOfDay(for: now.addingTimeInterval(-lookback))
        let days = try await days(tracker: tracker, since: since, now: now)
        let saved = try await CloudClient(server: link.server, token: link.token).upload(days)
        link.lastSync = now
        link.lastSyncError = nil
        try link.save(store: store)
        return saved
    }

    /// Where each account stands right now, as a phone would read it. A window is worth sending when
    /// its provider reported it; an account that failed to read is left out rather than guessed at.
    ///
    /// Only the label a person typed travels. An account they never named sends no label at all,
    /// because the fallback on this computer is the email address, and that never leaves it.
    static func limits(accounts: [Account], usage: [UUID: UsageSnapshot], now: Date = Date()) -> [CloudLimit] {
        accounts.flatMap { account -> [CloudLimit] in
            guard let snapshot = usage[account.id], snapshot.error == nil else { return [] }
            let label = account.label.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            return snapshot.windows.compactMap { window in
                // A reset already in the past is a reading waiting to be refreshed, not a countdown.
                let resetsAt = window.resetsAt.flatMap { $0 > now ? Int($0.timeIntervalSince1970.rounded()) : nil }
                return CloudLimit(accountKey: account.id.uuidString, tool: account.provider.rawValue, label: label,
                                  windowLabel: window.label, usedPercent: min(max(window.usedPercent, 0), 100), resetsAt: resetsAt)
            }
        }
    }

    /// After a refresh: at most once an hour, and never in the way of the refresh itself. Limits go
    /// more often, because a countdown that is an hour old is no longer a countdown.
    ///
    /// The two are independent. Daily totals are the leaderboard, so they go first and nothing about
    /// limit sharing can stop them: a website that doesn't take limit readings yet, or refuses one,
    /// costs the phone its countdown and nothing else.
    static func syncIfDue(tracker: TrackerEngine, accounts: [Account] = [], usage: [UUID: UsageSnapshot] = [:],
                          now: Date = Date(), store: (any SecretStore)? = nil,
                          progress: ProgressHandler? = nil) async {
        guard var link = CloudLink.load(store: store) else { return }

        if link.lastSync.map({ now.timeIntervalSince($0) >= 3600 }) ?? true {
            do {
                try await run(&link, tracker: tracker, now: now, store: store)
            } catch let error as CloudError where error.kind == .unlinked {
                CloudLink.remove(store: store)
                return
            } catch {
                link.lastSyncError = error.localizedDescription
                try? link.save(store: store)
            }
        }

        // Commits go on the same hourly beat as the totals, and are just as independent: a website
        // that doesn't take them yet, or a git that isn't installed, costs the day its commits and
        // nothing else.
        var work = WorkSettings.load()
        if work.enabled, GitWork.isAvailable, work.lastSync.map({ now.timeIntervalSince($0) >= 3600 }) ?? true {
            do {
                try await runWork(&work, link: link, now: now, progress: progress)
            } catch let error as CloudError where error.kind == .unlinked {
                CloudLink.remove(store: store)
                return
            } catch {
                link.lastSyncError = "Sending commits failed: \(error.localizedDescription)"
                try? link.save(store: store)
            }
        }

        guard link.sharesLimits, link.lastLimitSync.map({ now.timeIntervalSince($0) >= 300 }) ?? true else { return }
        // Counted as an attempt either way, so a website that keeps refusing is asked every five
        // minutes rather than on every refresh.
        link.lastLimitSync = now
        do {
            try await CloudClient(server: link.server, token: link.token).upload(limits(accounts: accounts, usage: usage, now: now))
        } catch let error as CloudError where error.kind == .unlinked {
            CloudLink.remove(store: store)
            return
        } catch {
            link.lastSyncError = "Sharing limits failed: \(error.localizedDescription)"
        }
        try? link.save(store: store)
    }

    /// Reads this computer's repositories and sends what they say about the last stretch of days.
    ///
    /// The same eight-day window the usage sync uses, for the same reason: a day can still change
    /// after it ends, whether because a log arrived late or because the history was rewritten. Each
    /// day is restated rather than added to, so re-sending one corrects it.
    ///
    /// The index makes the pass after the first one cheap, and it is also what lets the website say
    /// a person's day is still filling in. Someone halfway through their first index has real
    /// numbers that are not yet the whole truth, and showing those as final would quietly tell
    /// their team they did less than they did.
    @discardableResult
    static func runWork(_ settings: inout WorkSettings, link: CloudLink, now: Date = Date(),
                        progress: ProgressHandler? = nil) async throws -> Int {
        let lookback = Double(settings.lastSync == nil ? 30 : 8) * 86400
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let since = formatter.string(from: now.addingTimeInterval(-lookback))

        let index = WorkIndex.load()
        let first = !index.isComplete
        let scan = GitWork.scan(roots: settings.rootURLs, since: since, emails: settings.emails,
                                login: link.login, shareSubjects: settings.shareSubjects,
                                index: index, progress: progress)
        try? scan.index.save()

        let client = CloudClient(server: link.server, token: link.token)
        let state = CloudWorkIndex(done: scan.index.done, total: scan.index.total, complete: scan.index.isComplete)
        // A pass that found nothing new still has something to say while a first index is running:
        // that it is running, and how far it has got.
        guard !scan.days.isEmpty || first else {
            settings.lastSync = now
            try? settings.save()
            return 0
        }
        let saved = try await client.upload(scan.days, index: state)
        settings.lastSync = now
        try settings.save()
        return saved
    }

    /// Turning subject sharing off takes the words off the website right away, not at the next sync.
    static func stopSharingSubjects(_ settings: inout WorkSettings, link: CloudLink) async throws {
        settings.shareSubjects = false
        try settings.save()
        try await CloudClient(server: link.server, token: link.token).clearWorkSubjects()
    }

    /// Turning limit sharing off takes the readings off the website too, right away.
    static func stopSharingLimits(_ link: inout CloudLink) async throws {
        link.sharesLimits = false
        link.lastLimitSync = nil
        try link.save()
        try await CloudClient(server: link.server, token: link.token).clearLimits()
    }
}
