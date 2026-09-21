import Foundation

/// Made-up accounts and usage for screenshots, docs and CI: `keyhop status --sample` and
/// `keyhop insights --sample`. Touches no files, secret stores or network, and never contains a
/// real login.
enum SampleData {
    static func accounts(now: Date = Date()) -> [Account] {
        func account(_ index: Int, _ provider: Provider, _ email: String, _ label: String?, _ plan: String) -> Account {
            Account(id: UUID(uuidString: String(format: "5A3F0000-0000-4000-8000-%012d", index))!, provider: provider,
                    identity: email, email: email, label: label, plan: plan, addedAt: now.addingTimeInterval(-86400 * Double(40 - index)))
        }
        return [
            account(1, .claude, "me@personal.dev", "Personal", "Max 5x"),
            account(2, .claude, "work@studio.dev", nil, "Pro"),
            account(3, .cursor, "me@personal.dev", nil, "Ultra"),
            account(4, .cursor, "spare@personal.dev", nil, "Pro"),
            account(5, .codex, "me@personal.dev", nil, "Plus"),
            account(6, .gemini, "me@personal.dev", nil, "Standard"),
            account(7, .opencode, "profile@opencode.dev", "Multi-provider", "Local"),
            account(8, .pi, "profile@pi.dev", "Multi-provider", "Local"),
            account(9, .copilot, "octocat@github.dev", "Personal", "Pro"),
            account(10, .windsurf, "me@windsurf.dev", nil, "Pro"),
            account(11, .codebuff, "me@codebuff.dev", nil, "Strong"),
        ]
    }

    /// Codex in the middle of a partial outage and the rest working, so the window and the checks
    /// show what trouble looks like.
    static func services(now: Date = Date()) -> [ServiceHealth] {
        ServiceStatus.sorted(ServiceStatus.pages.map { tool, page in
            let trouble = tool == .codex
            return ServiceHealth(
                tool: tool.rawValue, name: page.name, page: page.url, level: trouble ? .partialOutage : .operational,
                incidents: trouble ? [ServiceHealth.Incident(name: "Elevated error rates in Codex CLI", stage: "identified",
                                                             updated: now.addingTimeInterval(-1_140), link: page.url)] : [])
        })
    }

    static func overview(now: Date = Date()) -> Overview {
        let accounts = accounts(now: now)
        let active: [Provider: UUID] = [
            .claude: accounts[0].id, .cursor: accounts[2].id, .codex: accounts[4].id, .gemini: accounts[5].id,
            .opencode: accounts[6].id, .pi: accounts[7].id, .copilot: accounts[8].id, .windsurf: accounts[9].id,
            .codebuff: accounts[10].id,
        ]
        func window(_ label: String, _ used: Double, _ resetIn: TimeInterval, _ length: TimeInterval) -> UsageWindow {
            UsageWindow(label: label, usedPercent: used, resetsAt: now.addingTimeInterval(resetIn), windowSeconds: length)
        }
        let read = now.addingTimeInterval(-120)
        let usage: [UUID: UsageSnapshot] = [
            accounts[0].id: UsageSnapshot(windows: [window("5h", 51, 11_160, 18000), window("Week", 6, 590_000, 604_800)], fetchedAt: read),
            accounts[1].id: UsageSnapshot(windows: [window("5h", 12, 2_400, 18000), window("Week", 41, 300_000, 604_800)], fetchedAt: read),
            accounts[2].id: UsageSnapshot(windows: [window("Auto", 62, 1_140_000, 2_592_000), window("API", 39, 1_140_000, 2_592_000)], fetchedAt: read),
            accounts[3].id: UsageSnapshot(error: "Login expired. Switch to it and sign in to Cursor again."),
            accounts[4].id: UsageSnapshot(windows: [window("5h", 93, 6_440, 18000), window("Week", 62, 421_000, 604_800)], fetchedAt: read),
            accounts[5].id: UsageSnapshot(windows: [window("Quota", 28, 51_400, 86400)], fetchedAt: read),
            accounts[8].id: UsageSnapshot(windows: [window("Premium", 47, 1_140_000, 2_592_000)], fetchedAt: read),
            accounts[9].id: UsageSnapshot(windows: [window("Day", 33, 51_400, 86400), window("Week", 18, 421_000, 604_800)], fetchedAt: read),
            accounts[10].id: UsageSnapshot(windows: [window("Credits", 25, 1_140_000, 2_592_000), window("Week", 30, 421_000, 604_800)], fetchedAt: read),
        ]

        var today: [UUID: Totals] = [:]
        var todayAll = Totals()
        for (index, account) in accounts.enumerated() {
            let tokens = [4_200_000, 1_900_000, 2_600_000, 0, 3_100_000, 2_300_000, 1_700_000, 1_400_000, 0, 0, 0][index]
            guard tokens > 0 else { continue }
            let totals = Totals(tokens: TokenCounts(input: tokens / 20, cacheRead: tokens * 3 / 4, output: tokens / 5),
                                cost: Double(tokens) / 1_000_000 * [3.1, 2.4, 1.2, 0, 1.6, 2.0, 1.7, 2.2, 0, 0, 0][index],
                                requests: tokens / 9000)
            today[account.id] = totals
            todayAll += totals
        }

        // Budget spend comes from the same sample usage the charts show, so the numbers agree.
        let monthCost = digest(range: .month, accounts: accounts, now: now).total.cost
        let personalWeek = digest(range: .week, accounts: [accounts[0]], now: now).total.cost
        let budgets = [
            Budget(scope: Budget.everything, amount: 250, period: .month),
            Budget(scope: Budget.scope(for: accounts[0].id), amount: 60, period: .week),
        ]
        let spend = [Budget.everything: monthCost, Budget.scope(for: accounts[0].id): personalWeek]
        let forecasts = [AlertRules.forecastKey(accounts[4].id, "5h"): now.addingTimeInterval(26 * 60)]
        return Overview(
            accounts: accounts, active: active, usage: usage, today: today, todayAll: todayAll,
            budgets: budgets, budgetSpend: spend, forecasts: forecasts,
            alerts: AlertRules.evaluate(accounts: accounts, active: active, usage: usage, forecasts: forecasts,
                                        budgets: budgets, budgetSpend: spend, now: now),
            notices: [], refreshedAt: read, secretStore: "sample data"
        )
    }

    static func digest(range: InsightsRange, accounts: [Account], now: Date) -> UsageDigest {
        var digest = digest(interval: range.interval(now: now), bucket: range.bucket, accounts: accounts, now: now)
        if !range.hasPrevious { digest.previous = Totals() }
        return digest
    }

    /// Where each sample tool's work happened: the repositories someone might have on the go, and
    /// Gemini CLI and Cursor, which record no folder, in none.
    private static func sampleProject(_ tool: Provider, _ index: Int) -> String {
        let home = Files.home.path
        switch tool {
        case .gemini, .cursor: return ""
        case .claude: return index % 3 == 0 ? "\(home)/code/atlas" : "\(home)/code/keyhop"
        case .codex: return "\(home)/code/atlas"
        case .opencode, .pi: return "\(home)/code/field-notes"
        case .copilot, .windsurf, .codebuff: return "\(home)/code/keyhop"
        }
    }

    /// Smooth, repeatable usage: a working-day rhythm by the hour, and by the day a weekly wave with
    /// quieter weekends and the odd day off.
    static func digest(interval: DateInterval, bucket: Bucket, accounts: [Account], now: Date) -> UsageDigest {
        var digest = UsageDigest()
        let calendar = Calendar.current
        let component = bucket.component
        let models = ["claude-opus-5", "gpt-5.6-sol", "composer-2", "claude-sonnet-5", "claude-haiku-4-5",
                      "gemini-3.1-pro-preview", "openai/gpt-5.6-sol", "anthropic/claude-sonnet-5"]
        var start = interval.start
        var index = 0.0
        // At least one bucket, so even just after midnight there's something to show.
        let end = min(interval.end, max(now, calendar.date(byAdding: component, value: 1, to: interval.start) ?? now))
        while start < end {
            for (i, account) in accounts.enumerated() {
                // Copilot, Windsurf and Codebuff expose limits, not a complete token ledger.
                guard account.provider != .copilot, account.provider != .windsurf, account.provider != .codebuff else { continue }
                let hour = Double(calendar.component(.hour, from: start))
                let daily: Double
                if bucket == .hour {
                    // A working-day curve with a quiet floor, so night hours aren't empty.
                    daily = max(0.08, sin((hour - 7) / 14 * .pi))
                } else if bucket == .week || bucket == .month {
                    // About five working days a week, twenty-two a month, with a slow drift.
                    daily = (bucket == .week ? 5.2 : 22) * (0.8 + 0.2 * sin(index / 5))
                } else {
                    let weekday = calendar.component(.weekday, from: start)
                    daily = Int(index) % 13 == 5 ? 0 : weekday == 1 ? 0.25 : weekday == 7 ? 0.45 : 1
                }
                let wave = 0.55 + 0.45 * sin(index * 0.9 + Double(i) * 1.7)
                let base = Double([2_600_000, 1_300_000, 1_900_000, 600_000, 2_200_000, 1_700_000][i % 6])
                let tokens = Int(base * wave * daily * (bucket == .hour ? 0.12 : 1))
                guard tokens > 0 else { continue }
                let cost = Double(tokens) / 1_000_000 * [2.9, 2.2, 1.1, 0.8, 1.5, 2.0][i % 6]
                let totals = Totals(tokens: TokenCounts(input: tokens / 20, cacheWrite: tokens / 50, cacheRead: tokens * 3 / 4,
                                                        output: tokens / 5, reasoning: tokens / 30), cost: cost,
                                    billed: account.provider == .cursor ? cost * 0.08 : 0, requests: max(1, tokens / 9000))
                let key = AccountKey(provider: account.provider, account: account.id)
                let model = switch account.provider {
                case .claude: Int(index) % 5 == 0 ? 3 : 0
                case .codex: 1
                case .gemini: 5
                case .opencode: 6
                case .pi: 7
                case .cursor, .copilot, .windsurf, .codebuff: 2
                }
                let name = models[model]
                digest.points.append(UsageDigest.Point(start: start, key: key, model: name, totals: totals))
                digest.byAccount[key, default: Totals()] += totals
                digest.byModel[ModelKey(provider: account.provider, model: name), default: Totals()] += totals
                digest.byProvider[account.provider, default: Totals()] += totals
                digest.byProject[sampleProject(account.provider, Int(index)), default: Totals()] += totals
                digest.total += totals
            }
            guard let next = calendar.date(byAdding: component, value: 1, to: start) else { break }
            start = next
            index += 1
        }
        if digest.total.requests > 0 {
            digest.byModel[ModelKey(provider: .claude, model: models[4]), default: Totals()] +=
                Totals(tokens: TokenCounts(input: 40_000, cacheRead: 300_000, output: 60_000), cost: 0.6, requests: 80)
        }
        digest.previous = Totals(tokens: TokenCounts(output: Int(Double(digest.total.tokens.total) * 0.86)), cost: digest.total.cost * 0.88)
        digest.sessions = sessions(from: digest, now: now)
        return digest
    }

    /// A handful of conversations drawn from the same sample burn, so Usage has a sessions list.
    static func sessions(from digest: UsageDigest, now: Date) -> [UsageDigest.Session] {
        digest.byModel.sorted { $0.value.tokens.total > $1.value.tokens.total }.prefix(8).enumerated().map { index, entry in
            let span = TimeInterval((index + 1) * 1400)
            return UsageDigest.Session(
                id: "sample-\(entry.key.provider.rawValue)-\(index)",
                provider: entry.key.provider,
                account: digest.byAccount.first { $0.key.provider == entry.key.provider }?.key.account,
                model: entry.key.model,
                from: now.addingTimeInterval(-span - 2400),
                to: now.addingTimeInterval(-span),
                totals: entry.value
            )
        }
    }
}
