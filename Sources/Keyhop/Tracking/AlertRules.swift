import Foundation

struct AlertCandidate: Codable, Equatable, Sendable {
    /// Stable per limit window or budget period, so each alert is raised once.
    let key: String
    let title: String
    let body: String
    /// The saved account a Switch button should move the tool to.
    let switchTo: UUID?
}

/// When to warn: a limit nearly used up or on track to run out before it resets, and budgets at
/// 80% and 100%. The macOS app posts these itself; the Linux tray gets them from `keyhop refresh`.
enum AlertRules {
    static func forecastKey(_ account: UUID, _ label: String) -> String {
        "\(account.uuidString)|\(label)"
    }

    static func evaluate(accounts: [Account], active: [Provider: UUID], usage: [UUID: UsageSnapshot],
                         forecasts: [String: Date], budgets: [Budget], budgetSpend: [String: Double],
                         now: Date) -> [AlertCandidate] {
        var alerts: [AlertCandidate] = []

        for provider in Provider.allCases {
            guard let id = active[provider], let account = accounts.first(where: { $0.id == id }),
                  let snapshot = usage[id], snapshot.error == nil else { continue }
            for window in snapshot.windows {
                let eta = forecasts[forecastKey(id, window.label)]
                let nearlyOut = window.usedPercent >= 90
                // Early in a window a few samples can project a run-out that never happens.
                guard nearlyOut || (eta != nil && window.usedPercent >= 50) else { continue }

                let alternative = SmartHop.recommendation(
                    for: provider,
                    accounts: accounts,
                    active: active,
                    usage: usage,
                    forecasts: forecasts,
                    budgets: budgets,
                    budgetSpend: budgetSpend,
                    excluding: [id],
                    now: now
                ).flatMap { $0.room >= 20 ? $0 : nil }

                let title = nearlyOut
                    ? "\(provider.name) \(window.label.lowercased()) limit at \(Int(window.usedPercent.rounded()))%"
                    : "\(provider.name) \(window.label.lowercased()) limit runs out around \(eta!.formatted(date: .omitted, time: .shortened))"
                let body = alternative.map { "\(account.displayName) is close to its limit. \($0.name) has \(Int($0.room.rounded()))% left." }
                    ?? "\(account.displayName) is close to its limit, and no other saved \(provider.name) account has room."
                let windowID = window.resetsAt.map { String(Int($0.timeIntervalSince1970 / 3600)) } ?? "open"
                alerts.append(AlertCandidate(key: "limit:\(id.uuidString):\(window.label):\(windowID):\(nearlyOut ? "90" : "pace")",
                                             title: title, body: body, switchTo: alternative?.account))
            }
        }

        for budget in budgets where budget.amount > 0 {
            let spent = budgetSpend[budget.scope] ?? 0
            let share = spent / budget.amount
            guard let threshold = [1.0, 0.8].first(where: { share >= $0 }) else { continue }
            let name = budget.account.flatMap { id in accounts.first { $0.id == id }?.displayName } ?? "All accounts"
            let periodStart = Int(budget.period.interval(containing: now).start.timeIntervalSince1970)
            alerts.append(AlertCandidate(
                key: "budget:\(budget.scope):\(periodStart):\(Int(threshold * 100))",
                title: threshold >= 1 ? "\(name) is over its \(budget.period.adjective) budget" : "\(name) used 80% of its \(budget.period.adjective) budget",
                body: "\(Numbers.usd(spent)) of \(Numbers.usd(budget.amount)) at API prices.",
                switchTo: nil
            ))
        }
        return alerts
    }
}
