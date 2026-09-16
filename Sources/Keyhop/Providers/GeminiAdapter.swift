import Foundation

/// Gemini CLI stores its Google OAuth login in `~/.gemini/oauth_creds.json` and its account
/// picker history in `~/.gemini/google_accounts.json`. Keyhop swaps the OAuth file and keeps the
/// picker pointed at the matching account; it never revokes Google's token.
struct GeminiAdapter: ProviderAdapter {
    let provider = Provider.gemini
    private let customDirectory: URL?

    init(directory: URL? = nil) {
        customDirectory = directory
    }

    static var directory: URL {
        let home = ProcessInfo.processInfo.environment["GEMINI_CLI_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Files.home
        return home.appendingPathComponent(".gemini", isDirectory: true)
    }
    static var credentialsURL: URL { directory.appendingPathComponent("oauth_creds.json") }
    static var accountsURL: URL { directory.appendingPathComponent("google_accounts.json") }
    private var credentialsURL: URL { (customDirectory ?? Self.directory).appendingPathComponent("oauth_creds.json") }
    private var accountsURL: URL { (customDirectory ?? Self.directory).appendingPathComponent("google_accounts.json") }

    func readLive() async throws -> LiveLogin? {
        guard let data = try? Data(contentsOf: credentialsURL) else { return nil }
        guard let credentials = JSON.object(data) else { throw KeyhopError("oauth_creds.json isn't valid JSON") }
        let access = credentials["access_token"] as? String
        let refresh = credentials["refresh_token"] as? String
        guard access?.isEmpty == false || refresh?.isEmpty == false else { return nil }

        let claims = JWT.claims(credentials["id_token"] as? String)
        let email = claims?["email"] as? String ?? activeAccount()
        let identity = claims?["sub"] as? String
        guard let stableIdentity = identity ?? email else { throw KeyhopError("Couldn't identify the Gemini login") }
        var secret = ["credentials": String(decoding: data, as: UTF8.self)]
        if let email { secret["email"] = email }
        return LiveLogin(
            identity: stableIdentity,
            email: email ?? "Google account",
            plan: nil,
            secret: secret
        )
    }

    func apply(_ secret: Secret) async throws {
        guard let raw = secret["credentials"], let credentials = JSON.object(raw),
              credentials["access_token"] is String || credentials["refresh_token"] is String else {
            throw KeyhopError("Saved Gemini login is damaged")
        }
        try Files.writeAtomically(Data(raw.utf8), to: credentialsURL)
        let claims = JWT.claims(credentials["id_token"] as? String)
        selectAccount(secret["email"] ?? claims?["email"] as? String)
    }

    func signOutLocally() async throws {
        let url = credentialsURL.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        clearActiveAccount()
    }

    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        guard JSON.object(secret["credentials"]) != nil else { throw KeyhopError("Saved Gemini login is damaged") }
        return LimitReport(windows: [], plan: nil)
    }

    private func activeAccount() -> String? {
        guard let data = try? Data(contentsOf: accountsURL), let root = JSON.object(data) else { return nil }
        return root["active"] as? String
    }

    private func selectAccount(_ email: String?) {
        guard let email, !email.isEmpty else { return }
        var root = (try? Data(contentsOf: accountsURL)).flatMap(JSON.object) ?? [:]
        var old = root["old"] as? [String] ?? []
        if let active = root["active"] as? String, active != email, !old.contains(active) { old.insert(active, at: 0) }
        old.removeAll { $0 == email }
        root["active"] = email
        root["old"] = old
        try? Files.writeAtomically(JSON.data(root, pretty: true), to: accountsURL)
    }

    private func clearActiveAccount() {
        guard let data = try? Data(contentsOf: accountsURL), var root = JSON.object(data) else { return }
        var old = root["old"] as? [String] ?? []
        if let active = root["active"] as? String, !old.contains(active) { old.insert(active, at: 0) }
        root["active"] = NSNull()
        root["old"] = old
        try? Files.writeAtomically(JSON.data(root, pretty: true), to: accountsURL)
    }
}
