import Foundation

/// One config folder per saved login, so a tool can run under one login in one terminal while
/// another terminal runs under a different one, without a hop. Claude Code reads
/// `CLAUDE_CONFIG_DIR`, Codex reads `CODEX_HOME`; Keyhop keeps a folder per login under its data
/// directory, puts the login in it, seeds the tool's settings once, and counts the logs it writes
/// there against that login directly.
enum RunDirectories {
    static var base: URL { Platform.dataDirectory.appendingPathComponent("run", isDirectory: true) }

    /// The tools that take their config folder from the environment.
    static func supports(_ provider: Provider) -> Bool { environmentKey(provider) != nil }

    static func environmentKey(_ provider: Provider) -> String? {
        switch provider {
        case .claude: "CLAUDE_CONFIG_DIR"
        case .codex: "CODEX_HOME"
        default: nil
        }
    }

    static func folder(provider: Provider, account: UUID, base: URL = base) -> URL {
        base.appendingPathComponent(provider.rawValue, isDirectory: true).appendingPathComponent(account.uuidString, isDirectory: true)
    }

    /// Every folder Keyhop made, with the login each belongs to.
    static func all(base: URL = base) -> [(provider: Provider, account: UUID, folder: URL)] {
        var found: [(provider: Provider, account: UUID, folder: URL)] = []
        for provider in Provider.allCases where supports(provider) {
            let root = base.appendingPathComponent(provider.rawValue, isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            for name in names.sorted() {
                guard let id = UUID(uuidString: name) else { continue }
                found.append((provider, id, root.appendingPathComponent(name, isDirectory: true)))
            }
        }
        return found
    }

    /// The log trees a tool writes inside its config folder, as the feeds read them.
    static func logRoots(provider: Provider, folder: URL) -> [URL] {
        switch provider {
        case .claude: [folder.appendingPathComponent("projects", isDirectory: true)]
        case .codex: [folder.appendingPathComponent("sessions", isDirectory: true), folder.appendingPathComponent("archived_sessions", isDirectory: true)]
        default: []
        }
    }

    /// Puts the login into its folder, seeding the tool's settings from the usual folder the first
    /// time, and returns the folder. The usual folder is never touched.
    @discardableResult
    static func prepare(account: Account, secret: Secret, base: URL = base) throws -> URL {
        guard supports(account.provider) else {
            throw KeyhopError("keyhop run works for Claude Code and Codex, the tools that take their config folder from the environment.")
        }
        let folder = folder(provider: account.provider, account: account.id, base: base)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        switch account.provider {
        case .claude: try ClaudeAdapter.place(secret, in: folder)
        case .codex: try CodexAdapter.place(secret, in: folder)
        default: break
        }
        return folder
    }

    /// Copies a settings file from the usual folder the first time, so the login starts with the
    /// person's own preferences rather than a blank slate.
    static func seed(_ name: String, from source: URL, into folder: URL) {
        let target = folder.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: target.path), FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.copyItem(at: source, to: target)
    }
}

/// Which login a folder runs under: `keyhop run` inside it, or any folder below it, picks that
/// login without naming it. The longest matching folder wins.
struct RunMap: Codable, Equatable {
    /// Absolute folder path to the login's id.
    var folders: [String: String] = [:]

    static var url: URL { Platform.dataDirectory.appendingPathComponent("run-map.json") }

    static func load() -> RunMap {
        guard let data = try? Data(contentsOf: url), let map = try? DashboardJSON.decoder.decode(RunMap.self, from: data) else { return RunMap() }
        return map
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
        try Files.writeAtomically(DashboardJSON.encoder.encode(self), to: Self.url)
    }

    static func normalise(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        return url.path == "/" ? "/" : url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
    }

    mutating func set(_ folder: String, account: UUID) {
        folders[Self.normalise(folder)] = account.uuidString
    }

    @discardableResult
    mutating func remove(_ folder: String) -> Bool {
        folders.removeValue(forKey: Self.normalise(folder)) != nil
    }

    /// The login for a directory: the mapped folder it is, or is inside, longest first.
    func account(for directory: String) -> UUID? {
        let path = Self.normalise(directory)
        let hit = folders.keys
            .filter { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
            .max { $0.count < $1.count }
        return hit.flatMap { folders[$0] }.flatMap(UUID.init(uuidString:))
    }
}
