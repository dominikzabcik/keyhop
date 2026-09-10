import Foundation

/// Codex keeps its whole login in `~/.codex/auth.json`. Limits come from the same ChatGPT
/// endpoint the Codex CLI reads, and tokens refresh through OpenAI's public Codex OAuth client.
struct CodexAdapter: ProviderAdapter {
    let provider = Provider.codex
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private var authURL: URL {
        let base = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? Files.home.appendingPathComponent(".codex")
        return base.appendingPathComponent("auth.json")
    }

    func readLive() async throws -> LiveLogin? {
        guard let data = try? Data(contentsOf: authURL) else { return nil }
        guard let root = JSON.object(data) else { throw SwitchrError("auth.json isn't valid JSON") }
        guard let tokens = root["tokens"] as? [String: Any],
              let claims = JWT.claims(tokens["id_token"] as? String) else { return nil }
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        let email = claims["email"] as? String ?? "ChatGPT account"
        let accountID = tokens["account_id"] as? String ?? auth?["chatgpt_account_id"] as? String ?? ""
        let user = claims["sub"] as? String ?? email
        return LiveLogin(
            identity: "\(user)|\(accountID)",
            email: email,
            plan: (auth?["chatgpt_plan_type"] as? String)?.capitalized,
            secret: ["auth": String(decoding: data, as: UTF8.self)]
        )
    }

    func apply(_ secret: Secret) async throws {
        guard let auth = secret["auth"], JSON.object(auth) != nil else { throw SwitchrError("Saved Codex login is damaged") }
        try Files.writeAtomically(Data(auth.utf8), to: authURL)
    }

    func signOutLocally() async throws {
        let url = authURL.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> UsageReport {
        guard var root = JSON.object(secret["auth"]),
              var tokens = root["tokens"] as? [String: Any],
              var access = tokens["access_token"] as? String else {
            throw SwitchrError("No ChatGPT login saved")
        }

        if let expiry = JWT.expiry(access), expiry < Date().addingTimeInterval(300) {
            guard allowRefresh else { throw SwitchrError("Login expired. Run codex once to refresh it.") }
            guard let refresh = tokens["refresh_token"] as? String else { throw SwitchrError("Login expired. Sign in again.") }
            let (data, status) = try await HTTP.postJSON("https://auth.openai.com/oauth/token", body: [
                "client_id": Self.clientID,
                "grant_type": "refresh_token",
                "refresh_token": refresh,
            ])
            guard status == 200, let body = JSON.object(data), let newAccess = body["access_token"] as? String else {
                throw SwitchrError(status == 401 ? "Login expired. Sign in again." : "Token refresh failed (\(status))")
            }
            tokens["access_token"] = newAccess
            if let v = body["refresh_token"] as? String { tokens["refresh_token"] = v }
            if let v = body["id_token"] as? String { tokens["id_token"] = v }
            root["tokens"] = tokens
            root["last_refresh"] = ISO8601DateFormatter().string(from: Date())
            await persist(["auth": try JSON.string(root, pretty: true)])
            access = newAccess
        }

        var headers = ["Authorization": "Bearer \(access)", "Accept": "application/json"]
        if let id = tokens["account_id"] as? String { headers["ChatGPT-Account-Id"] = id }
        let (data, status) = try await HTTP.get("https://chatgpt.com/backend-api/wham/usage", headers: headers)
        switch status {
        case 200: break
        case 401, 403: throw SwitchrError("ChatGPT rejected this login")
        default: throw SwitchrError("Codex usage returned \(status)")
        }
        guard let body = JSON.object(data) else { throw SwitchrError("Unreadable Codex usage response") }
        let rate = body["rate_limit"] as? [String: Any] ?? [:]
        let windows = [rate["primary_window"], rate["secondary_window"]]
            .compactMap(Self.window)
            .sorted { ($0.windowSeconds ?? .infinity) < ($1.windowSeconds ?? .infinity) }
        return UsageReport(windows: windows, plan: (body["plan_type"] as? String)?.capitalized)
    }

    private static func window(_ any: Any?) -> UsageWindow? {
        guard let w = any as? [String: Any], let used = JSON.number(w["used_percent"]) else { return nil }
        let seconds = JSON.number(w["limit_window_seconds"])
        var reset = Dates.parse(w["reset_at"])
        if reset == nil, let after = JSON.number(w["reset_after_seconds"]) {
            reset = Date().addingTimeInterval(after)
        }
        return UsageWindow(label: UsageWindow.label(seconds: seconds), usedPercent: used, resetsAt: reset, windowSeconds: seconds)
    }
}
