import Foundation

protocol ProviderAdapter: Sendable {
    var provider: Provider { get }

    /// The login the tool is using right now, or nil when signed out.
    func readLive() async throws -> LiveLogin?

    /// Makes `secret` the login the tool uses.
    func apply(_ secret: Secret) async throws

    /// Removes the local login without calling the provider's logout (which could revoke
    /// the saved token), so the tool asks you to sign in again.
    func signOutLocally() async throws

    /// Every login the tool holds right now, for the ones that keep more than one at a time.
    ///
    /// Most tools hold exactly one, so the default is simply the live login. GitHub's CLI keeps a
    /// token per account and switches between them, and Keyhop saves all of them rather than making
    /// someone sign out of one to be shown another.
    func readAllLogins() async throws -> [LiveLogin]

    /// Why this tool can't be used on this computer right now, when something outside it is
    /// missing. Nil when nothing stands in the way; a signed-out tool is not a blocker.
    func blocker() -> String?

    /// True for tools that keep several logins at once and so are never signed out to add another.
    var holdsManyLogins: Bool { get }

    /// Fetches limits for a saved login. Tokens are only refreshed when `allowRefresh` is
    /// set, which the store limits to accounts not in use (and for Claude Code and Codex to times
    /// when none of their sessions runs), so a running tool never has its refresh token rotated
    /// out from under it. Rotated secrets go to `persist` right away. Throw `LimitsWaitForTool`
    /// for a token past its hour that may not be refreshed: the last reading then stays.
    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport

    /// The Anthropic account a saved login is signed in to, for tools that can sign in to
    /// Anthropic beside Claude Code. Nil when it has none or it can't be asked.
    func anthropicAccount(of secret: Secret) async -> String?
}

extension ProviderAdapter {
    func readAllLogins() async throws -> [LiveLogin] {
        try await readLive().map { [$0] } ?? []
    }

    func blocker() -> String? { nil }

    var holdsManyLogins: Bool { false }

    func anthropicAccount(of secret: Secret) async -> String? { nil }
}

enum Adapters {
    static let all: [Provider: any ProviderAdapter] = [
        .claude: ClaudeAdapter(),
        .cursor: CursorAdapter(),
        .codex: CodexAdapter(),
        .gemini: GeminiAdapter(),
        .opencode: OpenCodeAdapter(),
        .pi: PiAdapter(),
        .copilot: CopilotAdapter(),
        .windsurf: WindsurfAdapter(),
        .codebuff: CodebuffAdapter(),
    ]
}
