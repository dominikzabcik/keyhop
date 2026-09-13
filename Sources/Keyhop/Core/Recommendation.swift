import Foundation

struct AccountRecommendation: Codable, Equatable, Sendable {
    let tool: String
    let account: UUID
    let name: String
    let email: String
    let active: Bool
    let room: Double
    let budgetRemaining: Double?
    let resetsAt: Date?
    let runsOutAt: Date?
    let reason: String
}

enum SmartHop {
    private struct Candidate {
        let recommendation: AccountRecommendation
        let score: Double
    }

    static func recommendation(
        for provider: Provider,
        accounts: [Account],
        active: [Provider: UUID],
        usage: [UUID: UsageSnapshot],
        forecasts: [String: Date],
        budgets: [Budget],
        budgetSpend: [String: Double],
        excluding excluded: Set<UUID> = [],
        now: Date = Date()
    ) -> AccountRecommendation? {
        accounts
            .filter { $0.provider == provider && !excluded.contains($0.id) }
            .compactMap { candidate($0, active: active, usage: usage, forecasts: forecasts,
                                    budgets: budgets, budgetSpend: budgetSpend, now: now) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.recommendation.account.uuidString < $1.recommendation.account.uuidString
            }
            .first?
            .recommendation
    }

    static func recommendations(
        accounts: [Account],
        active: [Provider: UUID],
        usage: [UUID: UsageSnapshot],
        forecasts: [String: Date],
        budgets: [Budget],
        budgetSpend: [String: Double],
        now: Date = Date()
    ) -> [AccountRecommendation] {
        Provider.allCases.compactMap {
            recommendation(for: $0, accounts: accounts, active: active, usage: usage, forecasts: forecasts,
                           budgets: budgets, budgetSpend: budgetSpend, now: now)
        }
    }

    private static func candidate(
        _ account: Account,
        active: [Provider: UUID],
        usage: [UUID: UsageSnapshot],
        forecasts: [String: Date],
        budgets: [Budget],
        budgetSpend: [String: Double],
        now: Date
    ) -> Candidate? {
        guard let snapshot = usage[account.id], snapshot.error == nil, !snapshot.windows.isEmpty,
              let tightest = snapshot.windows.min(by: { room($0) < room($1) }) else { return nil }
        let remaining = room(tightest)
        let scope = Budget.scope(for: account.id)
        let budget = budgets.first { $0.scope == scope } ?? budgets.first { $0.scope == Budget.everything }
        let budgetRemaining = budget.map { max(0, min(100, (1 - (budgetSpend[$0.scope] ?? 0) / max($0.amount, 0.01)) * 100)) }
        let runOut = snapshot.windows.compactMap { forecasts[AlertRules.forecastKey(account.id, $0.label)] }
            .filter { $0 > now }
            .min()
        let hoursToReset = tightest.resetsAt.map { max(0, $0.timeIntervalSince(now) / 3600) }
        let resetBonus = hoursToReset.map { max(0, 12 - min($0, 12)) * 0.5 } ?? 0
        let forecastPenalty = runOut == nil ? 0 : 30
        let score = remaining * 0.75 + (budgetRemaining ?? 100) * 0.25 + resetBonus - Double(forecastPenalty)
        let reason: String
        if let budgetRemaining, budgetRemaining < 30 {
            reason = "\(percent(remaining))% limit room and \(percent(budgetRemaining))% of its budget left."
        } else if let hoursToReset, hoursToReset < 2 {
            reason = "\(percent(remaining))% left; its tightest limit resets \(relativeReset(hoursToReset))."
        } else if runOut != nil {
            reason = "\(percent(remaining))% left, but recent use projects an early limit."
        } else {
            reason = "\(percent(remaining))% left on its tightest limit; the best available runway."
        }
        return Candidate(
            recommendation: AccountRecommendation(
                tool: account.provider.rawValue,
                account: account.id,
                name: account.displayName,
                email: account.email,
                active: active[account.provider] == account.id,
                room: remaining,
                budgetRemaining: budgetRemaining,
                resetsAt: tightest.resetsAt,
                runsOutAt: runOut,
                reason: reason
            ),
            score: score
        )
    }

    private static func room(_ window: UsageWindow) -> Double {
        max(0, min(100, 100 - window.usedPercent))
    }

    private static func percent(_ value: Double) -> Int {
        Int(value.rounded())
    }

    private static func relativeReset(_ hours: Double) -> String {
        let minutes = max(1, Int((hours * 60).rounded()))
        return minutes >= 60 ? "in \(minutes / 60)h \(minutes % 60)m" : "in \(minutes)m"
    }
}
