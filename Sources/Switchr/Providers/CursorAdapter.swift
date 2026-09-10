import AppKit
import Foundation
import SQLite3

/// Cursor keeps its login in `state.vscdb` (the `cursorAuth/*` rows) and mirrors the account
/// into `~/.cursor/cli-config.json` for cursor-agent. A running Cursor holds the login in
/// memory, so it gets new tokens through its own login deep link instead of the database.
struct CursorAdapter: ProviderAdapter {
    let provider = Provider.cursor
    private static let bundleID = "com.todesktop.230313mzl4w4u92"
    private static let keys = [
        "cursorAuth/accessToken",
        "cursorAuth/refreshToken",
        "cursorAuth/cachedEmail",
        "cursorAuth/cachedSignUpType",
        "cursorAuth/cachedScopedProfile",
        "cursorAuth/stripeMembershipType",
        "cursorAuth/stripeMembershipAuthId",
        "cursorAuth/stripeSubscriptionStatus",
    ]

    private var database: ItemTable {
        ItemTable(url: Files.home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb"))
    }
    private var cliConfigURL: URL { Files.home.appendingPathComponent(".cursor/cli-config.json") }

    func readLive() async throws -> LiveLogin? {
        guard FileManager.default.fileExists(atPath: database.url.path) else { return nil }
        let rows = try database.read(Self.keys)
        guard let token = rows["cursorAuth/accessToken"],
              let subject = JWT.claims(token)?["sub"] as? String else { return nil }
        var secret = rows
        if let authInfo = (try? Data(contentsOf: cliConfigURL)).flatMap({ JSON.object($0) })?["authInfo"] {
            secret["cliAuthInfo"] = try? JSON.string(authInfo)
        }
        return LiveLogin(
            identity: subject,
            email: rows["cursorAuth/cachedEmail"] ?? "",
            plan: rows["cursorAuth/stripeMembershipType"].map(Self.planName),
            secret: secret,
            // Cached separately from the token, so it can lag behind a switch.
            emailTrusted: false
        )
    }

    func apply(_ secret: Secret) async throws {
        guard let access = secret["cursorAuth/accessToken"], let refresh = secret["cursorAuth/refreshToken"] else {
            throw SwitchrError("Saved Cursor login is damaged")
        }
        if let authInfo = JSON.object(secret["cliAuthInfo"]) {
            try updateCLIConfig { $0["authInfo"] = authInfo }
        }

        if isRunning, await handOff(access: access, refresh: refresh) {
            // The login route doesn't touch the cached profile, so fill in the new account's.
            var profile: [String: String?] = [:]
            for key in ["cursorAuth/cachedEmail", "cursorAuth/cachedSignUpType"] where secret[key] != nil {
                profile[key] = secret[key]
            }
            try? database.write(profile)
            return
        }

        // Cursor is closed, or it didn't take the hand-off: swap the rows directly.
        let wasRunning = try await quitCursor()
        var rows: [String: String?] = [:]
        for key in Self.keys { rows[key] = secret[key] }
        try database.write(rows)
        if wasRunning { openCursor() }
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    /// Gives the tokens to the running Cursor through its own login deep link, the route its
    /// browser sign-in finishes on, so it switches accounts in place without a restart.
    /// Returns true once Cursor has persisted the new token.
    private func handOff(access: String, refresh: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "cursor"
        components.host = "cursorAuth"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "route", value: "login"),
            URLQueryItem(name: "accessToken", value: access),
            URLQueryItem(name: "refreshToken", value: refresh),
        ]
        guard let url = components.url,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        } catch {
            return false
        }
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if (try? database.read(["cursorAuth/accessToken"]))?["cursorAuth/accessToken"] == access { return true }
        }
        return false
    }

    func signOutLocally() async throws {
        _ = try await quitCursor()
        var rows: [String: String?] = [:]
        for key in Self.keys { rows[key] = .some(nil) }
        try database.write(rows)
        try updateCLIConfig { $0.removeValue(forKey: "authInfo") }
        openCursor()
    }

    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> UsageReport {
        guard let token = secret["cursorAuth/accessToken"], let subject = JWT.claims(token)?["sub"] as? String else {
            throw SwitchrError("Saved Cursor login is damaged")
        }
        if let expiry = JWT.expiry(token), expiry < Date() {
            throw SwitchrError("Login expired. Switch to it and sign in to Cursor again.")
        }
        let (data, status) = try await HTTP.get("https://cursor.com/api/usage-summary", headers: [
            "Cookie": "WorkosCursorSessionToken=\(Self.cookieSubject(subject))%3A%3A\(token)",
            "Accept": "application/json",
            "Referer": "https://www.cursor.com/settings",
        ])
        switch status {
        case 200: break
        case 401, 403: throw SwitchrError("Cursor rejected this login. Sign in again.")
        default: throw SwitchrError("Cursor usage returned \(status)")
        }
        guard let body = JSON.object(data) else { throw SwitchrError("Unreadable Cursor usage response") }
        return UsageReport(windows: Self.windows(body), plan: (body["membershipType"] as? String).map(Self.planName))
    }

    /// Every request in the account's usage export, priced. Cursor keeps no local usage logs,
    /// so this is where its token counts come from.
    func usageExport(_ secret: Secret, account: UUID) async throws -> [UsageRecord] {
        guard let token = secret["cursorAuth/accessToken"], let subject = JWT.claims(token)?["sub"] as? String else {
            throw SwitchrError("Saved Cursor login is damaged")
        }
        let (data, status) = try await HTTP.get("https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens", headers: [
            "Cookie": "WorkosCursorSessionToken=\(Self.cookieSubject(subject))%3A%3A\(token)",
            "Accept": "text/csv",
            "Referer": "https://www.cursor.com/settings",
        ])
        guard status == 200 else { throw SwitchrError("Cursor usage export returned \(status)") }

        let rows = CSV.rows(String(decoding: data, as: UTF8.self))
        guard let header = rows.first else { return [] }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let date = column("Date"), let model = column("Model"),
              let inputWithWrites = column("Input (w/ Cache Write)"), let inputWithoutWrites = column("Input (w/o Cache Write)"),
              let cacheRead = column("Cache Read"), let output = column("Output Tokens"), let cost = column("Cost") else {
            throw SwitchrError("Cursor changed its usage export")
        }
        let kind = column("Kind")

        return rows.dropFirst().compactMap { row -> UsageRecord? in
            guard row.count == header.count, let timestamp = Dates.parse(row[date]) else { return nil }
            if let kind, row[kind].localizedCaseInsensitiveContains("errored") { return nil }
            func count(_ index: Int) -> Int { Int(Double(row[index].replacingOccurrences(of: ",", with: "")) ?? 0) }

            var tokens = TokenCounts()
            tokens.input = count(inputWithoutWrites)
            tokens.cacheWrite = max(count(inputWithWrites) - count(inputWithoutWrites), 0)
            tokens.cacheRead = count(cacheRead)
            tokens.output = count(output)
            // "Included" and "Free" rows cost nothing extra; on-demand rows carry a dollar amount.
            let charged = Double(row[cost].replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces))
            let atApiPrices = Pricing.cost(model: row[model], tokens: tokens)
            return UsageRecord(
                key: "cursor:\(account.uuidString):\(row[date]):\(row[model]):\(tokens.total)",
                provider: .cursor, account: account, session: nil, kind: .request, timestamp: timestamp,
                model: row[model], tokens: tokens, cost: atApiPrices > 0 ? atApiPrices : (charged ?? 0), billed: charged
            )
        }
    }

    /// Cursor meters usage per billing cycle. Plans with separate Auto and API pools report a
    /// percentage for each; other plans report one total, or only cents spent against a cap.
    private static func windows(_ body: [String: Any]) -> [UsageWindow] {
        let cycleEnd = Dates.parse(body["billingCycleEnd"])
        let cycleLength: TimeInterval? = {
            guard let start = Dates.parse(body["billingCycleStart"]), let end = cycleEnd, end > start else { return nil }
            return end.timeIntervalSince(start)
        }()
        let usage = body["individualUsage"] as? [String: Any]
        let plan = usage?["plan"] as? [String: Any] ?? [:]

        func centsShare(_ lane: Any?) -> Double? {
            guard let lane = lane as? [String: Any], let cap = JSON.number(lane["limit"]), cap > 0,
                  let spent = JSON.number(lane["used"]) else { return nil }
            return spent / cap * 100
        }

        var figures: [(label: String, percent: Double)] = []
        if let auto = JSON.number(plan["autoPercentUsed"]) { figures.append(("Auto", auto)) }
        if let api = JSON.number(plan["apiPercentUsed"]) { figures.append(("API", api)) }
        if figures.isEmpty, let overall = JSON.number(plan["totalPercentUsed"]) ?? centsShare(plan) ?? centsShare(usage?["onDemand"]) {
            figures.append(("Plan", overall))
        }
        return figures.map {
            UsageWindow(label: $0.label, usedPercent: min(max($0.percent, 0), 100), resetsAt: cycleEnd, windowSeconds: cycleLength)
        }
    }

    private static func planName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Native Cursor subjects ("auth0|user_…") go in the cookie as the bare user id;
    /// WorkOS OAuth subjects ("google-oauth2|…") go in verbatim.
    private static func cookieSubject(_ subject: String) -> String {
        if let range = subject.range(of: #"\|user_[A-Za-z0-9_]+$"#, options: .regularExpression) {
            return String(subject[range].dropFirst())
        }
        return subject
    }

    // MARK: App lifecycle

    private func quitCursor() async throws -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        guard !apps.isEmpty else { return false }
        apps.forEach { $0.terminate() }
        for _ in 0..<100 {
            if apps.allSatisfy(\.isTerminated) {
                // Give its helper processes a moment to let go of the database.
                try? await Task.sleep(for: .milliseconds(500))
                return true
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        throw SwitchrError("Cursor didn't quit. Close any open dialog in Cursor and try again.")
    }

    private func openCursor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func updateCLIConfig(_ change: (inout [String: Any]) -> Void) throws {
        guard let data = try? Data(contentsOf: cliConfigURL), var config = JSON.object(data) else { return }
        change(&config)
        try Files.writeAtomically(JSON.data(config, pretty: true), to: cliConfigURL)
    }
}

/// Minimal access to VS Code's `ItemTable` key/value store.
struct ItemTable {
    let url: URL
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    func read(_ keys: [String]) throws -> [String: String] {
        let db = try open(SQLITE_OPEN_READONLY)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key, value FROM ItemTable WHERE key LIKE 'cursorAuth/%'", -1, &statement, nil) == SQLITE_OK else {
            throw SwitchrError("Couldn't read Cursor's login database")
        }
        defer { sqlite3_finalize(statement) }
        var rows: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyText = sqlite3_column_text(statement, 0) else { continue }
            let key = String(cString: keyText)
            guard keys.contains(key), let bytes = sqlite3_column_blob(statement, 1) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 1))
            rows[key] = String(decoding: UnsafeRawBufferPointer(start: bytes, count: count), as: UTF8.self)
        }
        return rows
    }

    /// Writes every row in one transaction; a nil value deletes the row.
    func write(_ rows: [String: String?]) throws {
        let db = try open(SQLITE_OPEN_READWRITE)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            throw SwitchrError("Cursor's login database is busy")
        }
        for (key, value) in rows {
            let sql = value == nil ? "DELETE FROM ItemTable WHERE key = ?1" : "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?1, ?2)"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw SwitchrError("Couldn't update Cursor's login database")
            }
            sqlite3_bind_text(statement, 1, key, -1, Self.transient)
            if let value { sqlite3_bind_text(statement, 2, value, -1, Self.transient) }
            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard result == SQLITE_DONE else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw SwitchrError("Couldn't update Cursor's login database")
            }
        }
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw SwitchrError("Couldn't save Cursor's login database")
        }
    }

    private func open(_ flags: Int32) throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw SwitchrError("Couldn't open Cursor's login database")
        }
        sqlite3_busy_timeout(db, 5000)
        return db
    }
}
