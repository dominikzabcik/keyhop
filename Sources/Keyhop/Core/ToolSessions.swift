import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A running session of Claude Code or Codex: where its login came from and when it started.
struct ToolSession: Equatable, Sendable {
    enum Place: Equatable, Sendable {
        /// The tool's usual folder, which holds the login in use.
        case usual
        /// A `keyhop run` folder of one saved login.
        case own(UUID)
        /// Can't be told (Codex, or a Claude Code too old to note its sessions).
        case unknown
    }

    var pid: Int32
    var place: Place
    var startedAt: Date?
    var directory: String?
}

/// Claude Code and Codex hand out a new refresh token on every refresh and retire the old one;
/// using a retired one can end the whole login, for every copy of it. A session keeps the token
/// it started with, so a login one may hold is refreshed by that tool alone, never by Keyhop.
enum ToolSessions {
    /// The tools whose refresh tokens are single-use.
    static let rotating: Set<Provider> = [.claude, .codex]

    /// Every running session of the tool, or nil when that can't be told (then every login counts
    /// as held: a limit read later is better than a login lost).
    static func running(_ provider: Provider) -> [ToolSession]? {
        guard rotating.contains(provider) else { return [] }
        #if os(Windows)
        return nil
        #else
        switch provider {
        case .claude:
            // Claude Code notes each session in <config>/sessions/<pid>.json, so the folder it runs
            // from (and with it the login) and when it started are known exactly.
            let usual = ClaudeAdapter.sessionsDirectory
            var found = noted(in: usual, place: .usual)
            for run in RunDirectories.all() where run.provider == .claude {
                found += noted(in: run.folder.appendingPathComponent("sessions", isDirectory: true), place: .own(run.account))
            }
            if FileManager.default.fileExists(atPath: usual.path) { return found }
            guard let listed = processes(of: .claude) else { return nil }
            return found + listed
        default:
            return processes(of: provider)
        }
        #endif
    }

    /// Whether a session may hold this login's token. A session in the usual folder holds the
    /// login that was in use when it started, so one started after the login was left can't.
    static func holds(_ session: ToolSession, _ account: Account, hasOwnFolder: Bool) -> Bool {
        let started = session.startedAt ?? .distantPast
        switch session.place {
        case .own(let id): return id == account.id
        case .usual: return started < (account.leftAt ?? .distantFuture)
        case .unknown: return hasOwnFolder || started < (account.leftAt ?? .distantFuture)
        }
    }

    /// Sessions noted in a folder whose process still runs.
    static func noted(in folder: URL, place: ToolSession.Place) -> [ToolSession] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            guard let note = (try? Data(contentsOf: folder.appendingPathComponent(name))).flatMap({ JSON.object($0) }),
                  let pid = JSON.number(note["pid"]).map({ Int32($0) }), alive(pid) else { return nil }
            let started = JSON.number(note["startedAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
            return ToolSession(pid: pid, place: place, startedAt: started, directory: note["cwd"] as? String)
        }
    }

    static func alive(_ pid: Int32) -> Bool {
        #if os(Windows)
        return true
        #else
        return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
        #endif
    }

    /// Sessions told from the process list: `ps` gives each one's age and command line.
    private static func processes(of provider: Provider) -> [ToolSession]? {
        guard let ps = Shell.which("ps") ?? (FileManager.default.isExecutableFile(atPath: "/bin/ps") ? "/bin/ps" : nil),
              let result = try? Shell.run(ps, ["-axo", "pid=,etime=,command="]), result.status == 0 else { return nil }
        let now = Date()
        return String(decoding: result.stdout, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), isSession(of: provider, commandLine: String(fields[2])) else { return nil }
            return ToolSession(pid: pid, place: .unknown, startedAt: age(String(fields[1])).map { now.addingTimeInterval(-$0) }, directory: nil)
        }
    }

    /// `ps` elapsed time, `[[dd-]hh:]mm:ss`, in seconds.
    static func age(_ elapsed: String) -> TimeInterval? {
        let dayParts = elapsed.split(separator: "-")
        let days = dayParts.count == 2 ? Double(dayParts[0]) : 0
        let clock = (dayParts.last ?? "").split(separator: ":").compactMap { Double($0) }
        guard let days, !clock.isEmpty, clock.count <= 3, clock.count == (dayParts.last ?? "").split(separator: ":").count else { return nil }
        return clock.reduce(0) { $0 * 60 + $1 } + days * 86400
    }

    /// Reads one `ps` command line: the native binary (`claude`, `codex`, `codex-<target>`, a
    /// versioned Claude build under `claude/versions/`) or node running the npm package.
    static func isSession(of provider: Provider, commandLine: String) -> Bool {
        let words = commandLine.split(separator: " ").map(String.init)
        guard let first = words.first else { return false }
        let program = (first as NSString).lastPathComponent
        switch provider {
        case .claude:
            if program == "claude" || first.contains("/claude/versions/") { return true }
            return ["node", "bun"].contains(program) && words.dropFirst().contains { $0.contains("@anthropic-ai/claude-code") }
        case .codex:
            if program == "codex" || program.hasPrefix("codex-") { return true }
            return ["node", "bun"].contains(program) && words.dropFirst().contains { $0.contains("@openai/codex") }
        default:
            return false
        }
    }
}

/// One refresh of a login at a time across every Keyhop process (the app, the command, the
/// browser host, the native window), so two of them never spend the same refresh token.
enum RefreshLock {
    static func holding<T>(_ id: UUID, in directory: URL, _ body: () async throws -> T) async throws -> T {
        #if os(Windows)
        return try await body()
        #else
        let folder = directory.appendingPathComponent("locks", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fd = open(folder.appendingPathComponent("\(id.uuidString).lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return try await body() }
        defer { close(fd) }
        // Another process refreshing this login is done within seconds; after half a minute the
        // reading waits for the next round rather than holding everything up.
        var held = false
        for _ in 0..<120 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { held = true; break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard held else { throw LimitsWaitForTool(tool: nil) }
        defer { flock(fd, LOCK_UN) }
        return try await body()
        #endif
    }
}

/// A saved login whose token is past its hour while Keyhop must not refresh it. The last reading
/// of its limits stays, and the login is not signed out.
struct LimitsWaitForTool: LocalizedError {
    let tool: String?
    var errorDescription: String? {
        tool.map { "\($0) refreshes this login the next time it uses it." } ?? "Another Keyhop is refreshing this login."
    }
}
