import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude, cursor, codex

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .cursor: "Cursor"
        case .codex: "Codex"
        }
    }

    /// Shown while Switchr waits for you to sign in with another account.
    var signInHint: String {
        switch self {
        case .claude: "Run `claude`, then `/login` with the other account. Switchr saves it automatically."
        case .cursor: "Sign in to Cursor with the other account. Switchr saves it automatically."
        case .codex: "Run `codex login` with the other account. Switchr saves it automatically."
        }
    }

    var switchNote: String? {
        switch self {
        case .claude: "Claude Code rereads its login every 30 seconds, so open sessions move to this account shortly. If one doesn't, restart it with `claude --continue`."
        case .codex: "New Codex sessions use this account. Running ones stay on the old login, so reopen them with `codex resume --last`."
        case .cursor: nil
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

struct UsageWindow: Equatable, Identifiable {
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

struct UsageReport {
    var windows: [UsageWindow]
    var plan: String?
}

struct UsageSnapshot: Equatable {
    var windows: [UsageWindow] = []
    var error: String?
    var fetchedAt: Date?
}

struct SwitchrError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
