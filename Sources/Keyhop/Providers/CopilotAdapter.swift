import Foundation

/// GitHub Copilot signs in as a GitHub account, and the GitHub CLI is where that login already
/// lives: `gh` keeps one token per account in the system secret store and names the active one in
/// `hosts.yml`. Copilot CLI and the editor extensions read that same login, so Keyhop switches
/// Copilot by switching the GitHub account rather than by inventing a second store for it.
///
/// Every change goes through `gh`'s own supported commands (`gh auth token`, `gh auth switch`,
/// `gh auth login --with-token`). Keyhop never rewrites `hosts.yml` itself, so a format change on
/// GitHub's side cannot corrupt a person's logins, and it never calls `gh auth logout`, which would
/// revoke the token Keyhop just saved.
struct CopilotAdapter: ProviderAdapter {
    let provider = Provider.copilot
    /// Overridden in tests so nothing touches a real `gh`.
    private let gh: (@Sendable ([String], Data?) throws -> ShellResult)?

    init(gh: (@Sendable ([String], Data?) throws -> ShellResult)? = nil) {
        self.gh = gh
    }

    static let host = "github.com"

    static var configDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["GH_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Files.home.appendingPathComponent(".config/gh", isDirectory: true)
    }

    static var hostsURL: URL { configDirectory.appendingPathComponent("hosts.yml") }

    /// Where Copilot CLI keeps its settings. Its login is GitHub's, so this only says it has run.
    static var cliDirectory: URL { Files.home.appendingPathComponent(".copilot", isDirectory: true) }

    private func run(_ arguments: [String], stdin: Data? = nil) throws -> ShellResult {
        if let gh { return try gh(arguments, stdin) }
        guard let path = Shell.which("gh") else {
            throw KeyhopError("Keyhop switches Copilot through the GitHub CLI. Install gh, then run gh auth login.")
        }
        return try Shell.run(path, arguments, stdin: stdin)
    }

    private func text(_ result: ShellResult) -> String {
        String(decoding: result.stdout, as: UTF8.self)
    }

    // MARK: Reading

    func readLive() async throws -> LiveLogin? {
        guard let login = try activeLogin() else { return nil }
        guard let token = try savedToken(for: login), !token.isEmpty else { return nil }
        return LiveLogin(identity: login, email: "@\(login)", plan: nil,
                         secret: ["token": token, "login": login])
    }

    /// The account `gh` is currently signed in as, from its own status rather than its config file.
    private func activeLogin() throws -> String? {
        guard Shell.which("gh") != nil || gh != nil else { return nil }
        let result = try run(["auth", "status", "--hostname", Self.host])
        guard result.status == 0 else { return nil }
        // `gh auth status` marks the account in use with "Active account: true" under its login.
        return Self.activeLogin(in: text(result))
    }

    /// Every account `gh auth status` lists, and which one is in use. Kept apart to be testable.
    static func logins(in status: String) -> [(login: String, active: Bool)] {
        var found: [(login: String, active: Bool)] = []
        for line in status.split(separator: "\n", omittingEmptySubsequences: false) {
            // gh bullets each line with a tick or a dash, so those go before anything is read.
            let text = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t-•✓✗*"))
            if let range = text.range(of: "Logged in to \(host) account "),
               let login = text[range.upperBound...].split(separator: " ").first.map(String.init),
               isGitHubLogin(login) {
                found.append((login, false))
            } else if text.hasPrefix("Active account: true"), !found.isEmpty {
                found[found.count - 1].active = true
            }
        }
        return found
    }

    static func activeLogin(in status: String) -> String? {
        logins(in: status).first { $0.active }?.login
    }

    /// GitHub's own rule for a username. Checked before a name is ever handed to `gh`, so nothing
    /// that could read as an option (a leading dash, say) reaches the command line.
    static func isGitHubLogin(_ value: String) -> Bool {
        guard (1...39).contains(value.count), !value.hasPrefix("-"), !value.hasSuffix("-") else { return false }
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private func savedToken(for login: String) throws -> String? {
        let result = try run(["auth", "token", "--hostname", Self.host, "--user", login])
        guard result.status == 0 else { return nil }
        let token = text(result).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: Switching

    func apply(_ secret: Secret) async throws {
        guard let login = secret["login"], Self.isGitHubLogin(login), let token = secret["token"], !token.isEmpty else {
            throw KeyhopError("Saved Copilot login is damaged")
        }
        // Already held by gh: switching is enough, and re-adding the token would rotate nothing.
        if try savedToken(for: login) == token {
            let switched = try run(["auth", "switch", "--hostname", Self.host, "--user", login])
            guard switched.status == 0 else { throw KeyhopError(Self.problem(switched, login: login)) }
            return
        }
        // gh takes the token on stdin, so it never appears in a process list.
        let added = try run(["auth", "login", "--hostname", Self.host, "--with-token"], stdin: Data(token.utf8))
        guard added.status == 0 else { throw KeyhopError(Self.problem(added, login: login)) }
        let switched = try run(["auth", "switch", "--hostname", Self.host, "--user", login])
        guard switched.status == 0 else { throw KeyhopError(Self.problem(switched, login: login)) }
    }

    var holdsManyLogins: Bool { true }

    /// Copilot can be on this computer without gh, and then Keyhop has nothing to switch it with.
    /// Said plainly, rather than leaving Copilot to look signed out for no visible reason.
    func blocker() -> String? {
        guard gh == nil, Shell.which("gh") == nil else { return nil }
        return "Keyhop switches Copilot through the GitHub CLI, which isn't installed. Install gh, then run `gh auth login`."
    }

    /// Nothing to do, and that is the point.
    ///
    /// Signing a tool out here exists so someone can sign in as a second account. gh already holds
    /// as many accounts as you like at once, so Keyhop finds them all in `readAllLogins()` and
    /// never has to take one away first. `gh auth logout` is also the wrong tool: it asks GitHub to
    /// revoke the token, which would break the copy Keyhop saved.
    func signOutLocally() async throws {}

    /// Every GitHub account gh holds, so all of them can be saved without signing out of any.
    func readAllLogins() async throws -> [LiveLogin] {
        guard Shell.which("gh") != nil || gh != nil else { return [] }
        let status = try run(["auth", "status", "--hostname", Self.host])
        guard status.status == 0 else { return [] }
        return try Self.logins(in: text(status)).compactMap { entry in
            guard let token = try savedToken(for: entry.login), !token.isEmpty else { return nil }
            return LiveLogin(identity: entry.login, email: "@\(entry.login)", plan: nil,
                             secret: ["token": token, "login": entry.login])
        }
    }

    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        guard secret["token"]?.isEmpty == false else { throw KeyhopError("Saved Copilot login is damaged") }
        // GitHub publishes no per-account Copilot allowance Keyhop can read, so it reports none
        // rather than guessing. Local usage is still counted from this computer's own logs.
        return LimitReport(windows: [], plan: nil)
    }

    private static func problem(_ result: ShellResult, login: String) -> String {
        let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "The GitHub CLI couldn't switch to \(login)." : message
    }
}
