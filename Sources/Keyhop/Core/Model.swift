import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude, cursor, codex, gemini, opencode, pi, copilot, windsurf, codebuff

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .copilot: "GitHub Copilot"
        case .windsurf: "Windsurf"
        case .codebuff: "Codebuff"
        }
    }

    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .copilot: "Copilot"
        case .windsurf: "Windsurf"
        case .codebuff: "Codebuff"
        }
    }

    /// Shown while Keyhop waits for you to sign in with another account.
    var signInHint: String {
        switch self {
        case .claude: "Run `claude`, then `/login` with the other account. Keyhop saves it automatically."
        case .cursor: "Sign in to Cursor with the other account. Keyhop saves it automatically."
        case .codex: "Run `codex login` with the other account. Keyhop saves it automatically."
        case .gemini: "Run `gemini`, then sign in with Google using the other account. Keyhop saves it automatically."
        case .opencode: "Run `opencode auth login` and sign in to the providers for the other profile. Keyhop saves it automatically."
        case .pi: "Run `pi`, then `/login` and sign in to the providers for the other profile. Keyhop saves it automatically."
        case .copilot: "Run `gh auth login` and sign in as the other account. Keyhop saves it automatically."
        case .windsurf: "Sign in to Windsurf with the other account. Keyhop saves it automatically."
        case .codebuff: "Run `codebuff login` with the other account. Keyhop saves it automatically."
        }
    }

    var switchNote: String? {
        switch self {
        #if os(macOS)
        case .claude: "Claude Code rereads its login every 30 seconds, so open sessions move to this account shortly. If one doesn't, restart it with `claude --continue`."
        #else
        case .claude: "New Claude Code sessions use this account. If an open session stays on the old one, restart it with `claude --continue`."
        #endif
        case .codex: "New Codex sessions use this account. Running ones stay on the old login, so reopen them with `codex resume --last`."
        case .gemini: "New Gemini CLI sessions use this account. Restart a running session to move it to the new login."
        case .opencode: "New OpenCode sessions use this profile. Restart a running session to move it to the new logins."
        case .pi: "New Pi sessions use this profile. Restart a running session to move it to the new logins."
        case .copilot: "New Copilot sessions use this account. Restart a running one, and reload your editor, to move it over."
        case .windsurf: "Restart Windsurf to move open windows to this account."
        case .codebuff: "New Codebuff sessions use this account. Restart a running session to move it to the new login."
        case .cursor: nil
        }
    }

    /// A current, human-readable list for anything that has to name every tool.
    static var wordList: String {
        let names = allCases.map(\.rawValue)
        return names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1]
    }

    var limitsNote: String? {
        switch self {
        case .gemini: "Quota stays in Gemini CLI; Keyhop tracks local usage."
        case .opencode: "Provider quotas stay in OpenCode; Keyhop tracks its local token and cost ledger."
        case .pi: "Provider quotas stay in Pi; Keyhop tracks its local token and cost ledger."
        // Neither writes a local transcript with complete token counts. Their first-party quota
        // readings are still useful and are kept separate from local token history.
        case .copilot: "Token history stays with GitHub; Keyhop reads available plan quotas."
        case .windsurf: "Windsurf exposes limits only for the profile in use; Keyhop reads its local cache."
        case .codebuff: "Codebuff exposes credit and subscription limits; its local history does not include model token counts."
        case .claude, .cursor, .codex: nil
        }
    }
}

struct Account: Codable, Identifiable, Equatable {
    var id: UUID
    var provider: Provider
    /// Stable key derived from the login itself (user id, org, workspace).
    var identity: String
    var email: String
    var label: String?
    var plan: String?
    var addedAt: Date

    var displayName: String {
        if let label, !label.isEmpty { return label }
        return email
    }
}

/// Raw credential material for one login, stored in the Keychain.
typealias Secret = [String: String]

struct LiveLogin {
    var identity: String
    var email: String
    var plan: String?
    var secret: Secret
    /// False when the email is cached apart from the token and may belong to a previous login.
    var emailTrusted = true
}

struct UsageWindow: Codable, Equatable, Identifiable {
    var label: String
    var usedPercent: Double
    var resetsAt: Date?
    var windowSeconds: TimeInterval?

    var id: String { label }

    /// Where usage would sit if it were spread evenly across the window.
    func pace(at now: Date) -> Double? {
        guard let resetsAt, let windowSeconds, windowSeconds > 0 else { return nil }
        let elapsed = 1 - resetsAt.timeIntervalSince(now) / windowSeconds
        guard elapsed.isFinite else { return nil }
        return min(max(elapsed, 0), 1)
    }

    func resetText(at now: Date) -> String {
        guard let resetsAt else { return "" }
        let s = Int(resetsAt.timeIntervalSince(now))
        if s <= 0 { return "now" }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }

    static func label(seconds: TimeInterval?) -> String {
        switch seconds {
        case 18000: "5h"
        case 604_800: "Week"
        case let s? where s >= 2_400_000: "Month"
        case let s? where s >= 3600: "\(Int(s / 3600))h"
        default: "Limit"
        }
    }
}

struct LimitReport {
    var windows: [UsageWindow]
    var plan: String?
}

struct UsageSnapshot: Codable, Equatable {
    var windows: [UsageWindow] = []
    var error: String?
    var fetchedAt: Date?
}

struct KeyhopError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
