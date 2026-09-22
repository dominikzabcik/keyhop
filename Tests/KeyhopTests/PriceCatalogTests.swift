import XCTest
@testable import Keyhop

/// Prices read from models.dev between releases.
final class PriceCatalogTests: XCTestCase {
    private func catalog(_ providers: [String: [String: [String: Double]]]) -> Data {
        let body = providers.mapValues { models in ["models": models.mapValues { ["cost": $0] }] }
        return try! JSONSerialization.data(withJSONObject: body)
    }

    func testStandardPricesAreReadAndResellersIgnored() {
        let data = catalog([
            "anthropic": ["claude-new-7": ["input": 4, "output": 20, "cache_read": 0.4, "cache_write": 5]],
            "openrouter": ["anthropic/claude-new-7": ["input": 9, "output": 99]],
            "openai": ["gpt-free": ["input": 1]],
        ])
        let prices = PriceCatalog.parse(data)
        XCTAssertEqual(prices["claude-new-7"], ModelPrice(input: 4, output: 20, cacheRead: 0.4, cacheWrite: 5))
        XCTAssertNil(prices["gpt-free"], "a model without an output price isn't priced")
        XCTAssertEqual(prices.count, 1)
    }

    func testTheFirstListedProviderWins() {
        let data = catalog([
            "anthropic": ["claude-shared": ["input": 3, "output": 15]],
            "alibaba": ["claude-shared": ["input": 1, "output": 1]],
        ])
        XCTAssertEqual(PriceCatalog.parse(data)["claude-shared"]?.input, 3)
    }

    /// Usage stored before its model had a price gets one; usage that already had a cost, from a
    /// price or from the tool itself, keeps it.
    func testUnpricedHistoryIsPricedOnceAPriceIsKnown() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-prices-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = try TrackerEngine(url: folder.appendingPathComponent("usage.sqlite"))
        let when = Date().addingTimeInterval(-60)
        func record(_ key: String, _ model: String, cost: Double) -> UsageRecord {
            UsageRecord(key: key, provider: .opencode, account: nil, session: nil, kind: .request, timestamp: when,
                        model: model, tokens: TokenCounts(input: 1_000_000, output: 1_000_000), cost: cost, billed: nil)
        }
        try await engine.store([
            record("unknown", "zai/glm-5", cost: 0),
            record("reported", "zai/glm-5", cost: 0.42),
            record("nothing-known", "someone/brand-new", cost: 0),
        ])
        let priced = try await engine.priceUnpriced()
        XCTAssertEqual(priced, Pricing.price(for: "glm-5") == nil ? 0 : 1)

        let day = DateInterval(start: when.addingTimeInterval(-60), end: Date().addingTimeInterval(60))
        let digest = try await engine.digest(interval: day, previous: day, bucket: .hour, provider: nil, sole: [:])
        let glm = try XCTUnwrap(Pricing.price(for: "glm-5"))
        let expected = glm.input + glm.output + 0.42
        XCTAssertEqual(digest.byModel[ModelKey(provider: .opencode, model: "glm-5")]?.cost ?? 0, expected, accuracy: 0.0001)
        XCTAssertEqual(digest.byModel[ModelKey(provider: .opencode, model: "brand-new")]?.cost, 0)
        let again = try await engine.priceUnpriced()
        XCTAssertEqual(again, 0, "pricing twice changes nothing")
    }
}
