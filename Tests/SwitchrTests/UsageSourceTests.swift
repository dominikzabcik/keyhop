import XCTest
@testable import Switchr

final class LogFeedTests: XCTestCase {
    private let rolloutFile = URL(fileURLWithPath: "/tmp/rollout-2026-09-10T08-00-00-0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b.jsonl")

    private func records(_ feed: LogFeed, _ lines: [String]) -> [UsageRecord] {
        var state: [String: String] = [:]
        var result: [UsageRecord] = []
        for line in lines {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if let record = feed.parse(object, rolloutFile, &state) { result.append(record) }
        }
        return result
    }

    func testClaudeResponseSplitsCacheWritesByLifetime() {
        let line = #"{"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"2026-09-10T08:00:00.123Z","message":{"id":"msg_1","model":"claude-opus-5","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":5000,"output_tokens":200,"cache_creation":{"ephemeral_1h_input_tokens":800,"ephemeral_5m_input_tokens":200}}}}"#
        let result = records(.claudeCode, [line])
        XCTAssertEqual(result.count, 1)
        let record = result[0]
        XCTAssertEqual(record.key, "claude:msg_1:req_1")
        XCTAssertEqual(record.tokens, TokenCounts(input: 10, cacheWrite: 200, cacheWrite1h: 800, cacheRead: 5000, output: 200))
        XCTAssertEqual(record.model, "claude-opus-5")
        XCTAssertGreaterThan(record.cost, 0)
    }

    func testClaudeSkipsSyntheticAndNonAssistantLines() {
        let synthetic = #"{"type":"assistant","timestamp":"2026-09-10T08:00:00Z","message":{"id":"m","model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}"#
        let user = #"{"type":"user","timestamp":"2026-09-10T08:00:00Z","message":{"role":"user","usage":{"input_tokens":1}}}"#
        XCTAssertTrue(records(.claudeCode, [synthetic, user]).isEmpty)
    }

    func testClaudeKeysStayStableWithoutAMessageID() {
        let line = #"{"type":"assistant","uuid":"line-1","timestamp":"2026-09-10T08:00:00Z","message":{"model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1}}}"#
        XCTAssertEqual(records(.claudeCode, [line]).map(\.key), records(.claudeCode, [line]).map(\.key))
    }

    func testCodexRecordsCountCachedTokensInsideInput() {
        let lines = [
            #"{"timestamp":"2026-09-10T08:00:00Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"#,
            #"{"timestamp":"2026-09-10T08:00:01Z","type":"token_usage_record","payload":{"response_id":"resp_1","session_id":"s","usage":{"input_tokens":1000,"cached_input_tokens":800,"cache_write_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":20,"total_tokens":1050}}}"#,
        ]
        let result = records(.codex, lines)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "codex:resp_1")
        XCTAssertEqual(result[0].model, "gpt-5.6-sol")
        XCTAssertEqual(result[0].kind, .request)
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 200, cacheRead: 800, output: 50, reasoning: 20))
    }

    func testCodexRunningTotalsBecomeDifferences() {
        func event(_ total: String, _ last: String) -> String {
            #"{"timestamp":"2026-09-10T08:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":"# + total + #","last_token_usage":"# + last + #"}}}"#
        }
        let first = #"{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":110}"#
        let second = #"{"input_tokens":300,"cached_input_tokens":100,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":330}"#
        let restarted = #"{"input_tokens":50,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":55}"#
        let result = records(.codex, [event(first, first), event(second, second), event(second, second), event(restarted, restarted)])

        XCTAssertEqual(result.map(\.kind), [.runningTotal, .runningTotal, .runningTotal])
        XCTAssertEqual(result[0].tokens, TokenCounts(input: 100, output: 10))
        XCTAssertEqual(result[1].tokens, TokenCounts(input: 100, cacheRead: 100, output: 20))
        XCTAssertEqual(result[2].tokens, TokenCounts(input: 50, output: 5))
    }
}

final class CursorUsageTests: XCTestCase {
    func testPoolsBecomeSeparateWindows() {
        let body: [String: Any] = [
            "billingCycleStart": "2026-09-01T00:00:00.000Z",
            "billingCycleEnd": "2026-10-01T00:00:00.000Z",
            "individualUsage": ["plan": ["autoPercentUsed": 62, "apiPercentUsed": 39]],
        ]
        let windows = CursorAdapter.windows(body)
        XCTAssertEqual(windows.map(\.label), ["Auto", "API"])
        XCTAssertEqual(windows.map(\.usedPercent), [62, 39])
        XCTAssertEqual(windows[0].windowSeconds, 30 * 86400)
    }

    func testPlansWithoutPoolsReportCentsAgainstTheCap() {
        let body: [String: Any] = ["individualUsage": ["plan": ["used": 500, "limit": 2000]]]
        XCTAssertEqual(CursorAdapter.windows(body).map(\.label), ["Plan"])
        XCTAssertEqual(CursorAdapter.windows(body).first?.usedPercent, 25)
    }

    func testExportRowsBecomePricedRecords() throws {
        let csv = """
        Date,Cloud Agent ID,Automation ID,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost
        2026-09-10T10:09:23.757Z,,,Included,claude-4.5-sonnet,No,1500,1000,20000,300,21800,Included
        2026-09-10T10:08:00.000Z,,,"Errored, No Charge",gpt-5,No,0,0,0,0,0,Free
        2026-09-10T10:07:00.000Z,,,On-Demand,unknown-model,No,100,100,0,10,110,$0.12
        """
        let account = UUID()
        let records = try CursorAdapter.usageRecords(csv: csv, account: account)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].tokens, TokenCounts(input: 1000, cacheWrite: 500, cacheRead: 20000, output: 300))
        XCTAssertNil(records[0].billed)
        XCTAssertEqual(records[0].account, account)
        XCTAssertEqual(records[1].billed, 0.12)
        XCTAssertEqual(records[1].cost, 0.12, accuracy: 1e-9)
    }

    func testChangedExportFormatIsReported() {
        XCTAssertThrowsError(try CursorAdapter.usageRecords(csv: "Something,Else\n1,2\n", account: UUID()))
    }
}
