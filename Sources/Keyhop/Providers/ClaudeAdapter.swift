import Foundation

/// Claude Code keeps its OAuth login in the Keychain item "Claude Code-credentials" on macOS, and
/// in `~/.claude/.credentials.json` (0600) on Linux. MCP server tokens stored next to it are left
/// untouched. The account summary lives in `~/.claude.json`.
struct ClaudeAdapter: ProviderAdapter {
    let provider = Provider.claude
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let profiles = ProfileCache()

    func readLive() async throws -> LiveLogin? {
        guard let root = Self.readCredentials(),
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }

        let configAccount = Self.readConfig()?["oauthAccount"] as? [String: Any]
        let profile = try await identify(token: token, oauth: oauth, configAccount: configAccount)

        // Keep Claude Code's own account summary when it describes this login; otherwise
        // store a minimal one so switching back writes the right name into ~/.claude.json.
        var account = configAccount ?? [:]
        if account["accountUuid"] as? String != profile.accountUUID {
            account = ["accountUuid": profile.accountUUID, "emailAddress": profile.email]
            if let org = profile.orgUUID { account["organizationUuid"] = org }
        }
        return LiveLogin(
            identity: profile.identity,
            email: profile.email,
            plan: profile.plan,
            secret: ["oauth": try JSON.string(oauth), "account": try JSON.string(account)]
        )
    }

    func apply(_ secret: Secret) async throws {
        guard let oauth = JSON.object(secret["oauth"]), oauth["accessToken"] is String else {
            throw KeyhopError("Saved Claude login is damaged")
        }
        var root = Self.readCredentials() ?? [:]
        root["claudeAiOauth"] = oauth
        try Self.writeCredentials(root)
        if let account = JSON.object(secret["account"]) {
            try Self.updateConfig { $0["oauthAccount"] = account }
        }
    }

    func signOutLocally() async throws {
        if var root = Self.readCredentials() {
            root.removeValue(forKey: "claudeAiOauth")
            try Self.writeCredentials(root)
        }
        try Self.updateConfig { $0.removeValue(forKey: "oauthAccount") }
    }

    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        guard var oauth = JSON.object(secret["oauth"]), var token = oauth["accessToken"] as? String else {
            throw KeyhopError("Saved Claude login is damaged")
        }

        let expiresAt = JSON.number(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        if let expiresAt, expiresAt < Date().addingTimeInterval(120) {
            guard allowRefresh else { throw KeyhopError("Login expired. Run claude once to refresh it.") }
            guard let refresh = oauth["refreshToken"] as? String else { throw KeyhopError("Login expired. Sign in again.") }
            let (data, status) = try await HTTP.postJSON("https://platform.claude.com/v1/oauth/token", body: [
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": Self.clientID,
            ])
            guard status == 200, let body = JSON.object(data), let access = body["access_token"] as? String else {
                throw KeyhopError(status == 400 || status == 401
                    ? "Login expired. Switch to it and run claude to sign in again."
                    : "Token refresh failed (\(status))")
            }
            oauth["accessToken"] = access
            if let v = body["refresh_token"] as? String { oauth["refreshToken"] = v }
            if let seconds = JSON.number(body["expires_in"]) {
                oauth["expiresAt"] = Int64((Date().timeIntervalSince1970 + seconds) * 1000)
            }
            var updated = secret
            updated["oauth"] = try JSON.string(oauth)
            await persist(updated)
            token = access
        }

        let (data, status) = try await HTTP.get("https://api.anthropic.com/api/oauth/usage", headers: Self.headers(token))
        switch status {
        case 200: break
        case 401: throw KeyhopError("Claude rejected this login. Sign in again.")
        case 429: throw KeyhopError("Claude is rate limiting usage checks. Try again in a few minutes.")
        default: throw KeyhopError("Claude usage returned \(status)")
        }
        guard let body = JSON.object(data) else { throw KeyhopError("Unreadable Claude usage response") }

        let slots: [(key: String, label: String, seconds: TimeInterval)] = [
            ("five_hour", "5h", 18000),
            ("seven_day", "Week", 604_800),
            ("seven_day_opus", "Opus", 604_800),
            ("seven_day_sonnet", "Sonnet", 604_800),
        ]
        let windows = slots.compactMap { slot -> UsageWindow? in
            guard let w = body[slot.key] as? [String: Any], let used = JSON.number(w["utilization"]) else { return nil }
            return UsageWindow(label: slot.label, usedPercent: used, resetsAt: Dates.parse(w["resets_at"]), windowSeconds: slot.seconds)
        }
        return LimitReport(windows: windows, plan: nil)
    }

    // MARK: Identity

    struct Profile {
        var accountUUID: String
        var orgUUID: String?
        var email: String
        var plan: String?
        var identity: String { "\(accountUUID)|\(orgUUID ?? "")" }
    }

    /// Asks Anthropic who the token belongs to, because ~/.claude.json can lag behind the stored
    /// login. Falls back to that file only when the token itself is expired.
    private func identify(token: String, oauth: [String: Any], configAccount: [String: Any]?) async throws -> Profile {
        if let cached = Self.profiles.get(token) { return cached }
        let tokenPlan = Self.planName(type: oauth["subscriptionType"] as? String, tier: oauth["rateLimitTier"] as? String)
        let (data, status) = try await HTTP.get("https://api.anthropic.com/api/oauth/profile", headers: Self.headers(token))

        if status == 200, let body = JSON.object(data),
           let account = body["account"] as? [String: Any], let uuid = account["uuid"] as? String {
            let org = body["organization"] as? [String: Any]
            let profile = Profile(
                accountUUID: uuid,
                orgUUID: org?["uuid"] as? String,
                email: account["email"] as? String ?? "Claude account",
                plan: Self.planName(type: org?["organization_type"] as? String, tier: org?["rate_limit_tier"] as? String) ?? tokenPlan
            )
            Self.profiles.set(token, profile)
            return profile
        }
        if status == 401 || status == 403, let configAccount, let uuid = configAccount["accountUuid"] as? String {
            return Profile(
                accountUUID: uuid,
                orgUUID: configAccount["organizationUuid"] as? String,
                email: configAccount["emailAddress"] as? String ?? "Claude account",
                plan: tokenPlan
            )
        }
        throw KeyhopError("Couldn't identify the Claude login (\(status)).")
    }

    static func planName(type: String?, tier: String?) -> String? {
        guard let type, !type.isEmpty else { return nil }
        let base = type.replacingOccurrences(of: "claude_", with: "").replacingOccurrences(of: "_", with: " ").capitalized
        if let tier, tier.contains("20x") { return "\(base) 20x" }
        if let tier, tier.contains("5x") { return "\(base) 5x" }
        return base
    }

    private static func headers(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)", "anthropic-beta": "oauth-2025-04-20", "Accept": "application/json"]
    }

    // MARK: Where the login lives

    /// Claude Code's config folder: `$CLAUDE_CONFIG_DIR`, or `~/.claude`.
    private static var configDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return Files.home.appendingPathComponent(".claude", isDirectory: true)
    }

    #if os(macOS)
    private static let service = "Claude Code-credentials"

    /// Same account name Claude Code uses: $USER, or a fixed fallback when it has unusual characters.
    private static var keychainAccount: String {
        let user = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        return user.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil ? user : "claude-code-user"
    }

    private static func readCredentials() -> [String: Any]? {
        (Keychain.read(service: service, account: keychainAccount) ?? Keychain.read(service: service, account: nil))
            .flatMap { JSON.object($0) }
    }

    private static func writeCredentials(_ root: [String: Any]) throws {
        try Keychain.write(service: service, account: keychainAccount, data: JSON.data(root))
    }

    private static var configURL: URL { Files.home.appendingPathComponent(".claude.json") }
    #else
    static var credentialsFile: URL { configDirectory.appendingPathComponent(".credentials.json") }

    private static func readCredentials() -> [String: Any]? {
        (try? Data(contentsOf: credentialsFile)).flatMap { JSON.object($0) }
    }

    private static func writeCredentials(_ root: [String: Any]) throws {
        try Files.writeAtomically(JSON.data(root), to: credentialsFile)
    }

    /// With a custom config folder, Claude Code keeps `.claude.json` inside it.
    private static var configURL: URL {
        ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { _ in configDirectory.appendingPathComponent(".claude.json") }
            ?? Files.home.appendingPathComponent(".claude.json")
    }
    #endif

    private static func readConfig() -> [String: Any]? {
        (try? Data(contentsOf: configURL)).flatMap { JSON.object($0) }
    }

    private static func updateConfig(_ change: (inout [String: Any]) -> Void) throws {
        guard var config = readConfig() else { return }
        change(&config)
        try Files.writeAtomically(JSON.data(config, pretty: true), to: configURL)
    }
}

private final class ProfileCache: @unchecked Sendable {
    private var profiles: [String: ClaudeAdapter.Profile] = [:]
    private let lock = NSLock()

    func get(_ token: String) -> ClaudeAdapter.Profile? {
        lock.lock()
        defer { lock.unlock() }
        return profiles[token]
    }

    func set(_ token: String, _ profile: ClaudeAdapter.Profile) {
        lock.lock()
        defer { lock.unlock() }
        profiles[token] = profile
    }
}
