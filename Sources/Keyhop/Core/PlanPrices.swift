import Foundation

/// What a plan costs a month at list price, in US dollars, as of October 2026. A plan Keyhop can't
/// price is left out, so the window says so instead of guessing. Team and enterprise seats are
/// priced per seat.
enum PlanPrices {
    /// Each tool's plans, from the cheapest up. The name is matched against what the provider reports,
    /// case-insensitively, by the words it contains.
    static let ladders: [Provider: [(plan: String, monthly: Double)]] = [
        .claude: [("Free", 0), ("Pro", 20), ("Max", 100), ("Max 5x", 100), ("Max 20x", 200), ("Team", 30), ("Enterprise", 60)],
        .codex: [("Free", 0), ("Go", 5), ("Plus", 20), ("Pro", 200), ("Team", 30), ("Business", 30), ("Enterprise", 60)],
        .cursor: [("Hobby", 0), ("Free", 0), ("Pro", 20), ("Pro+", 60), ("Pro Plus", 60), ("Ultra", 200), ("Teams", 40), ("Enterprise", 60)],
        .gemini: [("Free", 0), ("Standard", 0), ("AI Pro", 20), ("Pro", 20), ("AI Ultra", 250), ("Ultra", 250)],
        .copilot: [("Free", 0), ("Pro", 10), ("Pro+", 39), ("Business", 19), ("Enterprise", 39)],
        .windsurf: [("Free", 0), ("Pro", 15), ("Teams", 30), ("Enterprise", 60)],
    ]

    /// The list price of this login's plan, or nil when Keyhop can't price it.
    static func monthly(provider: Provider, plan: String?) -> Double? {
        guard let plan, !plan.isEmpty else { return nil }
        let lower = plan.lowercased()
        // Codebuff reports its own price as "$N/mo".
        if lower.hasPrefix("$"), let dollars = Double(lower.dropFirst().split(separator: "/").first ?? "") { return dollars }
        guard let ladder = ladders[provider] else { return nil }
        // The longest name that fits wins, so "Max 20x" is not read as "Max".
        let fits = ladder.filter { lower.contains($0.plan.lowercased()) }
        return fits.max(by: { $0.plan.count < $1.plan.count })?.monthly
    }

    /// The plan-based division a price falls in: free at nothing, max from a hundred dollars a month,
    /// pro in between. One table drives both the Plans section and the website's divisions.
    static func division(monthly: Double) -> String {
        monthly <= 0 ? "free" : monthly >= 100 ? "max" : "pro"
    }

    /// The plans of this tool that cost at least this much a month, cheapest first, with a person's
    /// own plans ahead of seats on a team plan.
    static func plans(for provider: Provider, atLeast dollars: Double) -> [(plan: String, monthly: Double)] {
        let seat = ["team", "business", "enterprise"]
        let fitting = (ladders[provider] ?? []).filter { $0.monthly >= dollars }.sorted { $0.monthly < $1.monthly }
        let own = fitting.filter { plan in !seat.contains { plan.plan.lowercased().contains($0) } }
        return own.isEmpty ? fitting : own
    }

    /// The plans of this tool cheaper than this one, dearest first.
    static func plans(for provider: Provider, below dollars: Double) -> [(plan: String, monthly: Double)] {
        (ladders[provider] ?? []).filter { $0.monthly < dollars && $0.monthly > 0 }.sorted { $0.monthly > $1.monthly }
    }
}
