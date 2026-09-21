import Foundation

/// A tree of append-only JSONL logs and how to turn their lines into usage records.
struct LogFeed {
    let roots: [URL]
    /// A line must contain one of these byte strings before it's worth decoding.
    let markers: [Data]
    /// `state` persists per file between reads, for parsers that need earlier lines.
    let parse: (_ object: [String: Any], _ file: URL, _ state: inout [String: String]) -> UsageRecord?

    static let all = [claudeCode, codex, geminiCLI, pi]

    // MARK: Claude Code

    /// `~/.claude/projects/**/*.jsonl`. Each assistant response is logged once per content
    /// block with identical usage, so the message and request ids make the key.
    static let claudeCode = LogFeed(
        roots: [Files.home.appendingPathComponent(".claude/projects")],
        markers: [Data("\"usage\"".utf8)]
    ) { object, _, _ in
        guard object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, !model.hasPrefix("<"),
              let timestamp = Dates.parse(object["timestamp"]) else { return nil }

        func count(_ key: String, in dictionary: [String: Any]? = nil) -> Int {
            Int(JSON.number((dictionary ?? usage)[key]) ?? 0)
        }
        let breakdown = usage["cache_creation"] as? [String: Any]
        let oneHour = breakdown.map { count("ephemeral_1h_input_tokens", in: $0) } ?? 0

        var tokens = TokenCounts()
        tokens.input = count("input_tokens")
        tokens.cacheWrite1h = oneHour
        tokens.cacheWrite = max(count("cache_creation_input_tokens") - oneHour, 0)
        tokens.cacheRead = count("cache_read_input_tokens")
        tokens.output = count("output_tokens")

        // Keys must be stable, so a re-read file can never count a response twice.
        let id = message["id"] as? String ?? object["uuid"] as? String ?? String(timestamp.timeIntervalSince1970)
        return UsageRecord(
            key: "claude:\(id):\(object["requestId"] as? String ?? "")",
            provider: .claude, account: nil, session: object["sessionId"] as? String,
            kind: .request, timestamp: timestamp, model: model, tokens: tokens,
            cost: Pricing.cost(model: model, tokens: tokens, fast: usage["speed"] as? String == "fast"),
            billed: nil, project: Projects.root(for: object["cwd"] as? String)
        )
    }

    // MARK: Codex

    /// `~/.codex/sessions/**/rollout-*.jsonl`. Current Codex writes a `token_usage_record` per
    /// response. Older sessions only emit `token_count` events carrying running totals, which are
    /// stored as the difference from the previous total.
    static let codex = LogFeed(
        roots: [Files.home.appendingPathComponent(".codex/sessions"), Files.home.appendingPathComponent(".codex/archived_sessions")],
        markers: ["token_usage_record", "token_count", "turn_context"].map { Data($0.utf8) }
    ) { object, file, state in
        let payload = object["payload"] as? [String: Any] ?? [:]
        let session = codexSession(file)

        switch object["type"] as? String {
        case "turn_context":
            if let model = payload["model"] as? String { state["model"] = model }
            if let directory = payload["cwd"] as? String { state["cwd"] = directory }
            return nil

        case "token_usage_record":
            guard let usage = payload["usage"] as? [String: Any], let timestamp = Dates.parse(object["timestamp"]) else { return nil }
            let model = state["model"] ?? "gpt-5"
            let tokens = codexTokens(usage)
            let id = payload["response_id"] as? String ?? "\(session):\(object["ordinal"] ?? timestamp.timeIntervalSince1970)"
            return UsageRecord(key: "codex:\(id)", provider: .codex, account: nil, session: payload["session_id"] as? String ?? session,
                               kind: .request, timestamp: timestamp, model: model, tokens: tokens,
                               cost: Pricing.cost(model: model, tokens: tokens), billed: nil,
                               project: Projects.root(for: state["cwd"]))

        case "event_msg" where payload["type"] as? String == "token_count":
            guard let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any],
                  let timestamp = Dates.parse(object["timestamp"]) else { return nil }
            let runningTotal = Int(JSON.number(total["total_tokens"]) ?? 0)
            let previous = JSON.object(state["total"])
            let previousTotal = previous.flatMap { JSON.number($0["total_tokens"]) }.map(Int.init) ?? -1
            guard runningTotal != previousTotal else { return nil }
            state["total"] = try? JSON.string(total)

            let usage: [String: Any]
            if let previous, runningTotal > previousTotal {
                usage = total.reduce(into: [:]) { result, entry in
                    result[entry.key] = (JSON.number(entry.value) ?? 0) - (JSON.number(previous[entry.key]) ?? 0)
                }
            } else {
                // First event in the file, or the total restarted.
                usage = info["last_token_usage"] as? [String: Any] ?? total
            }
            let model = state["model"] ?? "gpt-5"
            let tokens = codexTokens(usage)
            return UsageRecord(key: "codex-total:\(session):\(runningTotal)", provider: .codex, account: nil, session: session,
                               kind: .runningTotal, timestamp: timestamp, model: model, tokens: tokens,
                               cost: Pricing.cost(model: model, tokens: tokens), billed: nil,
                               project: Projects.root(for: state["cwd"]))

        default:
            return nil
        }
    }

    /// Codex counts cached and cache-write tokens inside `input_tokens`, and reasoning inside `output_tokens`.
    private static func codexTokens(_ usage: [String: Any]) -> TokenCounts {
        func count(_ key: String) -> Int { Int(JSON.number(usage[key]) ?? 0) }
        let cached = count("cached_input_tokens"), writes = count("cache_write_input_tokens")
        var tokens = TokenCounts()
        tokens.input = max(count("input_tokens") - cached - writes, 0)
        tokens.cacheRead = cached
        tokens.cacheWrite = writes
        tokens.output = count("output_tokens")
        tokens.reasoning = count("reasoning_output_tokens")
        return tokens
    }

    /// Rollout files end in the session id: `rollout-<date>-<uuid>.jsonl`.
    private static func codexSession(_ file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        return name.count > 36 ? String(name.suffix(36)) : name
    }

    // MARK: Gemini CLI

    /// `~/.gemini/tmp/*/chats/*.jsonl`. Gemini records one line per model response, including
    /// cached, thought and tool-prompt tokens in a compact `tokens` object.
    static let geminiCLI = LogFeed(
        roots: [GeminiAdapter.directory.appendingPathComponent("tmp")],
        markers: [Data("\"type\":\"gemini\"".utf8), Data("\"tokens\"".utf8)]
    ) { object, file, state in
        if let session = object["sessionId"] as? String ?? object["session_id"] as? String {
            state["session"] = session
        }
        guard object["type"] as? String == "gemini",
              let usage = object["tokens"] as? [String: Any],
              let model = object["model"] as? String,
              let timestamp = Dates.parse(object["timestamp"]) else { return nil }

        func count(_ key: String) -> Int { Int(JSON.number(usage[key]) ?? 0) }
        let cached = count("cached")
        let thoughts = count("thoughts")
        var tokens = TokenCounts()
        tokens.input = max(count("input") - cached, 0) + count("tool")
        tokens.cacheRead = cached
        tokens.output = count("output") + thoughts
        tokens.reasoning = thoughts

        let session = state["session"] ?? file.deletingPathExtension().lastPathComponent
        let id = object["id"] as? String ?? String(timestamp.timeIntervalSince1970)
        return UsageRecord(
            key: "gemini:\(session):\(id)", provider: .gemini, account: nil, session: session,
            kind: .request, timestamp: timestamp, model: model, tokens: tokens,
            cost: Pricing.cost(model: model, tokens: tokens), billed: nil
        )
    }

    // MARK: Pi

    /// `~/.pi/agent/sessions/**/*.jsonl`. Pi records exact usage and cost on assistant messages,
    /// compactions and branch summaries. Entry id plus timestamp stays the same when a session is
    /// forked, so the database key also prevents copied history from being counted twice.
    static let pi = LogFeed(
        roots: [PiAdapter.sessionsDirectory],
        markers: [Data("\"usage\"".utf8), Data("\"model_change\"".utf8), Data("\"type\":\"session\"".utf8)]
    ) { object, file, state in
        let type = object["type"] as? String
        if type == "session" {
            if let session = object["id"] as? String { state["session"] = session }
            if let directory = object["cwd"] as? String { state["cwd"] = directory }
            return nil
        }
        if type == "model_change" {
            if let provider = object["provider"] as? String, let model = object["modelId"] as? String {
                state["model"] = "\(provider)/\(model)"
            }
            return nil
        }

        let usage: [String: Any]
        var timestamp = Dates.parse(object["timestamp"])
        if type == "message" {
            guard let message = object["message"] as? [String: Any], message["role"] as? String == "assistant",
                  let found = message["usage"] as? [String: Any] else { return nil }
            usage = found
            if let provider = message["provider"] as? String, let model = message["model"] as? String {
                state["model"] = "\(provider)/\(model)"
            }
            timestamp = Dates.parse(message["timestamp"]) ?? timestamp
        } else if type == "compaction" || type == "branch_summary" {
            guard let found = object["usage"] as? [String: Any] else { return nil }
            usage = found
        } else {
            return nil
        }

        guard let id = object["id"] as? String,
              let timestamp,
              let session = state["session"] ?? piSession(file) else { return nil }
        func count(_ key: String) -> Int { Int(JSON.number(usage[key]) ?? 0) }
        let tokens = TokenCounts(input: count("input"), cacheWrite: count("cacheWrite"),
                                 cacheRead: count("cacheRead"), output: count("output"))
        let logged = JSON.number((usage["cost"] as? [String: Any])?["total"]) ?? 0
        guard tokens.total > 0 || logged > 0 else { return nil }
        let model = state["model"] ?? "unknown/unknown"
        let stamp = object["timestamp"] as? String ?? String(timestamp.timeIntervalSince1970)
        return UsageRecord(
            key: "pi:\(id):\(stamp)", provider: .pi, account: nil, session: session,
            kind: .request, timestamp: timestamp, model: model, tokens: tokens,
            cost: logged > 0 ? logged : Pricing.cost(model: model, tokens: tokens), billed: nil,
            project: Projects.root(for: state["cwd"])
        )
    }

    private static func piSession(_ file: URL) -> String? {
        let name = file.deletingPathExtension().lastPathComponent
        return name.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}$"#, options: .regularExpression)
            .map { String(name[$0]) }
    }
}

/// OpenCode's CLI and desktop app share a WAL-mode SQLite ledger. It already contains one row per
/// assistant response with exact token buckets and the provider-reported cost, so this reader opens
/// it read-only and turns only those rows into Keyhop records.
///
/// OpenCode writes an assistant row when a response starts and fills its tokens in when it finishes,
/// often many seconds later, while other sessions keep writing. So the watermark follows
/// `time_updated`, not creation time, and a row counts only once it is complete: a row read
/// mid-response would otherwise be stored with partial counts that are never corrected.
enum OpenCodeFeed {
    static func records(databaseURL: URL, since: Int64) throws -> (records: [UsageRecord], watermark: Int64) {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return ([], since) }
        let source = try Database(url: databaseURL, readOnly: true)
        var records: [UsageRecord] = []
        var watermark = since
        try source.query("""
            SELECT id, session_id, time_created, time_updated, data
            FROM message
            WHERE time_updated >= ?
            ORDER BY time_updated, id
            """, [.int(since)]) { row in
            guard let id = row.text(0), let session = row.text(1), let raw = row.text(4),
                  let message = JSON.object(raw), message["role"] as? String == "assistant",
                  let usage = message["tokens"] as? [String: Any] else { return }
            // Still streaming: leave the watermark where it is so this row is read again once done.
            guard (message["time"] as? [String: Any])?["completed"] != nil else { return }
            let created = row.int(2)
            watermark = max(watermark, row.int(3))
            func count(_ key: String, in object: [String: Any]? = nil) -> Int {
                Int(JSON.number((object ?? usage)[key]) ?? 0)
            }
            let cache = usage["cache"] as? [String: Any]
            let reasoning = count("reasoning")
            let tokens = TokenCounts(input: count("input"), cacheWrite: count("write", in: cache),
                                     cacheRead: count("read", in: cache),
                                     output: count("output") + reasoning, reasoning: reasoning)
            let logged = JSON.number(message["cost"]) ?? 0
            guard tokens.total > 0 || logged > 0 else { return }
            let provider = message["providerID"] as? String
            let modelID = message["modelID"] as? String
            let model = provider.flatMap { p in modelID.map { "\(p)/\($0)" } } ?? modelID ?? "unknown/unknown"
            records.append(UsageRecord(
                key: "opencode:\(id)", provider: .opencode, account: nil, session: session,
                kind: .request, timestamp: Date(timeIntervalSince1970: Double(created) / 1000),
                model: model, tokens: tokens,
                cost: logged > 0 ? logged : Pricing.cost(model: model, tokens: tokens), billed: nil,
                project: Projects.root(for: (message["path"] as? [String: Any])?["cwd"] as? String)
            ))
        }
        return (records, watermark)
    }
}
