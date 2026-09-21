import Foundation

// MARK: JSON documents
//
// The Linux tray and Insights window read these. Field names are part of that contract: add
// fields freely, but rename or remove one only together with linux/keyhop_common.py.

struct SpendDocument: Encodable {
    let tokens: Int
    let cost: Double
    let billed: Double
    let requests: Int

    init(_ totals: Totals) {
        tokens = totals.tokens.total
        cost = totals.cost
        billed = totals.billed
        requests = totals.requests
    }
}

struct BudgetDocument: Encodable {
    let scope: String
    let name: String
    let amount: Double
    let period: String
    let spent: Double

    init(_ budget: Budget, spent: Double, accounts: [Account]) {
        scope = budget.scope
        name = budget.account.flatMap { id in accounts.first { $0.id == id }?.displayName } ?? "All accounts"
        amount = budget.amount
        period = budget.period.rawValue
        self.spent = spent
    }
}

struct StatusDocument: Encodable {
    let version: String
    let platform: String
    let refreshedAt: Date?
    let secretStore: String
    let today: SpendDocument
    let tools: [Tool]
    let budgets: [BudgetDocument]
    let recommendations: [AccountRecommendation]
    let alerts: [AlertCandidate]
    let notices: [String]

    struct Tool: Encodable {
        let id: String
        let name: String
        let switchNote: String?
        let limitsNote: String?
        let signInHint: String
        let activeAccount: UUID?
        let accounts: [AccountEntry]
    }

    struct AccountEntry: Encodable {
        let id: UUID
        let email: String
        let label: String?
        let name: String
        let plan: String?
        let active: Bool
        let limits: [Limit]
        let limitsReadAt: Date?
        let error: String?
        /// Room left on the tightest limit, in percent.
        let room: Double?
        let today: SpendDocument?
        let budget: BudgetDocument?
    }

    struct Limit: Encodable {
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
        let runsOutAt: Date?
        let pace: Double?
    }

    init(_ overview: Overview) {
        let now = Date()
        version = AppVersion.current
        platform = Platform.name
        refreshedAt = overview.refreshedAt
        secretStore = overview.secretStore
        today = SpendDocument(overview.todayAll)
        alerts = overview.alerts
        notices = overview.notices
        budgets = overview.budgets.map { BudgetDocument($0, spent: overview.budgetSpend[$0.scope] ?? 0, accounts: overview.accounts) }
        recommendations = SmartHop.recommendations(
            accounts: overview.accounts,
            active: overview.active,
            usage: overview.usage,
            forecasts: overview.forecasts,
            budgets: overview.budgets,
            budgetSpend: overview.budgetSpend,
            now: now
        )
        tools = Provider.allCases.map { provider in
            Tool(
                id: provider.rawValue,
                name: provider.name,
                switchNote: provider.switchNote.map(Output.plain),
                limitsNote: provider.limitsNote,
                signInHint: Output.plain(provider.signInHint),
                activeAccount: overview.active[provider],
                accounts: overview.accounts.filter { $0.provider == provider }.map { account in
                    let snapshot = overview.usage[account.id]
                    let windows = snapshot?.windows ?? []
                    let scope = Budget.scope(for: account.id)
                    return AccountEntry(
                        id: account.id,
                        email: account.email,
                        label: account.label,
                        name: account.displayName,
                        plan: account.plan,
                        active: overview.active[provider] == account.id,
                        limits: windows.map { window in
                            Limit(label: window.label, usedPercent: window.usedPercent, resetsAt: window.resetsAt,
                                  runsOutAt: overview.forecasts[AlertRules.forecastKey(account.id, window.label)],
                                  pace: window.pace(at: now))
                        },
                        limitsReadAt: snapshot?.fetchedAt,
                        error: snapshot?.error,
                        room: windows.map { 100 - $0.usedPercent }.min(),
                        today: overview.today[account.id].map(SpendDocument.init),
                        budget: overview.budgets.first { $0.scope == scope }.map {
                            BudgetDocument($0, spent: overview.budgetSpend[scope] ?? 0, accounts: overview.accounts)
                        }
                    )
                }
            )
        }
    }
}

struct RecommendationListDocument: Encodable {
    let version = AppVersion.current
    let generatedAt: Date
    let recommendations: [AccountRecommendation]

    init(_ overview: Overview, provider: Provider? = nil, now: Date = Date()) {
        generatedAt = now
        recommendations = SmartHop.recommendations(
            accounts: overview.accounts,
            active: overview.active,
            usage: overview.usage,
            forecasts: overview.forecasts,
            budgets: overview.budgets,
            budgetSpend: overview.budgetSpend,
            now: now
        ).filter { provider == nil || $0.tool == provider?.rawValue }
    }
}

struct ActionResult: Encodable {
    let ok: Bool
    let message: String
    let account: UUID?
    let note: String?
}

struct UpdateDocument: Encodable {
    let current: String
    let latest: String
    let available: Bool
    let page: URL
}

struct UsageDocument: Encodable {
    let range: String
    let title: String
    let bucket: String
    let start: Date
    let end: Date
    let total: SpendDocument
    let previous: SpendDocument
    let accounts: [AccountUsage]
    let tools: [ToolUsage]
    let models: [ModelUsage]
    let projects: [ProjectUsage]
    let sessions: [SessionUsage]
    let points: [Point]
    let budgets: [BudgetDocument]

    /// A repository or folder, by where it is on this computer and the short name it goes by.
    /// Usage no tool placed in a folder has neither.
    struct ProjectUsage: Encodable {
        let path: String?
        let name: String
        let spend: SpendDocument
    }

    struct AccountUsage: Encodable {
        let id: UUID?
        let tool: String
        let name: String
        let email: String?
        let plan: String?
        let spend: SpendDocument
    }

    struct ToolUsage: Encodable {
        let tool: String
        let name: String
        let spend: SpendDocument
    }

    struct ModelUsage: Encodable {
        let model: String
        let tool: String
        let spend: SpendDocument
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
        let cacheWrite1h: Int
        let reasoning: Int
    }

    struct SessionUsage: Encodable {
        let id: String
        let tool: String
        let account: UUID?
        let model: String
        let from: Date
        let to: Date
        let spend: SpendDocument
    }

    struct Point: Encodable {
        let start: Date
        let account: UUID?
        let tool: String
        let model: String
        let tokens: Int
        let cost: Double
    }

    init(range: InsightsRange, now: Date, digest: UsageDigest, accounts: [Account], budgets: [Budget], spend: [String: Double]) {
        let interval = range.interval(now: now)
        self.range = range.argument
        title = range.title
        bucket = range.bucket == .hour ? "hour" : "day"
        start = interval.start
        end = interval.end
        total = SpendDocument(digest.total)
        previous = SpendDocument(digest.previous)
        self.accounts = digest.byAccount
            .sorted { $0.value.tokens.total > $1.value.tokens.total }
            .map { key, totals in
                let account = key.account.flatMap { id in accounts.first { $0.id == id } }
                return AccountUsage(id: key.account, tool: key.provider.rawValue, name: account?.displayName ?? "Earlier or removed",
                                    email: account?.email, plan: account?.plan, spend: SpendDocument(totals))
            }
        tools = digest.byProvider
            .sorted { $0.value.tokens.total > $1.value.tokens.total }
            .map { ToolUsage(tool: $0.key.rawValue, name: $0.key.name, spend: SpendDocument($0.value)) }
        models = digest.byModel
            .sorted { $0.value.tokens.total > $1.value.tokens.total }
            .map { key, totals in
                ModelUsage(model: key.model, tool: key.provider.rawValue, spend: SpendDocument(totals),
                           input: totals.tokens.input, output: totals.tokens.output, cacheRead: totals.tokens.cacheRead,
                           cacheWrite: totals.tokens.cacheWrite, cacheWrite1h: totals.tokens.cacheWrite1h,
                           reasoning: totals.tokens.reasoning)
            }
        projects = Reports.projects(digest).map { path, name, totals in
            ProjectUsage(path: path, name: name, spend: SpendDocument(totals))
        }
        sessions = digest.sessions.map {
            SessionUsage(id: $0.id, tool: $0.provider.rawValue, account: $0.account, model: $0.model,
                         from: $0.from, to: $0.to, spend: SpendDocument($0.totals))
        }
        points = digest.points.map {
            Point(start: $0.start, account: $0.key.account, tool: $0.key.provider.rawValue, model: $0.model,
                  tokens: $0.totals.tokens.total, cost: $0.totals.cost)
        }
        self.budgets = budgets.map { BudgetDocument($0, spent: spend[$0.scope] ?? 0, accounts: accounts) }
    }
}

struct DoctorDocument: Encodable {
    let version: String
    let platform: String
    let dataDirectory: String
    let secretStore: String
    let savedAccounts: Int
    let tools: [Tool]
    let trayInstalled: Bool
    let statusNotifierHost: Bool?

    struct Tool: Encodable {
        let id: String
        let name: String
        let installed: Bool
        let signedInAs: String?
        let problem: String?
        let loginLocation: String
    }
}

// MARK: Terminal output

enum Reports {
    static func recommendations(_ document: RecommendationListDocument) -> String {
        guard !document.recommendations.isEmpty else {
            return "No recommendation yet. Run `keyhop refresh` after saving an account so Keyhop can read its limits."
        }
        return document.recommendations.map { recommendation in
            let state = recommendation.active ? "already in use" : "switch available"
            return "\(Provider(rawValue: recommendation.tool)?.name ?? recommendation.tool): \(recommendation.name) (\(state))\n  \(recommendation.reason)"
        }.joined(separator: "\n")
    }

    static func status(_ overview: Overview) -> String {
        var lines = overview.notices
        guard !overview.accounts.isEmpty else {
            lines.append("No saved accounts yet. Sign in to a supported AI tool, then run `keyhop refresh`.")
            return lines.joined(separator: "\n")
        }
        let now = Date()
        for provider in Provider.allCases {
            let accounts = overview.accounts.filter { $0.provider == provider }
            guard !accounts.isEmpty else { continue }
            if !lines.isEmpty { lines.append("") }
            lines.append(provider.name)
            for account in accounts {
                let inUse = overview.active[provider] == account.id
                var head = "  \(inUse ? "*" : " ") \(account.displayName)"
                if account.label != nil { head += " <\(account.email)>" }
                if let plan = account.plan { head += "  \(plan)" }
                if inUse { head += "  (in use)" }
                lines.append(head)

                let snapshot = overview.usage[account.id]
                for window in snapshot?.windows ?? [] {
                    let percent = String(format: "%3d%%", Int(window.usedPercent.rounded()))
                    var line = "      \(window.label.padding(toLength: 6, withPad: " ", startingAt: 0)) \(percent)  \(bar(window.usedPercent))"
                    if inUse, let eta = overview.forecasts[AlertRules.forecastKey(account.id, window.label)], eta > now {
                        line += "  runs out around \(eta.formatted(date: .omitted, time: .shortened))"
                    } else if window.resetsAt != nil {
                        line += "  resets in \(window.resetText(at: now))"
                    }
                    lines.append(line)
                }
                if let error = snapshot?.error { lines.append("      \(error)") }
                if snapshot?.windows.isEmpty == true, let note = provider.limitsNote { lines.append("      \(note)") }
                if snapshot == nil { lines.append("      Limits not read yet.") }
                if let today = overview.today[account.id], today.requests > 0 {
                    lines.append("      Today  \(Numbers.tokens(today.tokens.total)) tokens, \(Numbers.usd(today.cost)) at API prices")
                }
            }
        }

        lines.append("")
        if overview.todayAll.requests > 0 {
            lines.append("Today across accounts: \(Numbers.tokens(overview.todayAll.tokens.total)) tokens, \(Numbers.usd(overview.todayAll.cost)) at API prices.")
        }
        for budget in overview.budgets {
            let document = BudgetDocument(budget, spent: overview.budgetSpend[budget.scope] ?? 0, accounts: overview.accounts)
            lines.append("Budget, \(document.name): \(Numbers.usd(document.spent)) of \(Numbers.usd(document.amount)) per \(document.period).")
        }
        for alert in overview.alerts {
            lines.append("! \(alert.title). \(alert.body)")
        }
        if let refreshedAt = overview.refreshedAt {
            lines.append("Limits read \(Output.relative(refreshedAt, now: now)). Run `keyhop refresh` to read them again.")
        } else {
            lines.append("Limits haven't been read yet. Run `keyhop refresh`.")
        }
        return lines.joined(separator: "\n")
    }

    static func usage(range: InsightsRange, digest: UsageDigest, accounts: [Account]) -> String {
        var lines: [String] = []
        var headline = "\(range.title): \(Numbers.tokens(digest.total.tokens.total)) tokens, \(Numbers.usd(digest.total.cost)) at API prices"
        let before = Double(digest.previous.tokens.total)
        if before > 0 {
            let change = Int(((Double(digest.total.tokens.total) - before) / before * 100).rounded())
            headline += change == 0 ? " (same as the period before)" : " (\(abs(change))% \(change > 0 ? "more" : "fewer") tokens than the period before)"
        }
        lines.append(headline)
        if digest.total.billed > 0 { lines.append("Billed on demand: \(Numbers.usd(digest.total.billed))") }
        guard digest.total.requests > 0 else {
            lines.append("No usage in this range yet.")
            return lines.joined(separator: "\n")
        }

        lines.append("")
        lines.append("Tools")
        for (provider, totals) in digest.byProvider.sorted(by: { $0.value.tokens.total > $1.value.tokens.total }) {
            lines.append("  \(provider.name.padding(toLength: 38, withPad: " ", startingAt: 0)) \(Numbers.tokens(totals.tokens.total).leftPadded(8))  \(Numbers.usd(totals.cost).leftPadded(9))")
        }
        lines.append("")
        lines.append("Accounts")
        for (key, totals) in digest.byAccount.sorted(by: { $0.value.tokens.total > $1.value.tokens.total }) {
            let account = key.account.flatMap { id in accounts.first { $0.id == id } }
            let name = "\(key.provider.name) · \(account?.displayName ?? "earlier or removed")"
            lines.append("  \(name.padding(toLength: 38, withPad: " ", startingAt: 0)) \(Numbers.tokens(totals.tokens.total).leftPadded(8))  \(Numbers.usd(totals.cost).leftPadded(9))")
        }
        lines.append("")
        lines.append("Models")
        for (key, totals) in digest.byModel.sorted(by: { $0.value.tokens.total > $1.value.tokens.total }) {
            let name = "\(key.model) · \(key.provider.shortName)"
            lines.append("  \(name.padding(toLength: 38, withPad: " ", startingAt: 0)) \(Numbers.tokens(totals.tokens.total).leftPadded(8))  \(Numbers.usd(totals.cost).leftPadded(9))")
        }
        let projects = Self.projects(digest)
        if projects.contains(where: { $0.path != nil }) {
            lines.append("")
            lines.append("Projects")
            for (_, name, totals) in projects.prefix(12) {
                lines.append("  \(name.padding(toLength: 38, withPad: " ", startingAt: 0)) \(Numbers.tokens(totals.tokens.total).leftPadded(8))  \(Numbers.usd(totals.cost).leftPadded(9))")
            }
            if projects.count > 12 { lines.append("  and \(projects.count - 12) more") }
        }
        return lines.joined(separator: "\n")
    }

    /// Projects, most used first, each with the short name it goes by. Usage no tool placed in a
    /// folder comes last whatever its size, because it isn't a project.
    static func projects(_ digest: UsageDigest) -> [(path: String?, name: String, totals: Totals)] {
        let names = Projects.names(for: digest.byProject.keys.filter { !$0.isEmpty })
        let placed = digest.byProject
            .filter { !$0.key.isEmpty }
            .sorted { $0.value.tokens.total > $1.value.tokens.total }
            .map { (path: Optional($0.key), name: names[$0.key] ?? $0.key, totals: $0.value) }
        let unplaced = digest.byProject[""].map { [(path: String?.none, name: "No folder recorded", totals: $0)] } ?? []
        return placed + unplaced
    }

    static func doctor(_ document: DoctorDocument) -> String {
        var lines = [
            "Keyhop \(document.version) on \(document.platform)",
            "Data:          \(document.dataDirectory)",
            "Saved logins:  \(document.savedAccounts) in \(document.secretStore)",
        ]
        for tool in document.tools {
            let state: String
            if let email = tool.signedInAs {
                state = "signed in as \(email)"
            } else if let problem = tool.problem {
                state = problem
            } else {
                state = tool.installed ? "signed out" : "not found"
            }
            lines.append("\(tool.name + ":")\(String(repeating: " ", count: max(1, 15 - tool.name.count - 1)))\(state)  [\(tool.loginLocation)]")
        }
        if let host = document.statusNotifierHost {
            lines.append("Tray:          \(document.trayInstalled ? "keyhop-tray installed" : "keyhop-tray not installed"), "
                + (host ? "the desktop shows tray icons" : "no tray host; on GNOME enable the AppIndicator extension"))
        }
        return lines.joined(separator: "\n")
    }

    /// A 20-cell bar, so limits read at a glance in a terminal.
    static func bar(_ percent: Double) -> String {
        let filled = Int((min(max(percent, 0), 100) / 100 * 20).rounded())
        return String(repeating: "█", count: filled) + String(repeating: "░", count: 20 - filled)
    }
}

private extension String {
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
