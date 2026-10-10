import XCTest
@testable import Keyhop

final class MeasuredFeedTests: XCTestCase {
    private func records(_ feed: LogFeed, _ lines: [String], file: URL) -> [UsageRecord] {
        var state: [String: String] = [:]
        var result: [UsageRecord] = []
        for line in lines {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            result.append(contentsOf: feed.parse(object, file, &state))
        }
        return result
    }

    // MARK: Qwen Code

    private let qwenFile = URL(fileURLWithPath: "/tmp/qwen/projects/demo/chats/chat-1.jsonl")

    func testQwenAssistantRecordsCountGeminiShapedUsage() {
        let line = #"{"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-10-01T08:00:00Z","cwd":"/tmp","model":"qwen3-coder-plus","usageMetadata":{"promptTokenCount":1000,"candidatesTokenCount":200,"thoughtsTokenCount":50,"cachedContentTokenCount":600,"totalTokenCount":1250}}"#
        let result = records(MeasuredFeeds.qwen, [line], file: qwenFile)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "qwen:u1")
        XCTAssertEqual(result[0].provider, .qwen)
        XCTAssertEqual(result[0].session, "s1")
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 400, cacheRead: 600, output: 250, reasoning: 50))
    }

    func testQwenSkipsForkedCopiesAndOtherRecordTypes() {
        let forked = #"{"type":"assistant","uuid":"u1","forkedFrom":"s0","timestamp":"2026-10-01T08:00:00Z","usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}"#
        let user = #"{"type":"user","uuid":"u2","timestamp":"2026-10-01T08:00:00Z","usageMetadata":{"promptTokenCount":10}}"#
        XCTAssertTrue(records(MeasuredFeeds.qwen, [forked, user], file: qwenFile).isEmpty)
    }

    // MARK: Kimi Code

    private let kimiFile = URL(fileURLWithPath: "/tmp/kimi/sessions/wd_demo_abc123/sess-1/agents/agent-9/wire.jsonl")
    private let kimiLegacyFile = URL(fileURLWithPath: "/tmp/kimi/sessions/d41d8cd9/sess-legacy/wire.jsonl")

    func testKimiCountsBothTurnAndSessionScopedRecords() {
        let turn = #"{"type":"usage.record","agentId":"agent-9","model":"kimi-k2","usage":{"inputOther":100,"output":40,"inputCacheRead":25,"inputCacheCreation":10},"usageScope":"turn","time":1776162403000}"#
        let operation = #"{"type":"usage.record","agentId":"agent-9","model":"kimi-k2","usage":{"inputOther":5,"output":2,"inputCacheRead":0,"inputCacheCreation":0},"usageScope":"session","time":1776162404000}"#
        let result = records(MeasuredFeeds.kimi, [turn, operation], file: kimiFile)
        XCTAssertEqual(result.count, 2, "operation-scoped records are per-request deltas too")
        XCTAssertEqual(result[0].session, "sess-1")
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 100, cacheWrite: 10, cacheRead: 25, output: 40))
        XCTAssertEqual(result[0].model, "kimi-k2")
    }

    func testKimiLegacyStatusUpdatesStillCount() {
        let line = #"{"timestamp":1776162403,"message":{"type":"StatusUpdate","payload":{"message_id":"msg-1","token_usage":{"input_other":100,"input_cache_read":25,"input_cache_creation":10,"output":40}}}}"#
        let result = records(MeasuredFeeds.kimi, [line], file: kimiLegacyFile)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "kimi:sess-legacy:msg-1")
        XCTAssertEqual(result[0].session, "sess-legacy")
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 100, cacheWrite: 10, cacheRead: 25, output: 40))
    }

    // MARK: OpenClaw

    private let openclawFile = URL(fileURLWithPath: "/tmp/openclaw/sessions/run-1.jsonl")

    func testOpenClawReadsPiShapedMessages() {
        let lines = [
            #"{"type":"session","id":"oc-1","cwd":"/tmp/project"}"#,
            #"{"type":"model_change","provider":"anthropic","modelId":"claude-opus-5"}"#,
            #"{"type":"message","id":"m1","timestamp":"2026-10-01T08:00:00Z","message":{"role":"assistant","usage":{"input":100,"output":50,"cacheRead":20,"cacheWrite":5,"cost":{"total":0.12}}}}"#,
        ]
        let result = records(MeasuredFeeds.openclaw, lines, file: openclawFile)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].provider, .openclaw)
        XCTAssertEqual(result[0].session, "oc-1")
        XCTAssertEqual(result[0].model, "anthropic/claude-opus-5")
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 100, cacheWrite: 5, cacheRead: 20, output: 50))
        XCTAssertEqual(result[0].cost, 0.12, accuracy: 1e-9)
    }

    // MARK: Grok Build

    private let grokFile = URL(fileURLWithPath: "/tmp/grok/sessions/cwd/abc/updates.jsonl")

    func testGrokTurnsSplitPerModelWithExactCost() {
        let line = #"{"params":{"sessionId":"g1","_meta":{"eventId":"evt-1","agentTimestampMs":1776162403000},"update":{"sessionUpdate":"turn_completed","usage":{"inputTokens":1000,"outputTokens":100,"cachedReadTokens":700,"cacheCreationTokens":100,"reasoningTokens":30,"costUsdTicks":250000000,"modelUsage":{"grok-4":{"inputTokens":800,"outputTokens":80,"cachedReadTokens":600,"cacheCreationTokens":100,"reasoningTokens":20,"costUsdTicks":200000000},"grok-4-mini":{"inputTokens":200,"outputTokens":20,"cachedReadTokens":100,"cacheCreationTokens":0,"reasoningTokens":10,"costUsdTicks":50000000}}}}}}"#
        let result = records(MeasuredFeeds.grok, [line], file: grokFile)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.model), ["grok-4", "grok-4-mini"])
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 100, cacheWrite: 100, cacheRead: 600, output: 80, reasoning: 20))
        XCTAssertEqual(result[0].cost, 0.02, accuracy: 1e-9)
        XCTAssertEqual(result[0].session, "g1")
        XCTAssertEqual(Set(result.map(\.key)).count, 2, "each model keeps its own key")
    }

    func testGrokTurnWithoutModelSplitStillCounts() {
        let line = #"{"params":{"sessionId":"g1","_meta":{"eventId":"evt-2","agentTimestampMs":1776162403000},"update":{"sessionUpdate":"turn_completed","usage":{"inputTokens":100,"outputTokens":10,"cachedReadTokens":0,"cacheCreationTokens":0,"costUsdTicks":10000000}}}}"#
        let result = records(MeasuredFeeds.grok, [line], file: grokFile)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].cost, 0.001, accuracy: 1e-12)
    }

    func testGrokIgnoresOtherUpdates() {
        let line = #"{"params":{"sessionId":"g1","update":{"sessionUpdate":"message","usage":{"inputTokens":5}}}}"#
        XCTAssertTrue(records(MeasuredFeeds.grok, [line], file: grokFile).isEmpty)
    }

    // MARK: Goose

    func testGooseLedgerRowsBecomeRecords() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("goose-\(UUID().uuidString).db")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let db = try Database(url: url)
        try db.script("""
            CREATE TABLE usage_ledger (id TEXT PRIMARY KEY, session_id TEXT, created_timestamp INTEGER, model TEXT,
                input_tokens INTEGER, output_tokens INTEGER, total_tokens INTEGER,
                cache_read_tokens INTEGER, cache_write_tokens INTEGER, cost REAL, cost_source TEXT, is_compaction INTEGER);
            INSERT INTO usage_ledger VALUES ('l1', 's1', 1776162403, 'claude-opus-5', 100, 50, 150, 20, 5, 0.3, 'provider', 0);
            INSERT INTO usage_ledger VALUES ('l2', 's1', 1776162404, 'claude-opus-5', 0, 0, 0, 0, 0, 0, 'provider', 0);
            """)
        let result = try MeasuredFeeds.gooseRecords(databaseURL: url, since: 0)
        XCTAssertEqual(result.records.count, 1, "empty rows don't count")
        XCTAssertEqual(result.records[0].key, "goose:l1")
        XCTAssertEqual(result.records[0].tokens, TokenCounts(input: 100, cacheWrite: 5, cacheRead: 20, output: 50))
        XCTAssertEqual(result.records[0].cost, 0.3, accuracy: 1e-9)
        XCTAssertEqual(result.watermark, 1776162404)
    }

    func testGooseWithoutALedgerIsSkipped() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("goose-old-\(UUID().uuidString).db")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let db = try Database(url: url)
        try db.script("CREATE TABLE sessions (id TEXT PRIMARY KEY, total_tokens INTEGER);")
        let result = try MeasuredFeeds.gooseRecords(databaseURL: url, since: 0)
        XCTAssertTrue(result.records.isEmpty)
    }

    // MARK: Kilo

    func testKiloReusesTheOpenCodeSchemaUnderItsOwnName() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kilo-\(UUID().uuidString).db")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let db = try Database(url: url)
        let data = #"{"role":"assistant","providerID":"anthropic","modelID":"claude-opus-5","cost":0.2,"time":{"completed":1776162403000},"tokens":{"input":100,"output":50,"reasoning":0,"cache":{"read":20,"write":5}}}"#
        try db.script("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")
        try db.execute("INSERT INTO message VALUES ('m1', 's1', 1776162403000, 1776162403000, ?)", [.text(data)])
        let result = try OpenCodeFeed.records(databaseURL: url, since: 0, provider: .kilo)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records[0].key, "kilo:m1")
        XCTAssertEqual(result.records[0].provider, .kilo)
    }

    // MARK: Amp

    func testAmpLedgerEventsJoinCacheTokensFromTheirMessage() {
        let thread = #"{"id":"T-abc","messages":[{"messageId":"m1","usage":{"model":"claude-opus-5","inputTokens":100,"outputTokens":50,"cacheCreationInputTokens":30,"cacheReadInputTokens":400,"totalTokens":580}}],"usageLedger":{"events":[{"id":"e1","timestamp":"2026-10-01T08:00:00Z","model":"claude-opus-5","tokens":{"input":100,"output":50,"total":580},"toMessageId":"m1","credits":12}]}}"#
        let result = MeasuredFeeds.ampRecords(Data(thread.utf8))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "amp:T-abc:e1")
        XCTAssertEqual(result[0].session, "T-abc")
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 100, cacheWrite: 30, cacheRead: 400, output: 50))
    }

    func testAmpFallsBackToMessageUsageWithoutALedger() {
        let thread = #"{"id":"T-xyz","messages":[{"messageId":"m1","usage":{"model":"claude-opus-5","timestamp":"2026-10-01T08:00:00Z","inputTokens":10,"outputTokens":5,"cacheCreationInputTokens":1,"cacheReadInputTokens":2}},{"messageId":"m2"}]}"#
        let result = MeasuredFeeds.ampRecords(Data(thread.utf8))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "amp:T-xyz:m1")
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 10, cacheWrite: 1, cacheRead: 2, output: 5))
    }

    func testAmpRereadsCountNothingTwiceThroughKeys() {
        let thread = #"{"id":"T-abc","messages":[],"usageLedger":{"events":[{"id":"e1","timestamp":"2026-10-01T08:00:00Z","model":"m","tokens":{"input":10,"output":5}}]}}"#
        let first = MeasuredFeeds.ampRecords(Data(thread.utf8))
        let second = MeasuredFeeds.ampRecords(Data(thread.utf8))
        XCTAssertEqual(first.map(\.key), second.map(\.key), "keys are stable, so the database dedups rereads")
    }
}
