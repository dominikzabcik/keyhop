import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Claude Code and Codex hand out a new refresh token on every refresh and retire the old one;
/// using a retired one can end the whole login, for every copy of it. A session keeps the token
/// it started with, so while one runs, its tool alone may refresh any login it could be holding.
enum ToolSessions {
    /// The tools whose refresh tokens are single-use.
    static let rotating: Set<Provider> = [.claude, .codex]

    /// Whether a session of the tool runs on this computer. When that can't be told, it counts
    /// as running: a limit read later is better than a login lost.
    static func running(_ provider: Provider) -> Bool {
        guard rotating.contains(provider) else { return false }
        #if os(Windows)
        return true
        #else
        guard let ps = Shell.which("ps") ?? (FileManager.default.isExecutableFile(atPath: "/bin/ps") ? "/bin/ps" : nil),
              let result = try? Shell.run(ps, ["-axo", "command="]), result.status == 0 else { return true }
        let lines = String(decoding: result.stdout, as: UTF8.self).split(separator: "\n")
        return lines.contains { isSession(of: provider, commandLine: String($0)) }
        #endif
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
        // reading goes ahead without a refresh rather than waiting forever.
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
