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
}
