import Foundation

/// Feeds for tools Keyhop measures but doesn't switch. Paths and record shapes follow each
/// vendor's own files where they are documented, and ccusage's adapters where they aren't.
enum MeasuredFeeds {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    // MARK: Where each tool keeps its data

    static var qwenDirectory: URL { directory("QWEN_DATA_DIR", fallback: ".qwen") }

    /// Kimi Code (current, `KIMI_CODE_HOME`), plus the archived kimi-cli's `~/.kimi`.
    static var kimiDirectories: [URL] {
        [directory("KIMI_CODE_HOME", fallback: ".kimi-code"), directory("KIMI_SHARE_DIR", fallback: ".kimi")]
    }

    static var openclawDirectory: URL { directory("OPENCLAW_DIR", fallback: ".openclaw") }
    static var grokDirectory: URL { directory("GROK_HOME", fallback: ".grok") }

    /// `AMP_DATA_DIR` may be a comma-separated list of data directories.
    static var ampDirectories: [URL] {
        if let custom = env["AMP_DATA_DIR"], !custom.isEmpty {
            return custom.split(separator: ",").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces), isDirectory: true) }
        }
        return [Files.home.appendingPathComponent(".local/share/amp", isDirectory: true)]
    }

    static var gooseDatabaseURL: URL {
        if let root = env["GOOSE_PATH_ROOT"], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("data/sessions/sessions.db")
        }
        let candidates = [
            Files.home.appendingPathComponent(".local/share/goose/sessions/sessions.db"),
            Files.home.appendingPathComponent("Library/Application Support/goose/sessions/sessions.db"),
            Files.home.appendingPathComponent(".local/share/Block/goose/sessions/sessions.db"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    static var kiloDatabaseURL: URL {
        directory("KILO_DATA_DIR", fallback: ".local/share/kilo").appendingPathComponent("kilo.db")
    }

    private static func directory(_ key: String, fallback: String) -> URL {
        if let custom = env[key], !custom.isEmpty { return URL(fileURLWithPath: custom, isDirectory: true) }
        return Files.home.appendingPathComponent(fallback, isDirectory: true)
    }

    /// Whether a tool has left any data on this computer, for `keyhop doctor`.
    static func present(_ provider: Provider) -> Bool {
        let exists = { FileManager.default.fileExists(atPath: $0) }
        switch provider {
        case .qwen: return exists(qwenDirectory.path)
        case .kimi: return kimiDirectories.contains { exists($0.path) }
        case .openclaw: return exists(openclawDirectory.path)
        case .grok: return exists(grokDirectory.path)
        case .amp: return ampDirectories.contains { exists($0.path) }
        case .goose: return exists(gooseDatabaseURL.path)
        case .kilo: return exists(kiloDatabaseURL.path)
        default: return false
        }
    }

    /// Where the usage that Keyhop counts comes from, for `keyhop doctor`.
    static func usageLocation(_ provider: Provider) -> String {
        switch provider {
        case .qwen: qwenDirectory.appendingPathComponent("projects").path
        case .kimi: kimiDirectories[0].appendingPathComponent("sessions").path
        case .openclaw: openclawDirectory.path
        case .grok: grokDirectory.appendingPathComponent("sessions").path
        case .amp: ampDirectories[0].appendingPathComponent("threads").path
        case .goose: gooseDatabaseURL.path
        case .kilo: kiloDatabaseURL.path
        default: ""
        }
    }

    // MARK: Qwen Code

    /// `~/.qwen/projects/<project>/chats/*.jsonl`. Gemini-shaped `usageMetadata` on assistant
    /// records. `/branch` copies records verbatim into a new session and marks them `forkedFrom`,
    /// so those copies are skipped and the record `uuid` keys out any remaining duplicate.
    static let qwen = LogFeed(
        roots: { [qwenDirectory.appendingPathComponent("projects", isDirectory: true)] },
        markers: [Data("\"usageMetadata\"".utf8)]
    ) { object, file, _ in
        guard object["type"] as? String == "assistant",
              object["forkedFrom"] == nil,
              let usage = object["usageMetadata"] as? [String: Any],
              let timestamp = Dates.parse(object["timestamp"]) else { return [] }
        func count(_ key: String) -> Int { Int(JSON.number(usage[key]) ?? 0) }
        let cached = count("cachedContentTokenCount")
        let thoughts = count("thoughtsTokenCount")
        var tokens = TokenCounts()
        tokens.input = max(count("promptTokenCount") - cached, 0)
        tokens.cacheRead = cached
        tokens.output = count("candidatesTokenCount") + thoughts
        tokens.reasoning = thoughts
        guard tokens.total > 0 else { return [] }
        let session = object["sessionId"] as? String ?? file.deletingPathExtension().lastPathComponent
        let id = object["uuid"] as? String ?? String(timestamp.timeIntervalSince1970)
        let model = object["model"] as? String ?? "qwen"
        return [UsageRecord(key: "qwen:\(id)", provider: .qwen, account: nil, session: session,
                            kind: .request, timestamp: timestamp, model: model, tokens: tokens,
                            cost: Pricing.cost(model: model, tokens: tokens), billed: nil,
                            project: Projects.root(for: object["cwd"] as? String))]
    }

    // MARK: Kimi Code

    /// New Kimi Code writes a `usage.record` per LLM request into each agent's `wire.jsonl`.
    /// `usageScope` only says whether the request came from a turn or an operation (compaction);
    /// both are per-request deltas, so both count. The archived kimi-cli's `StatusUpdate` lines
    /// are kept readable too.
    static let kimi = LogFeed(
        roots: { kimiDirectories.map { $0.appendingPathComponent("sessions", isDirectory: true) } },
        markers: [Data("usage.record".utf8), Data("token_usage".utf8)]
    ) { object, file, state in
        let session = kimiSession(file)
        if object["type"] as? String == "usage.record" {
            guard let usage = object["usage"] as? [String: Any], let ms = JSON.number(object["time"]) else { return [] }
            func count(_ key: String) -> Int { Int(JSON.number(usage[key]) ?? 0) }
            var tokens = TokenCounts()
            tokens.input = count("inputOther")
            tokens.cacheRead = count("inputCacheRead")
            tokens.cacheWrite = count("inputCacheCreation")
            tokens.output = count("output")
            guard tokens.total > 0 else { return [] }
            let agent = object["agentId"] as? String ?? file.deletingLastPathComponent().lastPathComponent
            let model = object["model"] as? String ?? "kimi"
            return [UsageRecord(key: "kimi:\(session):\(agent):\(Int64(ms)):\(tokens.output)", provider: .kimi,
                                account: nil, session: session, kind: .request,
                                timestamp: Date(timeIntervalSince1970: ms / 1000), model: model, tokens: tokens,
                                cost: Pricing.cost(model: model, tokens: tokens), billed: nil,
                                project: kimiWorkDir(file, &state))]
        }
        guard let message = object["message"] as? [String: Any], message["type"] as? String == "StatusUpdate",
              let payload = message["payload"] as? [String: Any],
              let usage = payload["token_usage"] as? [String: Any],
              let seconds = JSON.number(object["timestamp"]) else { return [] }
        func count(_ key: String) -> Int { Int(JSON.number(usage[key]) ?? 0) }
        var tokens = TokenCounts()
        tokens.input = count("input_other")
        tokens.cacheRead = count("input_cache_read")
        tokens.cacheWrite = count("input_cache_creation")
        tokens.output = count("output")
        guard tokens.total > 0 else { return [] }
        let id = payload["message_id"] as? String ?? String(Int64(seconds))
        return [UsageRecord(key: "kimi:\(session):\(id)", provider: .kimi, account: nil, session: session,
                            kind: .request, timestamp: Date(timeIntervalSince1970: seconds), model: "kimi",
                            tokens: tokens, cost: 0, billed: nil)]
    }

    /// New layout: `sessions/<wd>/<sessionId>/agents/<agentId>/wire.jsonl`. Legacy:
    /// `sessions/<md5>/<session>/wire.jsonl`.
    private static func kimiSession(_ file: URL) -> String {
        let dir = file.deletingLastPathComponent()
        let up = dir.deletingLastPathComponent()
        if up.lastPathComponent == "agents" { return up.deletingLastPathComponent().lastPathComponent }
        return dir.lastPathComponent
    }

    /// The session's working directory sits in `state.json` next to the agents folder. Read once
    /// per file and remembered in the parser state; "-" marks a session without one.
    private static func kimiWorkDir(_ file: URL, _ state: inout [String: String]) -> String? {
        if let cached = state["cwd"] { return cached == "-" ? nil : Projects.root(for: cached) }
        let dir = file.deletingLastPathComponent().deletingLastPathComponent()
        let sessionDir = dir.lastPathComponent == "agents" ? dir.deletingLastPathComponent() : dir
        let stateFile = sessionDir.appendingPathComponent("state.json")
        let workDir = (try? Data(contentsOf: stateFile)).flatMap { JSON.object($0) }?["workDir"] as? String
        state["cwd"] = workDir ?? "-"
        return Projects.root(for: workDir)
    }

    // MARK: OpenClaw

    /// Pi-shaped message records under `~/.openclaw`: `usage{input,output,cacheRead,cacheWrite}`
    /// with the provider-reported cost, and `model_change` records naming the active model.
    static let openclaw = LogFeed(
        roots: { [openclawDirectory] },
        markers: [Data("\"usage\"".utf8), Data("model_change".utf8), Data("\"type\":\"session\"".utf8)]
    ) { object, file, state in
        let type = object["type"] as? String
        if type == "session" {
            if let session = object["id"] as? String { state["session"] = session }
            if let directory = object["cwd"] as? String { state["cwd"] = directory }
            return []
        }
        if type == "model_change" {
            if let provider = object["provider"] as? String, let model = object["modelId"] as? String {
                state["model"] = "\(provider)/\(model)"
            }
            return []
        }
        guard type == "message",
              let message = object["message"] as? [String: Any], message["role"] as? String == "assistant",
              let usage = message["usage"] as? [String: Any],
              let id = object["id"] as? String,
              let timestamp = Dates.parse(object["timestamp"]) ?? Dates.parse(message["timestamp"]) else { return [] }
        if let provider = message["provider"] as? String, let model = message["model"] as? String {
            state["model"] = "\(provider)/\(model)"
        }
        func count(_ key: String) -> Int { Int(JSON.number(usage[key]) ?? 0) }
        let tokens = TokenCounts(input: count("input"), cacheWrite: count("cacheWrite"),
                                 cacheRead: count("cacheRead"), output: count("output"))
        let logged = JSON.number((usage["cost"] as? [String: Any])?["total"]) ?? 0
        guard tokens.total > 0 || logged > 0 else { return [] }
        let model = state["model"] ?? "unknown/unknown"
        let session = state["session"] ?? file.deletingPathExtension().lastPathComponent
        return [UsageRecord(key: "openclaw:\(id):\(object["timestamp"] as? String ?? String(timestamp.timeIntervalSince1970))",
                            provider: .openclaw, account: nil, session: session, kind: .request,
                            timestamp: timestamp, model: model, tokens: tokens,
                            cost: logged > 0 ? logged : Pricing.cost(model: model, tokens: tokens), billed: nil,
                            project: Projects.root(for: state["cwd"]))]
    }

    // MARK: Grok Build

    /// `~/.grok/sessions/<cwd>/<session>/updates.jsonl`: one `turn_completed` update per turn,
    /// with usage split per model and the exact cost in USD ticks (1e10 ticks = $1). Input
    /// includes cache reads and writes, and reasoning is already inside output.
    static let grok = LogFeed(
        roots: { [grokDirectory.appendingPathComponent("sessions", isDirectory: true)] },
        markers: [Data("turn_completed".utf8)]
    ) { object, file, state in
        guard let params = object["params"] as? [String: Any],
              let update = params["update"] as? [String: Any],
              update["sessionUpdate"] as? String == "turn_completed",
              let usage = update["usage"] as? [String: Any] else { return [] }
        let meta = params["_meta"] as? [String: Any]
        guard let ms = JSON.number(meta?["agentTimestampMs"]) else { return [] }
        let session = params["sessionId"] as? String ?? file.deletingLastPathComponent().lastPathComponent
        let eventKey = meta?["eventId"] as? String ?? "\(session):\(Int64(ms))"
        let project = grokProject(file, &state)

        func record(model: String, usage: [String: Any], suffix: String) -> UsageRecord? {
            func count(_ key: String) -> Int { Int(JSON.number(usage[key]) ?? 0) }
            let cachedRead = count("cachedReadTokens")
            let cacheWrite = count("cacheCreationTokens")
            var tokens = TokenCounts()
            tokens.input = max(count("inputTokens") - cachedRead - cacheWrite, 0)
            tokens.cacheRead = cachedRead
            tokens.cacheWrite = cacheWrite
            tokens.output = count("outputTokens")
            tokens.reasoning = count("reasoningTokens")
            let ticks = JSON.number(usage["costUsdTicks"]) ?? 0
            guard tokens.total > 0 || ticks > 0 else { return nil }
            return UsageRecord(key: "grok:\(eventKey)\(suffix)", provider: .grok, account: nil, session: session,
                               kind: .request, timestamp: Date(timeIntervalSince1970: ms / 1000), model: model,
                               tokens: tokens, cost: ticks > 0 ? ticks / 1e10 : Pricing.cost(model: model, tokens: tokens),
                               billed: nil, project: project)
        }
        if let byModel = usage["modelUsage"] as? [String: Any], !byModel.isEmpty {
            return byModel.sorted { $0.key < $1.key }.compactMap { model, value in
                (value as? [String: Any]).flatMap { record(model: model, usage: $0, suffix: ":\(model)") }
            }
        }
        return record(model: "grok", usage: usage, suffix: "").map { [$0] } ?? []
    }

    /// The turn's working directory comes from `summary.json` next to `updates.jsonl`.
    private static func grokProject(_ file: URL, _ state: inout [String: String]) -> String? {
        if let cached = state["cwd"] { return cached == "-" ? nil : Projects.root(for: cached) }
        let summary = file.deletingLastPathComponent().appendingPathComponent("summary.json")
        let info = (try? Data(contentsOf: summary)).flatMap { JSON.object($0) }?["info"] as? [String: Any]
        let cwd = info?["cwd"] as? String
        state["cwd"] = cwd ?? "-"
        return Projects.root(for: cwd)
    }
}
