import Foundation

struct AlertCandidate: Codable, Equatable, Sendable {
    /// Stable per limit window or budget period, so each alert is raised once.
    let key: String
    /// Names the tool and its state: "Codex is nearly out".
    let title: String
    let body: String
    /// The saved account a Switch button should move the tool to.
    let switchTo: UUID?
    /// The account and the figure, shown under the title: "me@personal.dev · 5-hour at 93%".
    var subtitle: String? = nil
    /// The tool the alert is about, so the notification can carry its mark.
    var tool: String? = nil
    /// How urgent: "out" (at the wall), "warn" (running low), "hop" (a hop on offer) or "done" (a hop made).
    var tone: String? = nil
    /// The account a Hop button names, for its label.
    var switchName: String? = nil
}

/// When to warn: a limit nearly used up, and budgets at
/// 80% and 100%. The macOS app posts these itself; the Linux tray gets them from `keyhop refresh`.
enum AlertRules {
    static func forecastKey(_ account: UUID, _ label: String) -> String {
        "\(account.uuidString)|\(label)"
    }

    /// The hop to make for someone who turned hop-before-the-limit on: the first limit alert
    /// that names an account with room. The alert's key comes along so each window triggers at
    /// most one hop.
    static func autoHop(from alerts: [AlertCandidate], accounts: [Account]) -> (key: String, to: Account)? {
        for alert in alerts where alert.key.hasPrefix("limit:") {
            guard let id = alert.switchTo, let account = accounts.first(where: { $0.id == id }) else { continue }
            return (alert.key, account)
        }
        return nil
    }

    static func evaluate(accounts: [Account], active: [Provider: UUID], usage: [UUID: UsageSnapshot],
                         forecasts: [String: Date], budgets: [Budget], budgetSpend: [String: Double],
                         now: Date) -> [AlertCandidate] {
        var alerts: [AlertCandidate] = []

        for provider in Provider.allCases {
            guard let id = active[provider], let account = accounts.first(where: { $0.id == id }),
                  let snapshot = usage[id], snapshot.error == nil else { continue }
            for window in snapshot.windows {
                // Only what is measured: a window at 90% or more. No guesses about when one runs out.
                guard window.usedPercent >= 90 else { continue }

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

                // KB-Notify: the title names the tool and its state, the subtitle the account and the
                // figure, and the body what to do about it.
                let used = Int(window.usedPercent.rounded())
                let title = "\(provider.name) is nearly out"
                let subtitle = "\(account.displayName) · \(windowWord(window.label)) at \(used)%"
                let body = alternative.map { "\($0.name) has \(Int($0.room.rounded()))% left. Hop now and keep going." }
                    ?? "No other \(provider.name) login has room. Add one to hop next time."
                let windowID = window.resetsAt.map { String(Int($0.timeIntervalSince1970 / 3600)) } ?? "open"
                alerts.append(AlertCandidate(key: "limit:\(id.uuidString):\(window.label):\(windowID):90",
                                             title: title, body: body, switchTo: alternative?.account,
                                             subtitle: subtitle, tool: provider.rawValue,
                                             tone: alternative == nil ? "out" : "warn",
                                             switchName: alternative?.name))
            }
        }

        for budget in budgets where budget.amount > 0 {
            let spent = budgetSpend[budget.scope] ?? 0
            let share = spent / budget.amount
            guard let threshold = [1.0, 0.8].first(where: { share >= $0 }) else { continue }
            let account = budget.account.flatMap { id in accounts.first { $0.id == id }?.displayName }
            // A budget over every account is a plural subject, and the budget is the whole set's.
            let name = account ?? "All accounts"
            let verb = account == nil ? "are" : "is"
            let whose = account == nil ? "the" : "its"
            let used = account == nil ? "have used" : "used"
            let periodStart = Int(budget.period.interval(containing: now).start.timeIntervalSince1970)
            alerts.append(AlertCandidate(
                key: "budget:\(budget.scope):\(periodStart):\(Int(threshold * 100))",
                title: threshold >= 1
                    ? "\(name) \(verb) over \(whose) \(budget.period.adjective) budget"
                    : "\(name) \(used) 80% of \(whose) \(budget.period.adjective) budget",
                body: threshold >= 1 ? "Over by \(Numbers.usd(spent - budget.amount))." : "Keyhop tells you again at 100%.",
                switchTo: nil,
                subtitle: "\(Numbers.usd(spent)) of \(Numbers.usd(budget.amount))",
                tone: threshold >= 1 ? "out" : "warn"
            ))
        }
        return alerts
    }

    /// A window's name as the notification says it: "5-hour", "weekly".
    static func windowWord(_ label: String) -> String {
        switch label {
        case "5h": "5-hour"
        case "Week": "weekly"
        case "Opus": "Opus weekly"
        case "Sonnet": "Sonnet weekly"
        default: label.lowercased()
        }
    }
}
