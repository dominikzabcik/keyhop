import Foundation

/// USD per million tokens.
struct ModelPrice: Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double?
    let cacheWrite: Double?
}

enum Pricing {
    static func price(for model: String) -> ModelPrice? {
        let name = normalize(model)
        if let exact = table[name] { return exact }
        // Variants such as "claude-opus-4-5-thinking" or "gpt-5.6-sol-high" price like their base model.
        let base = table.keys.filter { name.hasPrefix($0 + "-") }.max { $0.count < $1.count }
        return base.flatMap { table[$0] }
    }

    /// The cost at standard API prices. Zero for models without a known price.
    static func cost(model: String, tokens: TokenCounts, fast: Bool = false) -> Double {
        guard let price = price(for: model) else { return 0 }
        let cacheWrite = price.cacheWrite ?? price.input * 1.25
        let dollars = Double(tokens.input) * price.input
            + Double(tokens.cacheWrite) * cacheWrite
            + Double(tokens.cacheWrite1h) * price.input * 2
            + Double(tokens.cacheRead) * (price.cacheRead ?? price.input)
            + Double(tokens.output) * price.output
        // Fast mode on Claude Opus costs twice the standard rate.
        let multiplier = fast && normalize(model).hasPrefix("claude-opus") ? 2.0 : 1.0
        return dollars * multiplier / 1_000_000
    }

    static func normalize(_ model: String) -> String {
        var name = model.lowercased().trimmingCharacters(in: .whitespaces)
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if name.hasPrefix("cursor-") { name.removeFirst("cursor-".count) }
        return name.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
    }
}
