import Foundation

/// The Anthropic account behind an OAuth access token.
struct AnthropicAccount: Equatable, Sendable {
    let uuid: String
    let email: String?
}

typealias AnthropicLookup = @Sendable (_ accessToken: String) async throws -> AnthropicAccount

/// Asks Anthropic which account a token belongs to, the way Claude Code's own login is identified.
/// Answers are kept per token for the life of the process, so a sync every few minutes asks once
/// per token rather than every time.
enum AnthropicProfile {
    private static let cache = LookupCache()

    static let lookup: AnthropicLookup = { token in
        if let known = cache.get(token) { return known }
        let (data, status) = try await HTTP.get("https://api.anthropic.com/api/oauth/profile", headers: [
            "Authorization": "Bearer \(token)", "anthropic-beta": "oauth-2025-04-20", "Accept": "application/json",
        ])
        guard status == 200, let body = JSON.object(data), let account = body["account"] as? [String: Any],
              let uuid = account["uuid"] as? String, !uuid.isEmpty else {
            throw KeyhopError("Couldn't identify the Anthropic login (\(status)).")
        }
        let found = AnthropicAccount(uuid: uuid, email: account["email"] as? String)
        cache.set(token, found)
        return found
    }

    private final class LookupCache: @unchecked Sendable {
        private var accounts: [String: AnthropicAccount] = [:]
        private let lock = NSLock()

        func get(_ token: String) -> AnthropicAccount? {
            lock.lock()
            defer { lock.unlock() }
            return accounts[token]
        }

        func set(_ token: String, _ account: AnthropicAccount) {
            lock.lock()
            defer { lock.unlock() }
            accounts[token] = account
        }
    }
}

/// Pi and OpenCode can hold credentials for several model providers at once. Keyhop treats that
/// complete `auth.json` as one profile: it never edits an individual provider entry, and a switch
/// restores the exact document the tool wrote.
private struct AuthProfileFile {
    let provider: Provider
    let url: URL
    let lookup: AnthropicLookup

    func readLive() async throws -> LiveLogin? {
        guard let data = try? Data(contentsOf: url), let root = JSON.object(data), !root.isEmpty,
              root.values.allSatisfy({ $0 is [String: Any] }) else { return nil }

        // An Anthropic sign-in carries nothing but tokens, and both rotate as the tool refreshes
        // them. Named by its tokens, the same account would turn into a new profile every few
        // hours, so it is named by the account Anthropic reports instead. When that can't be
        // asked, the read fails rather than guess: a guess is how duplicates start.
        var accounts: [String: AnthropicAccount] = [:]
        for (key, value) in root {
            guard let credential = value as? [String: Any], Self.stableValue(in: credential) == nil,
                  let token = Self.anthropicAccessToken(key: key, credential: credential) else { continue }
            do {
                accounts[key] = try await lookup(token)
            } catch {
                throw KeyhopError("Couldn't tell which Anthropic account the \(provider.name) profile uses. \(error.localizedDescription)")
            }
        }

        let identity = Self.identity(provider: provider, root: root, accounts: accounts)
        let email = Self.email(in: root) ?? accounts.values.compactMap(\.email).sorted().first
        return LiveLogin(
            identity: identity,
            email: email ?? "\(provider.name) profile",
            plan: nil,
            secret: ["credentials": String(decoding: data, as: UTF8.self)],
            emailTrusted: email != nil
        )
    }

    func apply(_ secret: Secret) throws {
        guard let raw = secret["credentials"], let root = JSON.object(raw), !root.isEmpty,
              root.values.allSatisfy({ $0 is [String: Any] }) else {
            throw KeyhopError("Saved \(provider.name) profile is damaged")
        }
        try Files.writeAtomically(Data(raw.utf8), to: url)
    }

    func signOutLocally() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try Files.writeAtomically(try JSON.data([String: Any](), pretty: true), to: url)
    }

    /// Prefer an account id or JWT subject, which survives token renewal. API-key-only entries use
    /// a digest of the key; the actual credential is never used as a label or stored in metadata.
    static func identity(provider: Provider, root: [String: Any], accounts: [String: AnthropicAccount] = [:]) -> String {
        var parts: [String] = []
        for key in root.keys.sorted() {
            guard let credential = root[key] as? [String: Any] else { continue }
            if let stable = stableValue(in: credential) {
                parts.append("\(key):\(stable)")
            } else if let account = accounts[key] {
                parts.append("\(key):\(account.uuid)")
            } else if let token = tokenIdentity(in: credential) {
                parts.append("\(key):\(token)")
            } else if let data = try? JSONSerialization.data(withJSONObject: credential, options: [.sortedKeys]) {
                parts.append("\(key):\(SHA256Digest.hex(data))")
            }
        }
        return "\(provider.rawValue)-" + SHA256Digest.hex(Data(parts.joined(separator: "|").utf8)).prefix(16)
    }

    /// OpenCode and Pi both keep an Anthropic sign-in as `{"type": "oauth", "access", "refresh", "expires"}`.
    static func anthropicAccessToken(key: String, credential: [String: Any]) -> String? {
        guard key == "anthropic", credential["type"] as? String == "oauth",
              let token = credential["access"] as? String, !token.isEmpty else { return nil }
        return token
    }

    private static func stableValue(in credential: [String: Any]) -> String? {
        for key in ["accountId", "account_id", "userId", "user_id", "email", "login", "sub"] {
            if let value = credential[key] as? String, !value.isEmpty { return value }
        }
        for value in credential.values {
            guard let token = value as? String, let claims = JWT.claims(token) else { continue }
            for key in ["sub", "email"] {
                if let value = claims[key] as? String, !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func tokenIdentity(in credential: [String: Any]) -> String? {
        for key in ["key", "apiKey", "refresh", "token", "access"] {
            if let value = credential[key] as? String, !value.isEmpty {
                return SHA256Digest.hex(Data(value.utf8))
            }
        }
        return nil
    }

    private static func email(in root: [String: Any]) -> String? {
        for credential in root.values.compactMap({ $0 as? [String: Any] }) {
            if let email = credential["email"] as? String, email.contains("@") { return email }
            for value in credential.values {
                guard let token = value as? String,
                      let email = JWT.claims(token)?["email"] as? String,
                      email.contains("@") else { continue }
                return email
            }
        }
        return nil
    }
}

struct OpenCodeAdapter: ProviderAdapter {
    let provider = Provider.opencode
    private let customDirectory: URL?
    private let lookup: AnthropicLookup

    init(directory: URL? = nil, lookup: @escaping AnthropicLookup = AnthropicProfile.lookup) {
        customDirectory = directory
        self.lookup = lookup
    }

    static var directory: URL {
        let environment = ProcessInfo.processInfo.environment
        let data = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Files.home.appendingPathComponent(".local/share", isDirectory: true)
        return data.appendingPathComponent("opencode", isDirectory: true)
    }
    static var credentialsURL: URL { directory.appendingPathComponent("auth.json") }
    static var databaseURL: URL { databaseURL(environment: ProcessInfo.processInfo.environment, directory: directory) }
    static func databaseURL(environment: [String: String], directory: URL) -> URL {
        guard let configured = environment["OPENCODE_DB"], !configured.isEmpty else {
            return directory.appendingPathComponent("opencode.db")
        }
        // `:memory:` deliberately resolves to a nonexistent file: there is no persistent ledger
        // Keyhop can read. Relative values use the same data directory OpenCode uses.
        if configured == ":memory:" { return directory.appendingPathComponent(configured) }
        if (configured as NSString).isAbsolutePath { return URL(fileURLWithPath: configured) }
        return directory.appendingPathComponent(configured)
    }
    private var file: AuthProfileFile {
        AuthProfileFile(provider: provider, url: (customDirectory ?? Self.directory).appendingPathComponent("auth.json"), lookup: lookup)
    }

    func readLive() async throws -> LiveLogin? { try await file.readLive() }
    func apply(_ secret: Secret) async throws { try file.apply(secret) }
    func signOutLocally() async throws { try file.signOutLocally() }
    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        guard secret["credentials"] != nil else { throw KeyhopError("Saved OpenCode profile is damaged") }
        return LimitReport(windows: [], plan: nil)
    }
}

struct PiAdapter: ProviderAdapter {
    let provider = Provider.pi
    private let customDirectory: URL?
    private let lookup: AnthropicLookup

    init(directory: URL? = nil, lookup: @escaping AnthropicLookup = AnthropicProfile.lookup) {
        customDirectory = directory
        self.lookup = lookup
    }

    static var directory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["PI_CODING_AGENT_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return Files.home.appendingPathComponent(".pi/agent", isDirectory: true)
    }
    static var credentialsURL: URL { directory.appendingPathComponent("auth.json") }
    static var sessionsDirectory: URL {
        if let value = ProcessInfo.processInfo.environment["PI_CODING_AGENT_SESSION_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return directory.appendingPathComponent("sessions", isDirectory: true)
    }
    private var file: AuthProfileFile {
        AuthProfileFile(provider: provider, url: (customDirectory ?? Self.directory).appendingPathComponent("auth.json"), lookup: lookup)
    }

    func readLive() async throws -> LiveLogin? { try await file.readLive() }
    func apply(_ secret: Secret) async throws { try file.apply(secret) }
    func signOutLocally() async throws { try file.signOutLocally() }
    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        guard secret["credentials"] != nil else { throw KeyhopError("Saved Pi profile is damaged") }
        return LimitReport(windows: [], plan: nil)
    }
}
