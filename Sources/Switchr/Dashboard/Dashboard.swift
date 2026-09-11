import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `switchr dashboard`: one app page and a small JSON API, served to this computer only. The Linux
/// and Windows trays open it as Switchr's window, and `switchr insights --output` saves it as one
/// file with its data inside.
///
/// Only a window opened with the random token can use the API: every call needs it, the Host header
/// must be the loopback address (against DNS rebinding), and a cross-site page can't send the JSON
/// requests that change anything.
enum Dashboard {
    struct Launch: Codable {
        let port: UInt16
        let token: String
    }

    static let sections = ["overview", "accounts", "usage", "budgets", "settings"]

    private static var launchFile: URL { Platform.dataDirectory.appendingPathComponent("dashboard.json") }

    static func address(port: UInt16, token: String, section: String) -> String {
        "http://127.0.0.1:\(port)/#s=\(section)&k=\(token)"
    }

    /// Opens the dashboard, starting its server unless one is already running, and returns once the
    /// server stops: 15 minutes after its last window closed, or when a tray closes it.
    static func run(sample: Bool, section: String, open: Bool, json: Bool) async throws {
        if !sample, let running = await reachable() {
            announce(address(port: running.port, token: running.token, section: section), open: open, json: json, started: false)
            return
        }
        let session = try DashboardSession(sample: sample)
        let token = randomToken()
        let server = try LoopbackServer()
        let port = server.port
        server.start { request in await session.respond(to: request, token: token, port: port) }
        if !sample {
            try? FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
            try Files.writeAtomically(DashboardJSON.encoder.encode(Launch(port: port, token: token)), to: launchFile)
        }
        announce(address(port: port, token: token, section: section), open: open, json: json, started: true)
        await session.waitUntilDone(idleLimit: 15 * 60)
        server.stop()
        if !sample { try? FileManager.default.removeItem(at: launchFile) }
    }

    /// The dashboard as one self-contained file.
    static func staticPage(sample: Bool, readLogs: Bool) async throws -> String {
        let session = try DashboardSession(sample: sample)
        let boot = try await session.bootDocument(readLogs: readLogs)
        return DashboardPage.render(boot: String(decoding: try DashboardJSON.encoder.encode(boot), as: UTF8.self))
    }

    private static func announce(_ address: String, open: Bool, json: Bool, started: Bool) {
        if json {
            print(#"{"url":"\#(address)"}"#)
        } else if started {
            print("Switchr is open at \(address)")
            print("It keeps running while a window is open, and stops 15 minutes after the last one closes.")
        } else if !open {
            print(address)
        }
        fflush(nil)
        if open { DashboardWindow.open(address) }
    }

    private static func reachable() async -> Launch? {
        guard let data = try? Data(contentsOf: launchFile),
              let launch = try? DashboardJSON.decoder.decode(Launch.self, from: data),
              let url = URL(string: "http://127.0.0.1:\(launch.port)/api/ping") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.setValue("Bearer \(launch.token)", forHTTPHeaderField: "Authorization")
        guard let (_, status) = try? await HTTP.send(request), status == 200 else { return nil }
        return launch
    }

    static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<4).map { _ in
            let hex = String(generator.next() as UInt64, radix: 16)
            return String(repeating: "0", count: 16 - hex.count) + hex
        }.joined()
    }
}

enum DashboardJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Who may use the API.
enum DashboardAccess {
    static func hostIsLocal(_ host: String?, port: UInt16) -> Bool {
        host == "127.0.0.1:\(port)" || host == "localhost:\(port)"
    }

    /// Nil when the request may proceed, otherwise why not.
    static func problem(with request: HTTPRequest, token: String, port: UInt16) -> String? {
        guard hostIsLocal(request.headers["host"], port: port) else { return "This dashboard only answers on 127.0.0.1." }
        guard constantTimeEqual(request.headers["authorization"] ?? "", "Bearer \(token)") else {
            return "This window's session ended. Open Switchr again."
        }
        if let origin = request.headers["origin"], origin != "http://127.0.0.1:\(port)", origin != "http://localhost:\(port)" {
            return "Requests from other sites aren't allowed."
        }
        if request.method != "GET", !(request.headers["content-type"] ?? "").lowercased().hasPrefix("application/json") {
            return "Changes must be sent as JSON."
        }
        return nil
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8), right = Array(b.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// Opens the dashboard as an app window where the system allows it: a Chromium-family browser's
/// app mode (Edge ships with Windows), otherwise the default browser.
enum DashboardWindow {
    static func open(_ address: String) {
        let size = "--window-size=1360,900"
        #if os(Windows)
        let environment = ProcessInfo.processInfo.environment
        let edge = [environment["ProgramFiles(x86)"], environment["ProgramFiles"], environment["LOCALAPPDATA"]]
            .compactMap { $0 }
            .map { $0 + "\\Microsoft\\Edge\\Application\\msedge.exe" }
            .first { FileManager.default.fileExists(atPath: $0) }
        if let edge {
            Shell.launchDetached(edge, ["--app=\(address)", size])
            return
        }
        #elseif os(Linux)
        for name in ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge", "brave-browser"] {
            if let browser = Shell.which(name) {
                Shell.launchDetached(browser, ["--app=\(address)", size])
                return
            }
        }
        #endif
        _ = Desktop.open(address)
    }
}

// MARK: Documents

struct DashboardState: Encodable {
    /// live, sample or static.
    let mode: String
    let version: String
    let platform: String
    let dataDirectory: String
    let savedAt: Date
    let status: StatusDocument
    let adding: [String]
    let refreshing: Bool
    let messages: [String]
}

struct DashboardAction: Encodable {
    let message: String
    let note: String?
}

struct DashboardError: Encodable {
    let error: String
}

struct DashboardBoot: Encodable {
    let mode: String
    let section: String
    let state: DashboardState
    let usage: [String: DashboardUsage]
}

/// Everything the Usage section and the Overview's charts show for one range.
struct DashboardUsage: Encodable {
    struct Figures: Encodable {
        let tokens: Int
        let requests: Int
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
        let cost: Double
        let billed: Double

        init(_ totals: Totals) {
            tokens = totals.tokens.total
            requests = totals.requests
            input = totals.tokens.input
            output = totals.tokens.output
            cacheRead = totals.tokens.cacheRead
            cacheWrite = totals.tokens.cacheWrite + totals.tokens.cacheWrite1h
            cost = totals.cost
            billed = totals.billed
        }
    }

    struct Series: Encodable, Hashable {
        let id: String
        let name: String
        let tool: String
        let color: String
        let order: Int
    }

    struct Value: Encodable {
        var tokens = 0
        var cost = 0.0
    }

    struct Bucket: Encodable {
        let start: Date
        let values: [String: Value]
    }

    struct AccountRow: Encodable {
        let series: String
        let color: String
        let id: UUID?
        let tool: String
        let name: String
        let email: String?
        let plan: String?
        let active: Bool
        let figures: Figures
    }

    struct ModelRow: Encodable {
        let model: String
        let figures: Figures
    }

    struct Day: Encodable, Equatable {
        let day: String
        let tokens: Int
        let cost: Double
        let requests: Int
    }

    struct Streak: Encodable, Equatable {
        let current: Int
        let longest: Int
        let activeDays: Int
    }

    let range: String
    let title: String
    let bucket: String
    let tool: String
    let start: Date
    let end: Date
    let total: Figures
    let previous: Figures
    let series: [Series]
    let buckets: [Bucket]
    let accounts: [AccountRow]
    let models: [ModelRow]
    let heatmap: [Day]
    let streak: Streak

    /// Same fixed order as the Mac app, validated for color-vision and normal-vision separation on
    /// the enamel surface. Accounts past the fourth share the neutral.
    static let seriesColors = ["#C9821A", "#2F6FC0", "#B8423F", "#1E9A78"]
    static let otherColor = "#8A8A86"

    init(range: InsightsRange, tool: Provider?, now: Date, digest: UsageDigest, daily: UsageDigest, accounts: [Account], active: [Provider: UUID]) {
        let interval = range.interval(now: now)
        self.range = range.argument
        title = range.title
        bucket = range.bucket == .hour ? "hour" : "day"
        self.tool = tool?.rawValue ?? "all"
        start = interval.start
        end = interval.end
        total = Figures(digest.total)
        previous = Figures(digest.previous)

        let calendar = Calendar.current
        let keyFormat = DateFormatter()
        keyFormat.locale = Locale(identifier: "en_US_POSIX")
        keyFormat.dateFormat = range.bucket.dateFormat

        var values: [String: [String: Value]] = [:]
        var seen: Set<Series> = []
        for point in digest.points {
            let entry = Self.series(for: point.key, accounts: accounts)
            seen.insert(entry)
            var value = values[keyFormat.string(from: point.start), default: [:]][entry.id, default: Value()]
            value.tokens += point.totals.tokens.total
            value.cost += point.totals.cost
            values[keyFormat.string(from: point.start), default: [:]][entry.id] = value
        }
        series = seen.sorted { ($0.order, $0.id) < ($1.order, $1.id) }

        var buckets: [Bucket] = []
        var cursor = interval.start
        let component: Calendar.Component = range.bucket == .hour ? .hour : .day
        while cursor < interval.end, buckets.count < 800 {
            buckets.append(Bucket(start: cursor, values: values[keyFormat.string(from: cursor)] ?? [:]))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }
        self.buckets = buckets

        self.accounts = digest.byAccount
            .sorted { $0.value.tokens.total > $1.value.tokens.total }
            .map { key, totals in
                let entry = Self.series(for: key, accounts: accounts)
                let account = key.account.flatMap { id in accounts.first { $0.id == id } }
                return AccountRow(series: entry.id, color: entry.color, id: key.account, tool: key.provider.rawValue,
                                  name: account?.displayName ?? "Earlier or removed", email: account?.email, plan: account?.plan,
                                  active: account.map { active[key.provider] == $0.id } ?? false, figures: Figures(totals))
            }
        models = digest.byModel
            .sorted { $0.value.tokens.total > $1.value.tokens.total }
            .map { ModelRow(model: $0.key, figures: Figures($0.value)) }

        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.dateFormat = "yyyy-MM-dd"
        var perDay: [String: (tokens: Int, cost: Double, requests: Int)] = [:]
        for point in daily.points {
            let key = dayFormat.string(from: point.start)
            let earlier = perDay[key] ?? (0, 0, 0)
            perDay[key] = (earlier.tokens + point.totals.tokens.total, earlier.cost + point.totals.cost, earlier.requests + point.totals.requests)
        }
        var days: [Day] = []
        let heat = Self.heatmapInterval(now: now)
        var day = heat.start
        while day < heat.end, days.count < 400 {
            let key = dayFormat.string(from: day)
            let figures = perDay[key] ?? (0, 0, 0)
            days.append(Day(day: key, tokens: figures.tokens, cost: figures.cost, requests: figures.requests))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        heatmap = days
        streak = Self.streak(days: days, today: dayFormat.string(from: now))
    }

    /// 26 weeks ending this week, starting on a Monday.
    static func heatmapInterval(now: Date) -> DateInterval {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = calendar.date(byAdding: .weekOfYear, value: -25, to: weekStart) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return DateInterval(start: start, end: end)
    }

    /// Days in a row with usage, counting back from today, or from yesterday while today is still quiet.
    static func streak(days: [Day], today: String) -> Streak {
        var longest = 0, run = 0, active = 0
        for day in days {
            if day.requests > 0 {
                run += 1
                active += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        var current = 0
        for day in days.reversed() {
            if day.requests > 0 {
                current += 1
            } else if current == 0, day.day == today {
                continue
            } else {
                break
            }
        }
        return Streak(current: current, longest: longest, activeDays: active)
    }

    static func series(for key: AccountKey, accounts: [Account]) -> Series {
        guard let id = key.account, let index = accounts.firstIndex(where: { $0.id == id }) else {
            return Series(id: "earlier-\(key.provider.rawValue)", name: "\(key.provider.shortName), earlier or removed",
                          tool: key.provider.rawValue, color: otherColor, order: 10_000)
        }
        if index >= seriesColors.count, accounts.count > seriesColors.count + 1 {
            return Series(id: "other", name: "Other accounts", tool: key.provider.rawValue, color: otherColor, order: 9_000)
        }
        let account = accounts[index]
        return Series(id: account.id.uuidString, name: "\(account.provider.shortName), \(account.displayName)",
                      tool: account.provider.rawValue, color: index < seriesColors.count ? seriesColors[index] : otherColor, order: index)
    }
}

// MARK: Session

/// Answers the dashboard's requests. Each request opens the saved data afresh, as a `switchr`
/// command would, so changes made by a tray, the Mac app or a terminal show up right away.
actor DashboardSession {
    let sample: Bool
    private var lastSeen = Date()
    private var closed = false
    private var refreshing = false
    private var adding: [Provider: Task<Void, Never>] = [:]
    private var messages: [String] = []
    private var lastIngest: Date?

    init(sample: Bool) throws {
        self.sample = sample
        if !sample { _ = try Workspace.open() }
    }

    func waitUntilDone(idleLimit: TimeInterval) async {
        while !closed, Date().timeIntervalSince(lastSeen) < idleLimit {
            try? await Task.sleep(for: .seconds(5))
        }
    }

    func respond(to request: HTTPRequest, token: String, port: UInt16) async -> HTTPResponse {
        if request.method == "GET", request.path == "/" {
            guard DashboardAccess.hostIsLocal(request.headers["host"], port: port) else { return .text("Forbidden", status: 403) }
            lastSeen = Date()
            return .html(DashboardPage.render(boot: nil))
        }
        guard request.path.hasPrefix("/api/") else { return .text("Not found", status: 404) }
        if let problem = DashboardAccess.problem(with: request, token: token, port: port) {
            return .json(DashboardError(error: problem), status: 403)
        }
        lastSeen = Date()
        do {
            switch (request.method, request.path) {
            case ("GET", "/api/ping"):
                return .json(DashboardAction(message: "ok", note: nil))
            case ("GET", "/api/state"):
                return .json(try await state(allowRefresh: true))
            case ("POST", "/api/refresh"):
                try await refresh()
                return .json(try await state(allowRefresh: false))
            case ("POST", "/api/switch"):
                return .json(try await switchAccount(try Self.decode(IDBody.self, request).id))
            case ("POST", "/api/add"):
                return .json(try await add(try Self.decode(ToolBody.self, request).tool))
            case ("POST", "/api/rename"):
                let body = try Self.decode(RenameBody.self, request)
                return .json(try await rename(body.id, to: body.name))
            case ("POST", "/api/remove"):
                return .json(try await remove(try Self.decode(IDBody.self, request).id))
            case ("POST", "/api/budget"):
                return .json(try await budget(try Self.decode(BudgetBody.self, request)))
            case ("GET", "/api/usage"):
                guard let range = InsightsRange(argument: request.query["range"] ?? "week") else { throw UsageError("Unknown range.") }
                let word = request.query["tool"] ?? "all"
                let tool = word == "all" ? nil : try Commands.tool(word)
                return .json(try await usage(range: range, tool: tool, readLogs: true))
            case ("GET", "/api/doctor"):
                return .json(await Commands.doctorDocument(sample: sample))
            case ("GET", "/api/update"):
                return .json(try await checkUpdate())
            case ("POST", "/api/update"):
                return .json(try await installUpdate())
            case ("POST", "/api/close"):
                closed = true
                return .json(DashboardAction(message: "Closed", note: nil))
            default:
                return .json(DashboardError(error: "Unknown request."), status: 404)
            }
        } catch let error as UsageError {
            return .json(DashboardError(error: error.message), status: 400)
        } catch {
            return .json(DashboardError(error: error.localizedDescription), status: 409)
        }
    }

    // MARK: Reading

    func state(allowRefresh: Bool) async throws -> DashboardState {
        let overview: Overview
        if sample {
            overview = SampleData.overview()
        } else {
            let workspace = try Workspace.open()
            if allowRefresh, workspace.state.refreshedAt == nil, !refreshing {
                Task { try? await self.refresh() }
            }
            overview = try await Commands.currentOverview(workspace)
        }
        let pending = messages
        messages.removeAll()
        return DashboardState(mode: sample ? "sample" : "live", version: AppVersion.current, platform: Platform.name,
                              dataDirectory: Platform.dataDirectory.path, savedAt: Date(), status: StatusDocument(overview),
                              adding: adding.keys.map(\.rawValue).sorted(), refreshing: refreshing, messages: pending)
    }

    func usage(range: InsightsRange, tool: Provider?, readLogs: Bool) async throws -> DashboardUsage {
        let now = Date()
        let heat = DashboardUsage.heatmapInterval(now: now)
        if sample {
            let everyone = SampleData.accounts(now: now)
            let accounts = everyone.filter { tool == nil || $0.provider == tool }
            return DashboardUsage(range: range, tool: tool, now: now,
                                  digest: SampleData.digest(range: range, accounts: accounts, now: now),
                                  daily: SampleData.digest(interval: heat, bucket: .day, accounts: accounts, now: now),
                                  accounts: everyone, active: SampleData.overview(now: now).active)
        }
        let workspace = try Workspace.open()
        if readLogs, lastIngest.map({ now.timeIntervalSince($0) > 120 }) ?? true {
            _ = try await workspace.tracker.ingestLocalLogs()
            lastIngest = now
        }
        let sole = await workspace.service.soleAccounts
        let digest = try await workspace.tracker.digest(interval: range.interval(now: now), previous: range.previous(now: now),
                                                        bucket: range.bucket, provider: tool, sole: sole)
        let daily = try await workspace.tracker.digest(interval: heat, previous: heat, bucket: .day, provider: tool, sole: sole)
        return DashboardUsage(range: range, tool: tool, now: now, digest: digest, daily: daily,
                              accounts: await workspace.service.accounts, active: workspace.state.activeByTool)
    }

    func bootDocument(readLogs: Bool) async throws -> DashboardBoot {
        var ranges: [String: DashboardUsage] = [:]
        for range in InsightsRange.allCases {
            ranges[range.argument] = try await usage(range: range, tool: nil, readLogs: readLogs && range == .today)
        }
        let current = try await state(allowRefresh: false)
        return DashboardBoot(mode: "static", section: "usage", state: current, usage: ranges)
    }

    // MARK: Changes

    private struct IDBody: Decodable { let id: UUID }
    private struct ToolBody: Decodable { let tool: String }
    private struct RenameBody: Decodable {
        let id: UUID
        let name: String
    }

    struct BudgetBody: Decodable {
        let scope: String
        let amount: Double?
        let period: String?
    }

    private static func decode<Body: Decodable>(_ type: Body.Type, _ request: HTTPRequest) throws -> Body {
        do {
            return try JSONDecoder().decode(type, from: request.body)
        } catch {
            throw UsageError("That request was incomplete.")
        }
    }

    private func refuseInSample() throws {
        if sample { throw SwitchrError("This is sample data, so nothing changes. Run switchr dashboard without --sample for your accounts.") }
    }

    func refresh() async throws {
        guard !sample, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        var workspace = try Workspace.open()
        _ = try await Commands.performRefresh(&workspace, claimAlerts: false)
        lastIngest = Date()
    }

    private func switchAccount(_ id: UUID) async throws -> DashboardAction {
        try refuseInSample()
        var workspace = try Workspace.open()
        let account = try await workspace.service.switchTo(id)
        let inUse = await workspace.service.active[account.provider]
        try await workspace.tracker.noteActive(account.provider, account: inUse, at: Date())
        workspace.state.active[account.provider.rawValue] = inUse?.uuidString
        workspace.state.save()
        return DashboardAction(message: "Switched \(account.provider.name) to \(account.displayName).", note: account.provider.switchNote.map(Output.plain))
    }

    private func add(_ word: String) async throws -> DashboardAction {
        try refuseInSample()
        let provider = try Commands.tool(word)
        guard adding[provider] == nil else {
            return DashboardAction(message: "Already waiting for a new \(provider.name) login.", note: nil)
        }
        let workspace = try Workspace.open()
        _ = try await workspace.service.signOutForAdding(provider)
        var state = CLIState.load()
        state.active[provider.rawValue] = nil
        state.save()
        adding[provider] = Task {
            let result = await workspace.service.waitForLogin(provider)
            await self.finishAdding(provider, result: result, workspace: workspace)
        }
        return DashboardAction(message: "Signed \(provider.name) out on this computer.", note: Output.plain(provider.signInHint))
    }

    private func finishAdding(_ provider: Provider, result: (outcome: AccountService.SyncOutcome, alreadySaved: Bool)?, workspace: Workspace) async {
        adding[provider] = nil
        guard let result else {
            messages.append("No new \(provider.name) login arrived. Sign in, then add it again.")
            return
        }
        switch result.outcome {
        case .saved(let id), .current(let id):
            let email = await workspace.service.account(id)?.email ?? "The account"
            messages.append(result.alreadySaved ? "\(email) was already saved." : "Saved \(email) to \(provider.name).")
            try? await workspace.tracker.noteActive(provider, account: id, at: Date())
            var state = CLIState.load()
            state.active[provider.rawValue] = id.uuidString
            state.save()
        case .failed(let problem):
            messages.append(problem)
        case .signedOut:
            break
        }
    }

    private func rename(_ id: UUID, to name: String) async throws -> DashboardAction {
        try refuseInSample()
        let workspace = try Workspace.open()
        guard let account = await workspace.service.account(id) else { throw SwitchrError("That account isn't saved.") }
        await workspace.service.rename(id, to: name)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return DashboardAction(message: trimmed.isEmpty ? "\(account.email) shows its email again." : "Named \(account.email) \"\(trimmed)\".", note: nil)
    }

    private func remove(_ id: UUID) async throws -> DashboardAction {
        try refuseInSample()
        let workspace = try Workspace.open()
        guard let account = await workspace.service.account(id) else { throw SwitchrError("That account isn't saved.") }
        try await workspace.service.remove(id)
        return DashboardAction(message: "Removed \(account.displayName) from \(account.provider.name) and deleted its saved login.", note: nil)
    }

    private func budget(_ body: BudgetBody) async throws -> DashboardAction {
        try refuseInSample()
        let workspace = try Workspace.open()
        let scope: String
        let name: String
        if body.scope == Budget.everything {
            scope = Budget.everything
            name = "all accounts"
        } else {
            guard let id = UUID(uuidString: body.scope), let account = await workspace.service.account(id) else {
                throw SwitchrError("That account isn't saved.")
            }
            scope = Budget.scope(for: id)
            name = account.displayName
        }
        guard let amount = body.amount, amount > 0 else {
            try await workspace.tracker.setBudget(nil, scope: scope)
            return DashboardAction(message: "Removed the budget for \(name).", note: nil)
        }
        guard let period = BudgetPeriod(rawValue: body.period ?? "month") else { throw UsageError("Choose day, week or month.") }
        try await workspace.tracker.setBudget(Budget(scope: scope, amount: amount, period: period), scope: scope)
        return DashboardAction(message: "Budget for \(name): \(Numbers.usd(amount)) \(period.title) at API prices.", note: nil)
    }

    private func checkUpdate() async throws -> UpdateDocument {
        let release = try await Releases.latest()
        return UpdateDocument(current: AppVersion.current, latest: release.version,
                              available: Releases.isNewer(release.version, than: AppVersion.current), page: release.page)
    }

    private func installUpdate() async throws -> DashboardAction {
        try refuseInSample()
        let release = try await Releases.latest()
        guard Releases.isNewer(release.version, than: AppVersion.current) else {
            return DashboardAction(message: "Switchr \(AppVersion.current) is the latest version.", note: nil)
        }
        #if os(macOS)
        return DashboardAction(message: "The Mac app installs Switchr \(release.version) itself. Click the version number in its menu to check now.", note: nil)
        #else
        #if os(Windows)
        if let path = Bundle.main.executableURL?.path.lowercased(), path.contains("\\scoop\\apps\\") || path.contains("/scoop/apps/") {
            throw SwitchrError("Switchr was installed with Scoop, so update it there: scoop update switchr")
        }
        let how = try await WindowsInstaller.install(release, quiet: true)
        #else
        let how = try await LinuxInstaller.install(release, quiet: true)
        #endif
        return DashboardAction(message: "Installed Switchr \(release.version) \(how).", note: "Reopen Switchr to use it.")
        #endif
    }
}
