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

    /// Fetches limits for a saved login. Tokens are only refreshed when `allowRefresh` is
    /// set, which the store limits to accounts not in use, so a running tool never has
    /// its refresh token rotated out from under it. Rotated secrets go to `persist` right away.
    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport
}

enum Adapters {
    static let all: [Provider: any ProviderAdapter] = [
        .claude: ClaudeAdapter(),
        .cursor: CursorAdapter(),
        .codex: CodexAdapter(),
        .gemini: GeminiAdapter(),
        .copilot: CopilotAdapter(),
        .windsurf: WindsurfAdapter(),
    ]
}
