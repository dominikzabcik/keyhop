import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Codebuff keeps its current CLI account in `~/.config/manicode/credentials.json`. The product
/// was formerly named Manicode, so the directory name is intentionally unchanged. Keyhop swaps
/// only the official `default` profile and preserves every unrelated key in the document.
struct CodebuffAdapter: ProviderAdapter {
    let provider = Provider.codebuff
    private let customDirectory: URL?
    private let request: (@Sendable (URLRequest) async throws -> (Data, Int))?

    init(directory: URL? = nil,
         request: (@Sendable (URLRequest) async throws -> (Data, Int))? = nil) {
        customDirectory = directory
        self.request = request
    }

    static var directory: URL {
        directory(environment: ProcessInfo.processInfo.environment)
    }

    static func directory(environment: [String: String]) -> URL {
        // This is the override used by the official CLI. It is also useful for isolated installs.
        if let value = environment["FREEBUFF_CONFIG_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return Files.home.appendingPathComponent(".config/manicode", isDirectory: true)
    }

    static var credentialsURL: URL { directory.appendingPathComponent("credentials.json") }
    private var credentialsURL: URL {
        (customDirectory ?? Self.directory).appendingPathComponent("credentials.json")
    }

    func readLive() async throws -> LiveLogin? {
        guard let root = Self.readRoot(credentialsURL), let profile = Self.profile(in: root),
              let token = profile["authToken"] as? String, !token.isEmpty else { return nil }
        let id = Self.text(profile["id"])
        let email = Self.text(profile["email"])
        let identity = id ?? email ?? Self.fingerprint(token)
        return LiveLogin(
            identity: identity,
            email: email ?? "Codebuff account",
            plan: nil,
            secret: ["profile": try JSON.string(profile)],
            emailTrusted: email != nil
        )
    }

    func apply(_ secret: Secret) async throws {
        guard let raw = secret["profile"], let profile = JSON.object(raw),
              let token = profile["authToken"] as? String, !token.isEmpty else {
            throw KeyhopError("Saved Codebuff login is damaged")
        }
        var root = Self.readRoot(credentialsURL) ?? [:]
        root["default"] = profile
        // Old Manicode builds wrote the user at the top level. Removing those known fields avoids
        // leaving a second login that an older client could prefer, without touching other config.
        for key in Self.legacyProfileKeys { root.removeValue(forKey: key) }
        try Files.writeAtomically(try JSON.data(root, pretty: true), to: credentialsURL)
    }

    func signOutLocally() async throws {
        guard var root = Self.readRoot(credentialsURL) else { return }
        root.removeValue(forKey: "default")
        for key in Self.legacyProfileKeys { root.removeValue(forKey: key) }
        try Files.writeAtomically(try JSON.data(root, pretty: true), to: credentialsURL)
    }

    func blocker() -> String? {
        guard customDirectory == nil,
              let token = ProcessInfo.processInfo.environment["CODEBUFF_API_KEY"], !token.isEmpty else { return nil }
        return "Codebuff is using CODEBUFF_API_KEY. Unset it, then run `codebuff login` so Keyhop can switch saved accounts."
    }

    func fetchUsage(_ secret: Secret, allowRefresh: Bool,
                    persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        guard let profile = secret["profile"].flatMap(JSON.object),
              let token = profile["authToken"] as? String, !token.isEmpty else {
            throw KeyhopError("Saved Codebuff login is damaged")
        }

        var usageRequest = URLRequest(url: URL(string: "https://codebuff.com/api/v1/usage")!, timeoutInterval: 20)
        usageRequest.httpMethod = "POST"
        usageRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        usageRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        usageRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        usageRequest.httpBody = try JSONSerialization.data(withJSONObject: ["fingerprintId": "keyhop-usage"])
        let (usageData, usageStatus) = try await send(usageRequest)
        if usageStatus == 401 || usageStatus == 403 {
            throw KeyhopError("Codebuff rejected this saved login. Switch to it and run `codebuff login` again.")
        }
        guard usageStatus == 200, let usage = JSON.object(usageData) else {
            throw KeyhopError("Codebuff couldn't return usage (HTTP \(usageStatus)).")
        }

        // Subscription limits add exact block and weekly denominators. Credit balance remains
        // useful if this optional endpoint is unavailable, so its failure never discards usage.
        // The token goes only in the Authorization header: presenting a CLI token as a browser
        // session cookie is not how Codebuff issued it, and Keyhop does not impersonate clients.
        var subscription: [String: Any]?
        var subscriptionRequest = URLRequest(url: URL(string: "https://codebuff.com/api/user/subscription")!, timeoutInterval: 8)
        subscriptionRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        subscriptionRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let response = try? await send(subscriptionRequest), response.1 == 200 {
            subscription = JSON.object(response.0)
        }
        return Self.limitReport(usage: usage, subscription: subscription)
    }

    private func send(_ value: URLRequest) async throws -> (Data, Int) {
        if let request { return try await request(value) }
        return try await HTTP.send(value)
    }

    static func limitReport(usage: [String: Any], subscription: [String: Any]?) -> LimitReport {
        var windows: [UsageWindow] = []
        let used = JSON.number(usage["usage"]) ?? JSON.number(usage["used"])
        let remaining = JSON.number(usage["remainingBalance"]) ?? JSON.number(usage["remaining"])
        let total = JSON.number(usage["quota"]) ?? JSON.number(usage["limit"])
            ?? (used.flatMap { value in remaining.map { value + $0 } })
        if let used, let total, total > 0 {
            windows.append(UsageWindow(label: "Credits", usedPercent: max(used / total * 100, 0),
                                       resetsAt: Dates.parse(usage["next_quota_reset"]), windowSeconds: nil))
        }

        var plan: String?
        if subscription?["hasSubscription"] as? Bool == true {
            let rate = subscription?["rateLimit"] as? [String: Any] ?? [:]
            let limits = subscription?["limits"] as? [String: Any] ?? [:]
            if let value = JSON.number(rate["blockUsed"]), let cap = JSON.number(rate["blockLimit"]), cap > 0 {
                let hours = JSON.number(limits["blockDurationHours"])
                windows.append(UsageWindow(label: "Block", usedPercent: max(value / cap * 100, 0),
                                           resetsAt: Dates.parse(rate["blockResetsAt"]),
                                           windowSeconds: hours.map { $0 * 3600 }))
            }
            if let value = JSON.number(rate["weeklyUsed"]), let cap = JSON.number(rate["weeklyLimit"]), cap > 0 {
                windows.append(UsageWindow(label: "Week", usedPercent: max(value / cap * 100, 0),
                                           resetsAt: Dates.parse(rate["weeklyResetsAt"]), windowSeconds: 604_800))
            }
            plan = Self.text(subscription?["displayName"])
            if plan == nil, let details = subscription?["subscription"] as? [String: Any],
               let tier = JSON.number(details["tier"]) {
                plan = "$\(Int(tier))/mo"
            }
        }
        return LimitReport(windows: windows, plan: plan)
    }

    static func fingerprint(_ token: String) -> String {
        "codebuff-" + SHA256Digest.hex(Data(token.utf8)).prefix(12)
    }

    private static let legacyProfileKeys = ["id", "name", "email", "authToken", "fingerprintId", "fingerprintHash", "credits"]

    private static func readRoot(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap(JSON.object)
    }

    private static func profile(in root: [String: Any]) -> [String: Any]? {
        if let profile = root["default"] as? [String: Any] { return profile }
        // Compatibility with credentials written before the official CLI adopted named profiles.
        return root["authToken"] is String ? root : nil
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }
}
