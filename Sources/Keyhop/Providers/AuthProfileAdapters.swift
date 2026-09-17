import Foundation

/// Pi and OpenCode can hold credentials for several model providers at once. Keyhop treats that
/// complete `auth.json` as one profile: it never edits an individual provider entry, and a switch
/// restores the exact document the tool wrote.
private struct AuthProfileFile {
    let provider: Provider
    let url: URL

    func readLive() throws -> LiveLogin? {
        guard let data = try? Data(contentsOf: url), let root = JSON.object(data), !root.isEmpty,
              root.values.allSatisfy({ $0 is [String: Any] }) else { return nil }

        let identity = Self.identity(provider: provider, root: root)
        let email = Self.email(in: root)
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
    private static func identity(provider: Provider, root: [String: Any]) -> String {
        var parts: [String] = []
        for key in root.keys.sorted() {
            guard let credential = root[key] as? [String: Any] else { continue }
            if let stable = stableValue(in: credential) {
                parts.append("\(key):\(stable)")
            } else if let token = tokenIdentity(in: credential) {
                parts.append("\(key):\(token)")
            } else if let data = try? JSONSerialization.data(withJSONObject: credential, options: [.sortedKeys]) {
                parts.append("\(key):\(SHA256Digest.hex(data))")
            }
        }
        return "\(provider.rawValue)-" + SHA256Digest.hex(Data(parts.joined(separator: "|").utf8)).prefix(16)
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

    init(directory: URL? = nil) { customDirectory = directory }

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
        AuthProfileFile(provider: provider, url: (customDirectory ?? Self.directory).appendingPathComponent("auth.json"))
    }

    func readLive() async throws -> LiveLogin? { try file.readLive() }
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

    init(directory: URL? = nil) { customDirectory = directory }

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
        AuthProfileFile(provider: provider, url: (customDirectory ?? Self.directory).appendingPathComponent("auth.json"))
    }

    func readLive() async throws -> LiveLogin? { try file.readLive() }
    func apply(_ secret: Secret) async throws { try file.apply(secret) }
    func signOutLocally() async throws { try file.signOutLocally() }
    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        guard secret["credentials"] != nil else { throw KeyhopError("Saved Pi profile is damaged") }
        return LimitReport(windows: [], plan: nil)
    }
}
