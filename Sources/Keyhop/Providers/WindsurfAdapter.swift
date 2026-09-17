import Foundation

/// Windsurf signs in through Codeium and keeps the result in `~/.codeium/config.json`, the same
/// file its editor plugins read. Keyhop swaps that file and leaves the rest of the folder alone.
///
/// UNVERIFIED. Unlike the other adapters, this one was written without a Windsurf install to test
/// against, so the shape of that file is taken from what the plugin publishes rather than from a
/// login Keyhop has read itself. It is built to fail closed: every read returns nil when the file
/// is missing or doesn't carry the fields below, so Windsurf simply doesn't appear rather than
/// appearing broken. If the format has moved, the fix is here and nothing else has to change.
struct WindsurfAdapter: ProviderAdapter {
    let provider = Provider.windsurf
    private let customDirectory: URL?
    private let customStateDatabase: URL?

    init(directory: URL? = nil, stateDatabase: URL? = nil) {
        customDirectory = directory
        customStateDatabase = stateDatabase
    }

    static var directory: URL {
        let home = ProcessInfo.processInfo.environment["CODEIUM_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Files.home
        return home.appendingPathComponent(".codeium", isDirectory: true)
    }

    static var credentialsURL: URL { directory.appendingPathComponent("config.json") }
    private var credentialsURL: URL { (customDirectory ?? Self.directory).appendingPathComponent("config.json") }

    static var stateDatabaseURL: URL {
        #if os(macOS)
        return Files.home.appendingPathComponent("Library/Application Support/Windsurf/User/globalStorage/state.vscdb")
        #elseif os(Windows)
        let base = ProcessInfo.processInfo.environment["APPDATA"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Files.home.appendingPathComponent("AppData/Roaming", isDirectory: true)
        return base.appendingPathComponent("Windsurf/User/globalStorage/state.vscdb")
        #else
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Files.home.appendingPathComponent(".config", isDirectory: true)
        return base.appendingPathComponent("Windsurf/User/globalStorage/state.vscdb")
        #endif
    }

    /// The key the login is held under. Nothing is read from the file unless this is present.
    private static let apiKey = "apiKey"

    func readLive() async throws -> LiveLogin? {
        guard let data = try? Data(contentsOf: credentialsURL) else { return nil }
        guard let root = JSON.object(data) else { return nil }
        guard let key = root[Self.apiKey] as? String, !key.isEmpty else { return nil }

        // Windsurf writes the signed-in name when it has one. Without it the key itself is the only
        // stable thing to go on, so the account is identified by a digest rather than by a guess.
        let name = (root["name"] as? String) ?? (root["userName"] as? String)
        let email = (root["email"] as? String) ?? name
        var secret = ["credentials": String(decoding: data, as: UTF8.self), Self.apiKey: key]
        if let email { secret["email"] = email }
        return LiveLogin(identity: email ?? Self.fingerprint(key), email: email ?? "Windsurf account",
                         plan: root["planName"] as? String, secret: secret,
                         // Without a name in the file, the address shown is a placeholder, not a login.
                         emailTrusted: email != nil)
    }

    func apply(_ secret: Secret) async throws {
        guard let raw = secret["credentials"], let root = JSON.object(raw),
              (root[Self.apiKey] as? String)?.isEmpty == false else {
            throw KeyhopError("Saved Windsurf login is damaged")
        }
        try FileManager.default.createDirectory(at: credentialsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Files.writeAtomically(Data(raw.utf8), to: credentialsURL)
    }

    func signOutLocally() async throws {
        let url = credentialsURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Only the key goes: the rest of config.json is settings this person chose.
        guard var root = (try? Data(contentsOf: url)).flatMap(JSON.object) else {
            return try FileManager.default.removeItem(at: url)
        }
        root.removeValue(forKey: Self.apiKey)
        try Files.writeAtomically(JSON.data(root, pretty: true), to: url)
    }

    func fetchUsage(_ secret: Secret, allowRefresh: Bool, persist: @escaping @Sendable (Secret) async -> Void) async throws -> LimitReport {
        guard secret[Self.apiKey]?.isEmpty == false else { throw KeyhopError("Saved Windsurf login is damaged") }
        // The SQLite cache belongs to the profile currently open in Windsurf. Reusing it for an
        // inactive saved profile would be worse than no data, so keep its last reading with an error.
        guard !allowRefresh else { throw KeyhopError("Switch to this Windsurf profile to refresh its limits.") }
        let url = customStateDatabase ?? Self.stateDatabaseURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KeyhopError("No Windsurf limit cache was found. Open Windsurf once while signed in.")
        }
        let source = try Database(url: url, readOnly: true)
        var raw: Data?
        try source.query("SELECT value FROM ItemTable WHERE key = 'windsurf.settings.cachedPlanInfo' LIMIT 1") { row in
            raw = row.data(0)
        }
        guard let raw, let body = Self.cachedPlanObject(raw) else {
            throw KeyhopError("Windsurf's limit cache is empty or has changed format.")
        }
        return Self.limitReport(body)
    }

    private static func cachedPlanObject(_ data: Data) -> [String: Any]? {
        if let direct = JSON.object(data) { return direct }
        guard let string = String(data: data, encoding: .utf16LittleEndian) else { return nil }
        return JSON.object(string.trimmingCharacters(in: .controlCharacters))
    }

    static func limitReport(_ body: [String: Any]) -> LimitReport {
        var windows: [UsageWindow] = []
        if let quota = body["quotaUsage"] as? [String: Any] {
            if let remaining = JSON.number(quota["dailyRemainingPercent"]) {
                windows.append(UsageWindow(label: "Day", usedPercent: min(max(100 - remaining, 0), 100),
                                           resetsAt: Dates.parse(quota["dailyResetAtUnix"]), windowSeconds: 86400))
            }
            if let remaining = JSON.number(quota["weeklyRemainingPercent"]) {
                windows.append(UsageWindow(label: "Week", usedPercent: min(max(100 - remaining, 0), 100),
                                           resetsAt: Dates.parse(quota["weeklyResetAtUnix"]), windowSeconds: 604_800))
            }
        }
        if windows.isEmpty, let usage = body["usage"] as? [String: Any] {
            func add(_ label: String, totalKey: String, usedKey: String, remainingKey: String) {
                guard let total = JSON.number(usage[totalKey]), total > 0 else { return }
                let used = JSON.number(usage[usedKey]) ?? JSON.number(usage[remainingKey]).map { max(total - $0, 0) }
                guard let used else { return }
                windows.append(UsageWindow(label: label, usedPercent: min(max(used / total * 100, 0), 100),
                                           resetsAt: Dates.parse(body["endTimestamp"]), windowSeconds: nil))
            }
            add("Messages", totalKey: "messages", usedKey: "usedMessages", remainingKey: "remainingMessages")
            add("Flow actions", totalKey: "flowActions", usedKey: "usedFlowActions", remainingKey: "remainingFlowActions")
        }
        return LimitReport(windows: windows, plan: body["planName"] as? String)
    }

    /// Whether Windsurf is on this computer. Checked by the name it installs under rather than by a
    /// bundle identifier, so nothing here rests on an identifier Keyhop hasn't seen.
    static var isAppInstalled: Bool {
        if Shell.which("windsurf") != nil { return true }
        let places = ["/Applications/Windsurf.app", Files.home.appendingPathComponent("Applications/Windsurf.app").path]
        return places.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// A short, stable name for a login that carries no address. Never the key itself.
    static func fingerprint(_ key: String) -> String {
        "windsurf-" + SHA256Digest.hex(Data(key.utf8)).prefix(12)
    }
}
