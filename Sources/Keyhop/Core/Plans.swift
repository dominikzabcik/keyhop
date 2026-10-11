import Foundation

/// What each paid plan is worth: what it costs a month at list price next to what the month's
/// usage would have cost at API prices, and how close its windows came to the wall this week.
/// Counted on this computer from the usage store and the limit samples; nothing is sent.
struct PlansReport: Encodable {
    struct Window: Encodable {
        let label: String
        /// The highest fill seen in the last seven days, in percent.
        let peak: Double
        let usedNow: Double?
    }

    struct Row: Encodable {
        let id: UUID
        let tool: Provider
        let toolName: String
        let name: String
        let plan: String?
        /// List price a month, or nil when Keyhop can't price the plan.
        let price: Double?
        /// The month's usage at API prices, and what was actually billed on demand where a provider says.
        let apiValue: Double
        let billed: Double
        /// API value over price. Nil without a price, or on a free plan.
        let utilisation: Double?
        let windows: [Window]
        /// "earning", "room", "wall", "free", "unknown" or "quiet".
        let standing: String
        let verdict: String
        let advice: String?
    }

    let month: String
    let rows: [Row]
    /// What the plans cost a month, counting only priced plans.
    let paid: Double
    let apiValue: Double
    let headline: String

    /// The report for these logins. `apiValue` is this month's cost per account from the usage store,
    /// `peaks` the highest fill per window label in the last week, from the limit samples.
    static func build(accounts: [Account], usage: [UUID: UsageSnapshot], apiValue: [UUID: Totals],
                      peaks: [UUID: [String: Double]], now: Date = Date()) -> PlansReport {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLLL yyyy"
        let month = formatter.string(from: now)
        let dayOfMonth = Double(Calendar.current.component(.day, from: now))
        let daysInMonth = Double(Calendar.current.range(of: .day, in: .month, for: now)?.count ?? 30)
        let elapsed = max(0.05, min(1, dayOfMonth / daysInMonth))

        var rows: [Row] = []
        for account in accounts.sorted(by: { ($0.provider.rawValue, $0.displayName) < ($1.provider.rawValue, $1.displayName) }) {
            guard account.provider.isSwitchable else { continue }
            let totals = apiValue[account.id] ?? Totals()
            let value = (totals.cost * 100).rounded() / 100
            let billed = (totals.billed * 100).rounded() / 100
            let price = PlanPrices.monthly(provider: account.provider, plan: account.plan)
            let snapshot = usage[account.id]
            let windows: [Window] = {
                var seen: [String: Window] = [:]
                for window in snapshot?.windows ?? [] {
                    let peak = max(peaks[account.id]?[window.label] ?? 0, window.usedPercent)
                    seen[window.label] = Window(label: window.label, peak: (peak * 10).rounded() / 10, usedNow: window.usedPercent)
                }
                for (label, peak) in peaks[account.id] ?? [:] where seen[label] == nil {
                    seen[label] = Window(label: label, peak: (peak * 10).rounded() / 10, usedNow: nil)
                }
                return seen.values.sorted { $0.label < $1.label }
            }()
            let highest = windows.map(\.peak).max() ?? 0
            let wall = windows.filter { $0.peak >= 90 }.map(\.label)
            let others = accounts.filter { $0.provider == account.provider && $0.id != account.id }

            var standing = "unknown"
            var verdict: String
            var advice: String? = nil
            let utilisation = price.flatMap { $0 > 0 ? value / $0 : nil }
            let projected = value / elapsed
            if !wall.isEmpty {
                standing = "wall"
                verdict = "Near the wall: \(wall.joined(separator: " and ")) peaked at \(Int(highest.rounded()))% this week."
                if let price, let next = PlanPrices.plans(for: account.provider, atLeast: price + 1).first {
                    advice = others.isEmpty
                        ? "The next plan up is \(next.plan) at \(Numbers.usd(next.monthly)) a month, or add a second login and hop between them."
                        : "Hop to another \(account.provider.name) login when it fills, or step up to \(next.plan) at \(Numbers.usd(next.monthly)) a month."
                } else if !others.isEmpty {
                    advice = "Hop to another \(account.provider.name) login when it fills."
                }
            } else if let price, price == 0 {
                standing = "free"
                verdict = value > 0 ? "A free plan carrying \(Numbers.usd(value)) of API value this month." : "A free plan, quiet this month."
            } else if let price {
                if value == 0 && highest < 5 {
                    standing = "quiet"
                    verdict = "Nothing used this month on a \(Numbers.usd(price)) plan."
                    if let cheaper = PlanPrices.plans(for: account.provider, below: price).first {
                        advice = "If that holds, \(cheaper.plan) at \(Numbers.usd(cheaper.monthly)) a month would do."
                    }
                } else if value >= price {
                    standing = "earning"
                    verdict = "Earning its keep: \(Numbers.usd(value)) of API value on a \(Numbers.usd(price)) plan, \(Int((value / price * 100).rounded()))%."
                } else if projected < price * 0.5 && highest < 60 {
                    standing = "room"
                    verdict = "\(Numbers.usd(value)) of API value so far on a \(Numbers.usd(price)) plan, on pace for \(Numbers.usd(projected)); the windows peaked at \(Int(highest.rounded()))%."
                    if let cheaper = PlanPrices.plans(for: account.provider, below: price).first(where: { $0.monthly >= projected * 1.25 }) {
                        advice = "\(cheaper.plan) at \(Numbers.usd(cheaper.monthly)) a month would cover this pace."
                    }
                } else {
                    standing = "earning"
                    verdict = "\(Numbers.usd(value)) of API value so far on a \(Numbers.usd(price)) plan, on pace for \(Numbers.usd(projected))."
                }
            } else {
                verdict = account.plan.map { "Keyhop doesn't know what \($0) costs. \(Numbers.usd(value)) of API value this month." }
                    ?? "No plan reported. \(Numbers.usd(value)) of API value this month."
            }
            rows.append(Row(id: account.id, tool: account.provider, toolName: account.provider.name, name: account.displayName,
                            plan: account.plan, price: price, apiValue: value, billed: billed, utilisation: utilisation,
                            windows: windows, standing: standing, verdict: verdict, advice: advice))
        }
        let paid = rows.compactMap(\.price).reduce(0, +)
        let total = (rows.map(\.apiValue).reduce(0, +) * 100).rounded() / 100
        let headline: String
        if rows.isEmpty {
            headline = "No logins to price yet."
        } else if paid == 0 {
            headline = "No priced plans. \(Numbers.usd(total)) of API value this month."
        } else {
            let pace = total / elapsed
            headline = "You pay \(Numbers.usd(paid)) a month for plans. This month's work is \(Numbers.usd(total)) at API prices so far, on pace for \(Numbers.usd(pace))."
        }
        return PlansReport(month: month, rows: rows, paid: paid, apiValue: total, headline: headline)
    }
}
