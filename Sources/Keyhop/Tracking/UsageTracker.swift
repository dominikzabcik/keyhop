#if os(macOS)
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
        let url = Platform.dataDirectory.appendingPathComponent("usage.sqlite")
        sample = nil
        do {
            engine = try TrackerEngine(url: url)
            // Usage history is personal: only you can read the folder and the database.
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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

    static func forecastKey(_ account: UUID, _ label: String) -> String { AlertRules.forecastKey(account, label) }

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
            defer { store.progress.set(nil) }
            // New prices first, so the logs read next are priced with them.
            await engine.refreshPrices(now: now)
            try await engine.ingestLocalLogs(progress: store.progress.handler)

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
            budgetSpend = try await engine.budgetSpend(for: budgets, now: now, sole: sole)
            lastUpdate = now
            problem = nil
            await CloudSync.syncIfDue(tracker: engine, accounts: accounts, usage: usage, now: now)
        } catch {
            problem = error.localizedDescription
        }
        revision += 1

        let alerts = AlertRules.evaluate(accounts: store.accounts, active: store.active, usage: store.usage, forecasts: forecasts,
                                         budgets: budgets, budgetSpend: budgetSpend, now: now)
        for alert in alerts {
            Alerts.shared.post(key: alert.key, title: alert.title, body: alert.body, switchTo: alert.switchTo)
        }
    }

    private func loadBudgets() async {
        guard let engine else { return }
        budgets = (try? await engine.budgets()) ?? []
    }

    // MARK: Budgets

    func setBudget(_ budget: Budget?, scope: String) {
        budgets.removeAll { $0.scope == scope }
        if let budget { budgets.append(budget) }
        guard let engine else { return }
        Task {
            try? await engine.setBudget(budget, scope: scope)
            if let spend = try? await engine.budgetSpend(for: budgets, now: Date(), sole: AccountStore.shared.soleAccounts) {
                budgetSpend = spend
            }
            revision += 1
        }
    }

    // MARK: Insights

    func digest(range: InsightsRange, provider: Provider?, sole: [Provider: UUID]) async -> UsageDigest {
        if let sample { return sample.digest(range: range, provider: provider) }
        guard let engine else { return UsageDigest() }
        let now = Date()
        do {
            return try await engine.digest(interval: range.interval(now: now), previous: range.previous(now: now),
                                           bucket: range.bucket, provider: provider, sole: sole)
        } catch {
            problem = error.localizedDescription
            return UsageDigest()
        }
    }
}

/// Deterministic sample usage for previews.
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
            let tokens = [4_200_000, 1_900_000, 2_600_000, 0, 3_100_000, 2_300_000][i % 6]
            guard tokens > 0 else { continue }
            today[account.id] = Totals(tokens: TokenCounts(input: tokens / 20, cacheRead: tokens * 3 / 4, output: tokens / 5),
                                       cost: Double(tokens) / 1_000_000 * [3.1, 2.4, 1.2, 0, 1.6, 2.0][i % 6], requests: tokens / 9000)
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
            forecasts[AlertRules.forecastKey(accounts[1].id, "5h")] = Date().addingTimeInterval(26 * 60)
        }
        self.forecasts = forecasts
    }

    @MainActor
    func digest(range: InsightsRange, provider: Provider?) -> UsageDigest {
        var digest = UsageDigest()
        let interval = range.interval(now: Date())
        let step: TimeInterval = range.bucket == .hour ? 3600 : 86400
        let accounts = store.accounts.filter { provider == nil || $0.provider == provider }
        let models = ["claude-opus-5", "gpt-5.6-sol", "composer-2", "claude-sonnet-5", "claude-haiku-4-5", "gemini-3.1-pro-preview"]
        var start = interval.start
        var index = 0.0
        while start < min(interval.end, Date()) {
            for (i, account) in accounts.enumerated() {
                let hourOfDay = Double(Calendar.current.component(.hour, from: start))
                let daily = range.bucket == .hour ? max(0, sin((hourOfDay - 7) / 14 * .pi)) : 1
                let wave = 0.55 + 0.45 * sin(index * 0.9 + Double(i) * 1.7)
                let tokens = Int(Double([2_600_000, 1_300_000, 1_900_000, 600_000, 2_200_000, 1_700_000][i % 6]) * wave * daily * (range.bucket == .hour ? 0.12 : 1))
                guard tokens > 0 else { continue }
                let cost = Double(tokens) / 1_000_000 * [2.9, 2.2, 1.1, 0.8, 1.5, 2.0][i % 6]
                let totals = Totals(tokens: TokenCounts(input: tokens / 20, cacheRead: tokens * 3 / 4, output: tokens / 5), cost: cost,
                                    billed: account.provider == .cursor ? cost * 0.08 : 0, requests: tokens / 9000)
                let key = AccountKey(provider: account.provider, account: account.id)
                let modelIndex = account.provider == .claude ? (Int(index) % 5 == 0 ? 3 : 0) : account.provider == .codex ? 1 : account.provider == .gemini ? 5 : 2
                let modelName = models[modelIndex]
                digest.points.append(UsageDigest.Point(start: start, key: key, model: modelName, totals: totals))
                digest.byAccount[key, default: Totals()] += totals
                digest.byModel[ModelKey(provider: account.provider, model: modelName), default: Totals()] += totals
                digest.byProvider[account.provider, default: Totals()] += totals
                digest.total += totals
            }
            start = start.addingTimeInterval(step)
            index += 1
        }
        if accounts.contains(where: { $0.provider == .claude }) {
            let haiku = Totals(tokens: TokenCounts(input: 40_000, cacheRead: 300_000, output: 60_000), cost: 0.6, requests: 80)
            digest.byModel[ModelKey(provider: .claude, model: models[4]), default: Totals()] += haiku
        }
        digest.previous = Totals(tokens: TokenCounts(output: Int(Double(digest.total.tokens.total) * 0.86)), cost: digest.total.cost * 0.88)
        return digest
    }
}
#endif
