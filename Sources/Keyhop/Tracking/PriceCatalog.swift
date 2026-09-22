import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Model prices kept current between releases.
///
/// Keyhop ships with the prices models.dev listed when it was built. New models arrive faster than
/// releases do, so once a day Keyhop reads models.dev again and keeps the prices it lists, in a
/// small file beside the usage database. Those take precedence over the built-in ones; when the
/// file is missing or models.dev can't be reached, the built-in prices are used as before.
enum PriceCatalog {
    static let source = URL(string: "https://models.dev/api.json")!
    /// The providers whose models the tracked tools run. Resellers (OpenRouter, Bedrock and the
    /// like) list the same models at their own prices, which aren't the standard API price.
    static let providers = ["anthropic", "openai", "google", "xai", "deepseek", "moonshotai", "zai",
                            "alibaba", "mistral", "minimax", "meta"]
    static let fileName = "prices.json"
    static let maxAge: TimeInterval = 24 * 3600

    private static let state = State()

    /// A downloaded price for this normalized model name, if there is one.
    static func price(exact name: String) -> ModelPrice? { state.prices[name] }

    /// Every model name with a downloaded price, for matching variants to their base model.
    static var names: Dictionary<String, ModelPrice>.Keys { state.prices.keys }

    /// How many downloaded prices are in use and when they were read, or nil when only the
    /// built-in ones are.
    static var summary: (count: Int, updated: Date)? {
        state.updated.map { (state.prices.count, $0) }
    }

    /// Reads the saved prices from `directory`, once per directory.
    static func load(from directory: URL) {
        let url = directory.appendingPathComponent(fileName)
        guard state.loadedFrom != url.path else { return }
        state.loadedFrom = url.path
        guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        state.set(saved.prices.mapValues(\.price), updated: saved.updated)
    }

    /// Reads models.dev again when the saved prices are more than a day old. Returns whether the
    /// prices changed. Quiet on failure: the prices already in use stay.
    @discardableResult
    static func refreshIfStale(in directory: URL, now: Date = Date()) async -> Bool {
        load(from: directory)
        if let updated = state.updated, now.timeIntervalSince(updated) < maxAge { return false }
        var request = URLRequest(url: source, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("keyhop/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        guard let (data, status) = try? await HTTP.send(request), status == 200 else { return false }
        let prices = parse(data)
        // A catalog this small is a broken answer, not a price list; keep what we have.
        guard prices.count >= 20 else { return false }
        let changed = prices != state.prices
        state.set(prices, updated: now)
        let saved = Saved(updated: now, prices: prices.mapValues(SavedPrice.init))
        if let encoded = try? JSONEncoder().encode(saved) {
            try? encoded.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        }
        return changed
    }

    /// The standard prices in a models.dev catalog, keyed the way `Pricing.normalize` names
    /// models. Where two providers list one model, the first in `providers` wins.
    static func parse(_ data: Data) -> [String: ModelPrice] {
        guard let catalog = JSON.object(data) else { return [:] }
        var prices: [String: ModelPrice] = [:]
        for provider in providers {
            let models = (catalog[provider] as? [String: Any])?["models"] as? [String: Any] ?? [:]
            for (id, value) in models.sorted(by: { $0.key < $1.key }) {
                guard let cost = (value as? [String: Any])?["cost"] as? [String: Any],
                      let input = JSON.number(cost["input"]), let output = JSON.number(cost["output"]) else { continue }
                let name = Pricing.normalize(id)
                guard prices[name] == nil else { continue }
                prices[name] = ModelPrice(input: input, output: output,
                                          cacheRead: JSON.number(cost["cache_read"]), cacheWrite: JSON.number(cost["cache_write"]))
            }
        }
        return prices
    }

    // MARK: Saved form

    private struct Saved: Codable {
        let updated: Date
        let prices: [String: SavedPrice]
    }

    private struct SavedPrice: Codable {
        let input: Double
        let output: Double
        let cacheRead: Double?
        let cacheWrite: Double?

        init(_ price: ModelPrice) {
            input = price.input
            output = price.output
            cacheRead = price.cacheRead
            cacheWrite = price.cacheWrite
        }

        var price: ModelPrice { ModelPrice(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite) }
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _prices: [String: ModelPrice] = [:]
        private var _updated: Date?
        private var _loadedFrom: String?

        var prices: [String: ModelPrice] { lock.withLock { _prices } }
        var updated: Date? { lock.withLock { _updated } }
        var loadedFrom: String? {
            get { lock.withLock { _loadedFrom } }
            set { lock.withLock { _loadedFrom = newValue } }
        }

        func set(_ prices: [String: ModelPrice], updated: Date) {
            lock.withLock {
                _prices = prices
                _updated = updated
            }
        }
    }
}
