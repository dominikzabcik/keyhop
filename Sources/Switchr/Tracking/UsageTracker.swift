import Foundation
import SwiftUI

/// The app-facing side of usage tracking: keeps today's totals, budgets, and limit forecasts
/// current for the menu, answers Insights queries, and raises alerts.
@MainActor
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    @Published private(set) var revision = 0
    @Published private(set) var isUpdating = false
    @Published private(set) var today: [UUID: Totals] = [:]
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var budgetSpend: [String: Double] = [:]
    @Published private(set) var forecasts: [String: Date] = [:]
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var problem: String?

    private let engine: TrackerEngine?
    private let sample: SampleUsage?
    private var cursorExports: [UUID: Date] = [:]

    init() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Switchr/usage.sqlite")
        sample = nil
        do {
            engine = try TrackerEngine(url: url)
        } catch {
            engine = nil
            problem = error.localizedDescription
        }
        Task { await loadBudgets() }
    }

    /// Sample data for screenshots. Touches no files.
    init(preview store: AccountStore) {
        engine = nil
        let sample = SampleUsage(store: store)
        self.sample = sample
        today = sample.today
        budgets = sample.budgets
        budgetSpend = sample.budgetSpend
        forecasts = sample.forecasts
        lastUpdate = Date().addingTimeInterval(-120)
    }

    static func forecastKey(_ account: UUID, _ label: String) -> String { "\(account.uuidString)|\(label)" }

    func budget(for scope: String) -> Budget? { budgets.first { $0.scope == scope } }

    // MARK: Updating

    func noteActive(_ provider: Provider, _ account: UUID?) {
        guard let engine else { return }
        Task { try? await engine.noteActive(provider, account: account, at: Date()) }
    }

    func refresh(store: AccountStore) async {
        guard let engine, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let now = Date()
        let accounts = store.accounts
        let usage = store.usage
        let sole = store.soleAccounts
        do {
            for provider in Provider.allCases {
                try await engine.noteActive(provider, account: store.active[provider], at: now)
            }
            try await engine.ingestLocalLogs()

            // Cursor keeps no local logs, so each account's own usage export fills in, at most twice an hour.
            for account in accounts where account.provider == .cursor {
                if let last = cursorExports[account.id], now.timeIntervalSince(last) < 30 * 60 { continue }
                guard let secret = await store.secret(for: account.id),
                      let records = try? await CursorAdapter().usageExport(secret, account: account.id) else { continue }
                try await engine.store(records)
                cursorExports[account.id] = now
            }

            var forecasts: [String: Date] = [:]
            for account in accounts {
                guard let snapshot = usage[account.id], snapshot.error == nil, let fetchedAt = snapshot.fetchedAt else { continue }
                try await engine.addSamples(account: account.id, windows: snapshot.windows, at: fetchedAt)
                for window in snapshot.windows {
                    if let eta = try await engine.forecast(account: account.id, window: window, now: now) {
                        forecasts[Self.forecastKey(account.id, window.label)] = eta
                    }
                }
            }
            self.forecasts = forecasts

            budgets = try await engine.budgets()
            today = try await engine.accountTotals(in: BudgetPeriod.day.interval(containing: now), sole: sole).byAccount
            budgetSpend = try await spend(for: budgets, now: now, sole: sole)
            lastUpdate = now
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        revision += 1
        raiseAlerts(store: store, now: now)
    }

    private func loadBudgets() async {
        guard let engine else { return }
        budgets = (try? await engine.budgets()) ?? []
    }

    private func spend(for budgets: [Budget], now: Date, sole: [Provider: UUID]) async throws -> [String: Double] {
        guard let engine else { return [:] }
        var spend: [String: Double] = [:]
        for period in Set(budgets.map(\.period)) {
            let totals = try await engine.accountTotals(in: period.interval(containing: now), sole: sole)
            for budget in budgets where budget.period == period {
                spend[budget.scope] = budget.account.map { totals.byAccount[$0]?.cost ?? 0 } ?? totals.all.cost
            }
        }
        return spend
    }

    // MARK: Budgets

    func setBudget(_ budget: Budget?, scope: String) {
        budgets.removeAll { $0.scope == scope }
        if let budget { budgets.append(budget) }
        guard let engine else { return }
        Task {
            try? await engine.setBudget(budget, scope: scope)
            if let spend = try? await spend(for: budgets, now: Date(), sole: AccountStore.shared.soleAccounts) {
                budgetSpend = spend
            }
            revision += 1
        }
    }

    // MARK: Insights

    func digest(range: InsightsRange, provider: Provider?, sole: [Provider: UUID]) async -> UsageDigest {
        if let sample { return sample.digest(range: range, provider: provider) }
        guard let engine else { return UsageDigest() }
        let interval = range.interval(now: Date())
        let previous = DateInterval(start: interval.start.addingTimeInterval(-interval.duration), duration: interval.duration)
        do {
            return try await engine.digest(interval: interval, previous: previous, bucket: range.bucket, provider: provider, sole: sole)
        } catch {
            problem = error.localizedDescription
            return UsageDigest()
        }
    }

    // MARK: Alerts

    private func raiseAlerts(store: AccountStore, now: Date) {
        for (provider, id) in store.active {
            guard let account = store.accounts.first(where: { $0.id == id }), let snapshot = store.usage[id], snapshot.error == nil else { continue }
            for window in snapshot.windows {
                let eta = forecasts[Self.forecastKey(id, window.label)]
                let nearlyOut = window.usedPercent >= 90
                guard nearlyOut || eta != nil else { continue }

                let alternative = store.accounts
                    .filter { $0.provider == provider && $0.id != id }
                    .compactMap { other -> (Account, Double)? in
                        guard let used = store.usage[other.id]?.windows.first(where: { $0.label == window.label })?.usedPercent, used < 80 else { return nil }
                        return (other, used)
                    }
                    .min { $0.1 < $1.1 }

                let title = nearlyOut
                    ? "\(provider.name) \(window.label.lowercased()) limit at \(Int(window.usedPercent.rounded()))%"
                    : "\(provider.name) \(window.label.lowercased()) limit runs out around \(eta!.formatted(date: .omitted, time: .shortened))"
                let body = alternative.map { "\(account.displayName) is close to its limit. \($0.0.displayName) has \(Int((100 - $0.1).rounded()))% left." }
                    ?? "\(account.displayName) is close to its limit, and no other saved \(provider.name) account has room."
                let windowID = window.resetsAt.map { String(Int($0.timeIntervalSince1970 / 3600)) } ?? "open"
                Alerts.shared.post(key: "limit:\(id.uuidString):\(window.label):\(windowID):\(nearlyOut ? "90" : "pace")",
                                   title: title, body: body, switchTo: alternative?.0.id)
            }
        }

        for budget in budgets where budget.amount > 0 {
            let spent = budgetSpend[budget.scope] ?? 0
            let share = spent / budget.amount
            guard let threshold = [1.0, 0.8].first(where: { share >= $0 }) else { continue }
            let name = budget.account.flatMap { id in store.accounts.first { $0.id == id }?.displayName } ?? "All accounts"
            let periodStart = Int(budget.period.interval(containing: now).start.timeIntervalSince1970)
            Alerts.shared.post(
                key: "budget:\(budget.scope):\(periodStart):\(Int(threshold * 100))",
                title: threshold >= 1 ? "\(name) is over its \(budget.period.adjective) budget" : "\(name) used 80% of its \(budget.period.adjective) budget",
                body: "\(Numbers.usd(spent)) of \(Numbers.usd(budget.amount)) at API prices."
            )
        }
    }
}

enum InsightsRange: String, CaseIterable, Identifiable {
    case today, week, month, thirtyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "This month"
        case .thirtyDays: "30 days"
        }
    }

    var bucket: Bucket { self == .today ? .hour : .day }

    func interval(now: Date) -> DateInterval {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        switch self {
        case .today:
            return DateInterval(start: startOfToday, end: endOfToday)
        case .week:
            return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: startOfToday)!, end: endOfToday)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: startOfToday, end: endOfToday)
        case .thirtyDays:
            return DateInterval(start: calendar.date(byAdding: .day, value: -29, to: startOfToday)!, end: endOfToday)
        }
    }
}

/// Deterministic sample usage for `--snapshot` and `--preview-insights`.
struct SampleUsage {
    let store: AccountStore
    let today: [UUID: Totals]
    let budgets: [Budget]
    let budgetSpend: [String: Double]
    let forecasts: [String: Date]

    @MainActor
    init(store: AccountStore) {
        self.store = store
        let accounts = store.accounts
        var today: [UUID: Totals] = [:]
        for (i, account) in accounts.enumerated() {
            let tokens = [4_200_000, 1_900_000, 2_600_000, 0, 3_100_000][i % 5]
            guard tokens > 0 else { continue }
            today[account.id] = Totals(tokens: TokenCounts(input: tokens / 20, cacheRead: tokens * 3 / 4, output: tokens / 5),
                                       cost: Double(tokens) / 1_000_000 * [3.1, 2.4, 1.2, 0, 1.6][i % 5], requests: tokens / 9000)
        }
        self.today = today
        var budgets = [Budget(scope: Budget.everything, amount: 600, period: .month)]
        var spend = [Budget.everything: 412.6]
        if let first = accounts.first {
            budgets.append(Budget(scope: Budget.scope(for: first.id), amount: 50, period: .week))
            spend[Budget.scope(for: first.id)] = 21.4
        }
        self.budgets = budgets
        budgetSpend = spend
        var forecasts: [String: Date] = [:]
        if accounts.count > 1 {
            forecasts[UsageTracker.forecastKey(accounts[1].id, "5h")] = Date().addingTimeInterval(26 * 60)
        }
        self.forecasts = forecasts
    }

    @MainActor
    func digest(range: InsightsRange, provider: Provider?) -> UsageDigest {
        var digest = UsageDigest()
        let interval = range.interval(now: Date())
        let step: TimeInterval = range.bucket == .hour ? 3600 : 86400
        let accounts = store.accounts.filter { provider == nil || $0.provider == provider }
        let models = ["claude-opus-5", "gpt-5.6-sol", "composer-2", "claude-sonnet-5", "claude-haiku-4-5"]
        var start = interval.start
        var index = 0.0
        while start < min(interval.end, Date()) {
            for (i, account) in accounts.enumerated() {
                let hourOfDay = Double(Calendar.current.component(.hour, from: start))
                let daily = range.bucket == .hour ? max(0, sin((hourOfDay - 7) / 14 * .pi)) : 1
                let wave = 0.55 + 0.45 * sin(index * 0.9 + Double(i) * 1.7)
                let tokens = Int(Double([2_600_000, 1_300_000, 1_900_000, 600_000, 2_200_000][i % 5]) * wave * daily * (range.bucket == .hour ? 0.12 : 1))
                guard tokens > 0 else { continue }
                let cost = Double(tokens) / 1_000_000 * [2.9, 2.2, 1.1, 0.8, 1.5][i % 5]
                let totals = Totals(tokens: TokenCounts(input: tokens / 20, cacheRead: tokens * 3 / 4, output: tokens / 5), cost: cost,
                                    billed: account.provider == .cursor ? cost * 0.08 : 0, requests: tokens / 9000)
                let key = AccountKey(provider: account.provider, account: account.id)
                digest.points.append(UsageDigest.Point(start: start, key: key, totals: totals))
                digest.byAccount[key, default: Totals()] += totals
                digest.total += totals
                let modelIndex = account.provider == .claude ? (Int(index) % 5 == 0 ? 3 : 0) : account.provider == .codex ? 1 : 2
                digest.byModel[models[modelIndex], default: Totals()] += totals
            }
            start = start.addingTimeInterval(step)
            index += 1
        }
        if accounts.contains(where: { $0.provider == .claude }) {
            let haiku = Totals(tokens: TokenCounts(input: 40_000, cacheRead: 300_000, output: 60_000), cost: 0.6, requests: 80)
            digest.byModel[models[4], default: Totals()] += haiku
        }
        digest.previous = Totals(tokens: TokenCounts(output: Int(Double(digest.total.tokens.total) * 0.86)), cost: digest.total.cost * 0.88)
        return digest
    }
}
