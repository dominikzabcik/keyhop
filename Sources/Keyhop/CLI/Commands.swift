import Foundation
#if os(macOS)
import ServiceManagement
#endif

/// What the command line remembers between runs, next to accounts.json: the last limits it read,
/// which account each tool used, and which alerts it already raised.
struct CLIState: Codable {
    var usage: [String: UsageSnapshot] = [:]
    var active: [String: String] = [:]
    var refreshedAt: Date?
    var cursorExports: [String: Date] = [:]
    var sentAlerts: [String: Date] = [:]

    static var url: URL { Platform.dataDirectory.appendingPathComponent("cli-state.json") }

    static func load(from file: URL = url) -> CLIState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CLIState.self, from: Data(contentsOf: file))) ?? CLIState()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? Files.writeAtomically(data, to: Self.url)
    }

    var usageByID: [UUID: UsageSnapshot] {
        Dictionary(uniqueKeysWithValues: usage.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }

    var activeByTool: [Provider: UUID] {
        Dictionary(uniqueKeysWithValues: active.compactMap { key, value in
            guard let provider = Provider(rawValue: key), let id = UUID(uuidString: value) else { return nil }
            return (provider, id)
        })
    }
}

/// Everything a command works with, opened once per run.
struct Workspace {
    let service: AccountService
    let tracker: TrackerEngine
    var state: CLIState

    static func open() throws -> Workspace {
        let directory = Platform.dataDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let database = directory.appendingPathComponent("usage.sqlite")
        let tracker = try TrackerEngine(url: database)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.path)
        return Workspace(service: AccountService(directory: directory), tracker: tracker, state: CLIState.load())
    }
}

/// Everything `status` and `refresh` report.
struct Overview {
    var accounts: [Account]
    var active: [Provider: UUID]
    var usage: [UUID: UsageSnapshot]
    var today: [UUID: Totals]
    var todayAll: Totals
    var budgets: [Budget]
    var budgetSpend: [String: Double]
    var forecasts: [String: Date]
    var alerts: [AlertCandidate]
    var notices: [String]
    var refreshedAt: Date?
    var secretStore: String
}

enum Commands {
    // MARK: status and refresh

    static func status(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let refresh = args.flag("--refresh")
        let sample = args.flag("--sample")
        try args.finish()
        if sample {
            return try emit(SampleData.overview(), json: json)
        }
        var workspace = try Workspace.open()
        // Nothing has been read on this computer yet, so the first status reads everything once.
        let terminal = TerminalProgress()
        let overview = refresh || workspace.state.refreshedAt == nil
            ? try await performRefresh(&workspace, claimAlerts: false, progress: terminal.handler)
            : try await currentOverview(workspace)
        terminal.finish()
        try emit(overview, json: json)
    }

    static func refresh(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let claimAlerts = args.flag("--claim-alerts")
        try args.finish()
        var workspace = try Workspace.open()
        let terminal = TerminalProgress()
        defer { terminal.finish() }
        let overview = try await performRefresh(&workspace, claimAlerts: claimAlerts, progress: terminal.handler)
        terminal.finish()
        try emit(overview, json: json)
    }

    /// Syncs every tool's login, reads limits with each account's own token, reads usage logs
    /// and Cursor's exports, and records limit samples for forecasts.
    static func performRefresh(_ workspace: inout Workspace, claimAlerts: Bool, progress: ProgressHandler? = nil) async throws -> Overview {
        let service = workspace.service
        let tracker = workspace.tracker
        var notices: [String] = []
        for (index, provider) in Provider.switchable.enumerated() {
            progress?(WorkProgress(step: .logins, done: index, total: Provider.switchable.count, detail: provider.name))
            switch await service.syncLive(provider) {
            case .saved(let id):
                if let account = await service.account(id) { notices.append("Saved \(account.email) to \(provider.name).") }
            case .failed(let message):
                notices.append(message)
            case .current, .signedOut:
                break
            }
        }
        let usage = await service.fetchUsage(previous: workspace.state.usageByID, progress: progress)
        let accounts = await service.accounts
        let active = await service.active
        let now = Date()

        for provider in Provider.switchable {
            try await tracker.noteActive(provider, account: active[provider], at: now)
        }
        // New prices first, so the logs read next are priced with them.
        await tracker.refreshPrices(now: now)
        try await tracker.ingestLocalLogs(progress: progress)
        for account in accounts where account.provider == .cursor {
            let key = account.id.uuidString
            if let last = workspace.state.cursorExports[key], now.timeIntervalSince(last) < 30 * 60 { continue }
            guard let secret = await service.secret(for: account.id),
                  let records = try? await CursorAdapter().usageExport(secret, account: account.id) else { continue }
            try await tracker.store(records)
            workspace.state.cursorExports[key] = now
        }
        await MergeFolder.syncIfDue(tracker: tracker, accounts: accounts, now: now)
        for account in accounts {
            guard let snapshot = usage[account.id], snapshot.error == nil, let fetchedAt = snapshot.fetchedAt else { continue }
            try await tracker.addSamples(account: account.id, windows: snapshot.windows, at: fetchedAt)
        }

        workspace.state.usage = Dictionary(uniqueKeysWithValues: usage.map { ($0.key.uuidString, $0.value) })
        workspace.state.active = Dictionary(uniqueKeysWithValues: active.map { ($0.key.rawValue, $0.value.uuidString) })
        workspace.state.refreshedAt = now

        var overview = try await overview(workspace, accounts: accounts, active: active, usage: usage, now: now)
        overview.notices = notices
        if claimAlerts {
            overview.alerts = overview.alerts.filter { workspace.state.sentAlerts[$0.key] == nil }
            for alert in overview.alerts { workspace.state.sentAlerts[alert.key] = now }
            workspace.state.sentAlerts = workspace.state.sentAlerts.filter { now.timeIntervalSince($0.value) < 40 * 86400 }
        }
        workspace.state.save()
        // The indexing pass draws on the same meter as the rest of a refresh, so a first index
        // shows up in the window and the menu instead of looking like the app has stalled.
        await CloudSync.syncIfDue(tracker: tracker, accounts: accounts, usage: usage, now: now, progress: progress)
        await CloudSync.liveIfDue(tracker: tracker, now: now)
        return overview
    }

    /// The last refresh's view, without touching the network.
    static func currentOverview(_ workspace: Workspace) async throws -> Overview {
        let accounts = await workspace.service.accounts
        let saved = Set(accounts.map(\.id))
        let active = workspace.state.activeByTool.filter { saved.contains($0.value) }
        return try await overview(workspace, accounts: accounts, active: active, usage: workspace.state.usageByID, now: Date())
    }

    private static func overview(_ workspace: Workspace, accounts: [Account], active: [Provider: UUID],
                                 usage: [UUID: UsageSnapshot], now: Date) async throws -> Overview {
        let tracker = workspace.tracker
        let sole = await workspace.service.soleAccounts
        var forecasts: [String: Date] = [:]
        for account in accounts {
            for window in usage[account.id]?.windows ?? [] {
                if let eta = try await tracker.forecast(account: account.id, window: window, now: now) {
                    forecasts[AlertRules.forecastKey(account.id, window.label)] = eta
                }
            }
        }
        let today = try await tracker.accountTotals(in: BudgetPeriod.day.interval(containing: now), sole: sole)
        let budgets = try await tracker.budgets()
        let spend = try await tracker.budgetSpend(for: budgets, now: now, sole: sole)
        let alerts = AlertRules.evaluate(accounts: accounts, active: active, usage: usage, forecasts: forecasts,
                                         budgets: budgets, budgetSpend: spend, now: now,
                                         unavailable: ToolSessions.runningInOwnFolder())
        return Overview(accounts: accounts, active: active, usage: usage, today: today.byAccount, todayAll: today.all,
                        budgets: budgets, budgetSpend: spend, forecasts: forecasts, alerts: alerts, notices: [],
                        refreshedAt: workspace.state.refreshedAt, secretStore: workspace.service.vault.storeName)
    }

    private static func emit(_ overview: Overview, json: Bool) throws {
        if json {
            try Output.json(StatusDocument(overview))
        } else {
            print(Reports.status(overview))
        }
    }

    static func recommend(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let refresh = args.flag("--refresh")
        let sample = args.flag("--sample")
        let provider = try toolOption(&args)
        try args.finish()
        let overview: Overview
        if sample {
            overview = SampleData.overview()
        } else {
            var workspace = try Workspace.open()
            overview = refresh
                ? try await performRefresh(&workspace, claimAlerts: false)
                : try await currentOverview(workspace)
        }
        let document = RecommendationListDocument(overview, provider: provider)
        if json { try Output.json(document) } else { print(Reports.recommendations(document)) }
    }

    // MARK: Accounts

    /// Runs a tool under one saved login in this terminal: Keyhop keeps a config folder per login,
    /// points the tool at it through its environment, and counts what it writes there against that
    /// login. Nothing in use changes, so another terminal can run under another login at once.
    static func run(_ args: inout Arguments) async throws {
        let command = args.command()
        let tool = try toolOption(&args)
        let first = args.nextPositional()
        if first == "map" { return try await runMap(&args, tool: tool) }
        guard let command, let executable = command.first, !executable.isEmpty else {
            throw UsageError("Say what to run after --, like: keyhop run work@studio.dev -- claude")
        }
        try args.finish()
        let workspace = try Workspace.open()
        let accounts = await workspace.service.accounts
        let account: Account
        if let first {
            account = try resolve(first, tool: tool, in: accounts)
        } else {
            let here = FileManager.default.currentDirectoryPath
            guard let id = RunMap.load().account(for: here), let mapped = accounts.first(where: { $0.id == id }) else {
                throw UsageError("Name a login, or map this folder first: keyhop run map . work@studio.dev")
            }
            account = mapped
        }
        guard RunDirectories.supports(account.provider), let key = RunDirectories.environmentKey(account.provider) else {
            throw UsageError("keyhop run works for Claude Code and Codex, the tools that take their config folder from the environment. \(account.provider.name) doesn't.")
        }
        let folder = try await workspace.service.prepareRun(account.id)
        guard let path = Shell.which(executable) ?? (FileManager.default.isExecutableFile(atPath: executable) ? executable : nil) else {
            throw UsageError("\(executable) isn't on your PATH.")
        }
        var environment = ProcessInfo.processInfo.environment
        if let folder {
            environment[key] = folder.path
            FileHandle.standardError.write(Data("keyhop: \(executable) runs as \(account.displayName) (\(key)=\(folder.path))\n".utf8))
        } else {
            // The login in use already lives in the usual folder; a second copy would sign it out.
            FileHandle.standardError.write(Data("keyhop: \(executable) runs as \(account.displayName), the login in use, from its usual folder\n".utf8))
        }
        let note = folder.flatMap { RunDirectories.markRunning(in: $0) }
        let status = Result { try Shell.runInteractive(path, Array(command.dropFirst()), environment: environment) }
        if let note { try? FileManager.default.removeItem(at: note) }
        exit(try status.get())
    }

    private static func runMap(_ args: inout Arguments, tool: Provider?) async throws {
        let json = args.flag("--json")
        let word = args.nextPositional()
        var map = RunMap.load()
        switch word {
        case nil:
            try args.finish()
            let accounts = await (try Workspace.open()).service.accounts
            let rows = map.folders.sorted { $0.key < $1.key }.map { path, id -> (folder: String, account: String) in
                (path, accounts.first(where: { $0.id.uuidString == id }).map { "\($0.provider.name) · \($0.displayName)" } ?? "a removed login")
            }
            if json {
                struct Row: Encodable { let folder: String; let account: String }
                try Output.json(rows.map { Row(folder: $0.folder, account: $0.account) })
            } else if rows.isEmpty {
                print("No folders mapped. Map one with keyhop run map <folder> <login>.")
            } else {
                for row in rows { print("\(row.folder)  ->  \(row.account)") }
            }
        case "off":
            let folder = try args.positional("the folder to unmap")
            try args.finish()
            guard map.remove(folder) else { throw UsageError("\(folder) isn't mapped.") }
            try map.save()
            print("\(RunMap.normalise(folder)) no longer picks a login.")
        case let folder?:
            let reference = try args.positional("the login the folder runs under")
            try args.finish()
            var isDirectory: ObjCBool = false
            let path = RunMap.normalise(folder)
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw UsageError("\(folder) isn't a folder.")
            }
            let workspace = try Workspace.open()
            let account = try resolve(reference, tool: tool, in: await workspace.service.accounts)
            guard RunDirectories.supports(account.provider) else {
                throw UsageError("keyhop run works for Claude Code and Codex. \(account.provider.name) doesn't take its config folder from the environment.")
            }
            map.set(path, account: account.id)
            try map.save()
            print("Inside \(path), keyhop run -- \(account.provider == .claude ? "claude" : "codex") runs as \(account.displayName).")
        }
    }

    static func switchAccount(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let tool = try toolOption(&args)
        let reference = try args.positional("the account to switch to")
        try args.finish()
        var workspace = try Workspace.open()
        let account = try resolve(reference, tool: tool, in: await workspace.service.accounts)
        let switched = try await workspace.service.switchTo(account.id)
        for provider in [account.provider] + switched.followed.map(\.provider) {
            let inUse = await workspace.service.active[provider]
            try await workspace.tracker.noteActive(provider, account: inUse, at: Date())
            workspace.state.active[provider.rawValue] = inUse?.uuidString
        }
        workspace.state.save()

        let message = "Switched \(account.provider.name) to \(account.displayName)."
        let overrides = Overrides.list(for: account.provider)
        let note = ([account.provider.switchNote].compactMap { $0 } + overrides + switched.notes).map(Output.plain).joined(separator: "\n")
        if json {
            try Output.json(ActionResult(ok: true, message: message, account: account.id, note: note.isEmpty ? nil : note))
        } else {
            print(message)
            if !note.isEmpty { print(note) }
        }
    }

    static func add(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let noWait = args.flag("--no-wait")
        let timeout = try args.option("--timeout").map { value -> Int in
            guard let seconds = Int(value), seconds > 0 else { throw UsageError("--timeout takes a number of seconds.") }
            return seconds
        } ?? 600
        let provider = try tool(try args.positional("a tool: \(Provider.wordList)"))
        guard provider.isSwitchable else {
            throw UsageError("\(provider.name) is measured only; it has no login Keyhop can switch.")
        }
        try args.finish()

        var workspace = try Workspace.open()
        let previous = try await workspace.service.signOutForAdding(provider)
        workspace.state.active[provider.rawValue] = nil
        workspace.state.save()
        let signedOut = await workspace.service.holdsManyLogins(provider)
            ? "\(provider.name) keeps every account you sign in to, so nothing was signed out."
            : "Signed \(provider.name) out on this computer\(previous == nil ? "" : ", after saving the login in use")."

        if noWait {
            let message = "\(signedOut) Sign in with the other account, then run `keyhop refresh` to save it."
            if json { try Output.json(ActionResult(ok: true, message: Output.plain(message), account: nil, note: nil)) } else { print(message) }
            return
        }
        if !json {
            print(signedOut)
            print(Output.plain(provider.signInHint))
            print("Waiting up to \(timeout / 60) min for the new login. Press Ctrl+C to stop.")
        }
        guard let result = await workspace.service.waitForLogin(provider, attempts: max(1, timeout / 2)) else {
            throw KeyhopError("No new \(provider.name) login yet. After you sign in, run `keyhop refresh` to save it.")
        }
        let message: String
        var saved: UUID?
        switch result.outcome {
        case .failed(let problem):
            throw KeyhopError(problem)
        case .saved(let id), .current(let id):
            saved = id
            let email = await workspace.service.account(id)?.email ?? "the account"
            message = result.alreadySaved ? "\(email) was already saved." : "Saved \(email) to \(provider.name)."
        case .signedOut:
            message = "\(provider.name) is still signed out."
        }
        try await workspace.tracker.noteActive(provider, account: saved, at: Date())
        workspace.state.active[provider.rawValue] = saved?.uuidString
        workspace.state.save()
        if json { try Output.json(ActionResult(ok: true, message: message, account: saved, note: nil)) } else { print(message) }
    }

    static func rename(_ args: inout Arguments) async throws {
        let clear = args.flag("--clear")
        let tool = try toolOption(&args)
        let reference = try args.positional("the account to rename")
        let name = args.remainingWords()
        try args.finish()
        guard clear || !name.isEmpty else { throw UsageError("Missing the new name. Use --clear to remove a name.") }
        let workspace = try Workspace.open()
        let account = try resolve(reference, tool: tool, in: await workspace.service.accounts)
        await workspace.service.rename(account.id, to: clear ? "" : name)
        print(clear ? "Removed the name from \(account.email)." : "Named \(account.email) \"\(name)\".")
    }

    /// Keeps a login for last, like a work or paid one: Smart Hop and the alerts offer it only when
    /// no other login of its tool has room. `--off` puts it back in turn.
    static func reserve(_ args: inout Arguments) async throws {
        let off = args.flag("--off")
        let tool = try toolOption(&args)
        let reference = try args.positional("the login to keep for last")
        try args.finish()
        let workspace = try Workspace.open()
        let account = try resolve(reference, tool: tool, in: await workspace.service.accounts)
        await workspace.service.keepForLast(account.id, !off)
        print(off ? "\(account.displayName) is back in turn for \(account.provider.name)."
                  : "\(account.displayName) is kept for last: Smart Hop offers it only when no other \(account.provider.name) login has room.")
    }

    static func remove(_ args: inout Arguments) async throws {
        let tool = try toolOption(&args)
        let reference = try args.positional("the account to remove")
        try args.finish()
        let workspace = try Workspace.open()
        let account = try resolve(reference, tool: tool, in: await workspace.service.accounts)
        try await workspace.service.remove(account.id)
        print("Removed \(account.displayName) from \(account.provider.name) and deleted its saved login.")
    }

    // MARK: Usage and budgets

    /// What each paid plan is worth this month, from this computer's own store.
    static func plans(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let skipLogs = args.flag("--no-read")
        try args.finish()
        let workspace = try Workspace.open()
        if !skipLogs {
            let terminal = TerminalProgress()
            defer { terminal.finish() }
            await workspace.tracker.refreshPrices()
            try await workspace.tracker.ingestLocalLogs(progress: terminal.handler)
        }
        let report = try await Self.plansReport(workspace: workspace, now: Date())
        if json { try Output.json(report) } else { print(Reports.plans(report)) }
    }

    /// Efficiency coaching from this computer's store: optimize, compare and yield.
    static func coach(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let skipLogs = args.flag("--no-read")
        let part = args.nextPositional()
        try args.finish()
        if let part, !["optimize", "compare", "yield"].contains(part) {
            throw UsageError("Unknown coach reading '\(part)'. Use optimize, compare or yield.")
        }
        let workspace = try Workspace.open()
        if !skipLogs {
            let terminal = TerminalProgress()
            defer { terminal.finish() }
            await workspace.tracker.refreshPrices()
            try await workspace.tracker.ingestLocalLogs(progress: terminal.handler)
        }
        let report = try await Self.coachReport(workspace: workspace, now: Date())
        if json { try Output.json(report) } else { print(Reports.coach(report, part: part)) }
    }

    static func coachReport(workspace: Workspace, now: Date) async throws -> CoachReport {
        let sole = await workspace.service.soleAccounts
        let range = InsightsRange.thirtyDays.resolved(firstUse: nil)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let since = formatter.string(from: range.interval(now: now).start)
        let login = CloudLink.load()?.login
        // git blocks on its processes, so it reads off the shared pool while the store is read.
        let reading = Task.detached(priority: .utility) { WorkYield.read(settings: WorkSettings.load(), since: since, login: login) }
        let digest = try await workspace.tracker.digest(interval: range.interval(now: now), previous: range.previous(now: now),
                                                        bucket: .day, provider: nil, sole: sole)
        let sessions = (try? await workspace.tracker.sessions(in: range.interval(now: now), provider: nil, sole: sole, limit: 200)) ?? []
        return CoachReport.build(digest: digest, sessions: sessions, work: await reading.value)
    }

    static func plansReport(workspace: Workspace, now: Date) async throws -> PlansReport {
        let accounts = await workspace.service.accounts
        let sole = await workspace.service.soleAccounts
        let month = InsightsRange.month.resolved(firstUse: nil)
        let digest = try await workspace.tracker.digest(interval: month.interval(now: now), previous: month.previous(now: now),
                                                        bucket: .day, provider: nil, sole: sole)
        var value: [UUID: Totals] = [:]
        for (key, totals) in digest.byAccount { if let id = key.account { value[id] = totals } }
        let peaks = try await workspace.tracker.windowPeaks(since: now.addingTimeInterval(-7 * 86400))
        return PlansReport.build(accounts: accounts, usage: workspace.state.usageByID, apiValue: value, peaks: peaks, now: now)
    }

    /// Every login's remaining limit pooled, where it was this week and where it is heading.
    static func forecast(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let refresh = args.flag("--refresh")
        let sample = args.flag("--sample")
        let tool = try toolOption(&args)
        try args.finish()
        let report: QuotaReport
        if sample {
            report = SampleData.quota(tool: tool)
        } else {
            var workspace = try Workspace.open()
            if refresh || workspace.state.refreshedAt == nil {
                let terminal = TerminalProgress()
                _ = try await performRefresh(&workspace, claimAlerts: false, progress: terminal.handler)
                terminal.finish()
            }
            report = try await quotaReport(workspace: workspace, tool: tool, now: Date())
        }
        if json { try Output.json(report) } else { print(Reports.forecast(report, tool: tool)) }
    }

    static func quotaReport(workspace: Workspace, tool: Provider? = nil, now: Date) async throws -> QuotaReport {
        let accounts = await workspace.service.accounts.filter { tool == nil || $0.provider == tool }
        let samples = try await workspace.tracker.limitSamples(since: now.addingTimeInterval(-8 * 86400))
        return QuotaReport.build(accounts: QuotaInput.list(accounts: accounts, usage: workspace.state.usageByID,
                                                           active: workspace.state.activeByTool),
                                 samples: samples, now: now)
    }

    static func usage(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let skipLogs = args.flag("--no-read")
        let word = try args.option("--range") ?? "week"
        guard let asked = InsightsRange(argument: word) else {
            throw UsageError("Unknown range '\(word)'. Use today, week, month, 30d, 90d, 12m, all, or dates as 2026-01-01..2026-03-31.")
        }
        let tool = try toolOption(&args)
        try args.finish()

        let workspace = try Workspace.open()
        if !skipLogs {
            let terminal = TerminalProgress()
            defer { terminal.finish() }
            await workspace.tracker.refreshPrices()
            try await workspace.tracker.ingestLocalLogs(progress: terminal.handler)
        }
        let now = Date()
        let range = asked.resolved(firstUse: try await workspace.tracker.firstUse(provider: tool))
        let sole = await workspace.service.soleAccounts
        let digest = try await workspace.tracker.digest(interval: range.interval(now: now), previous: range.previous(now: now),
                                                        bucket: range.bucket, provider: tool, sole: sole)
        var report = digest
        report.sessions = (try? await workspace.tracker.sessions(in: range.interval(now: now), provider: tool, sole: sole)) ?? []
        let accounts = await workspace.service.accounts
        let budgets = try await workspace.tracker.budgets()
        let spend = try await workspace.tracker.budgetSpend(for: budgets, now: now, sole: sole)
        if json {
            try Output.json(UsageDocument(range: range, now: now, digest: report, accounts: accounts, budgets: budgets, spend: spend))
        } else {
            print(Reports.usage(range: range, digest: report, accounts: accounts))
        }
    }

    static func budget(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let action = args.nextPositional() ?? "list"
        let workspace = try Workspace.open()
        let accounts = await workspace.service.accounts

        switch action {
        case "list":
            try args.finish()
            let now = Date()
            let budgets = try await workspace.tracker.budgets()
            let spend = try await workspace.tracker.budgetSpend(for: budgets, now: now, sole: await workspace.service.soleAccounts)
            let documents = budgets.map { BudgetDocument($0, spent: spend[$0.scope] ?? 0, accounts: accounts) }
            if json {
                try Output.json(documents)
            } else if documents.isEmpty {
                print("No budgets yet. Set one with `keyhop budget set all 200 --period month`.")
            } else {
                for document in documents {
                    print("\(document.name): \(Numbers.usd(document.spent)) of \(Numbers.usd(document.amount)) per \(document.period)")
                }
            }

        case "set":
            let word = try args.option("--period") ?? "month"
            guard let period = BudgetPeriod(rawValue: word) else { throw UsageError("Unknown period '\(word)'. Use day, week or month.") }
            let tool = try toolOption(&args)
            let target = try args.positional("all, or the account the budget is for")
            let amountWord = try args.positional("an amount in dollars")
            try args.finish()
            guard let amount = Double(amountWord.replacingOccurrences(of: "$", with: "")), amount > 0 else {
                throw UsageError("The amount must be a positive number of dollars.")
            }
            let scope = try budgetScope(target, tool: tool, accounts: accounts)
            try await workspace.tracker.setBudget(Budget(scope: scope.id, amount: amount, period: period), scope: scope.id)
            print("Budget for \(scope.name): \(Numbers.usd(amount)) \(period.title), counting what you are charged. Keyhop warns at 80% and 100%.")

        case "clear":
            let tool = try toolOption(&args)
            let target = try args.positional("all, or the account whose budget to clear")
            try args.finish()
            let scope = try budgetScope(target, tool: tool, accounts: accounts)
            try await workspace.tracker.setBudget(nil, scope: scope.id)
            print("Cleared the budget for \(scope.name).")

        default:
            throw UsageError("Unknown budget action '\(action)'. Use list, set or clear.")
        }
    }

    // MARK: App

    static func update(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let checkOnly = args.flag("--check")
        let once = try args.option("--channel").map { word -> UpdateChannel in
            guard let channel = UpdateChannel.parse(word) else { throw UsageError("Channel must be stable or beta.") }
            return channel
        }
        if args.nextPositional() == "channel" {
            let word = args.nextPositional()
            try args.finish()
            if let word {
                guard let channel = UpdateChannel.parse(word) else { throw UsageError("Channel must be stable or beta.") }
                try UpdateChannel.save(channel)
                print("Keyhop now follows \(channel.title). \(channel.note)")
                if channel == .stable, AppVersion.isPrerelease {
                    print("This beta stays until a Stable release newer than \(AppVersion.current) comes out.")
                }
            } else {
                print("Keyhop follows \(UpdateChannel.current.title)\(UpdateChannel.saved == nil ? " (the default for \(AppVersion.current))" : ""). \(UpdateChannel.current.note)")
                print("Change it with: keyhop update channel stable|beta")
            }
            return
        }
        try args.finish()
        let channel = once ?? UpdateChannel.current
        let release = try await Releases.latest(channel: channel)
        let current = AppVersion.current
        let available = Releases.isNewer(release.version, than: current)

        if checkOnly || !available {
            if json {
                try Output.json(UpdateDocument(current: current, latest: release.version, available: available, page: release.page,
                                               channel: channel.rawValue))
            } else {
                print(available
                    ? "Keyhop \(release.version) is available on \(channel.title) (you have \(current)). Run `keyhop update` to install it."
                    : "Keyhop \(current) is the latest \(channel.title) version.")
            }
            return
        }
        #if os(macOS)
        print("Keyhop \(release.version) is available. The menu bar app installs it automatically, or click the version number in its menu.")
        #else
        #if os(Windows)
        if let path = Bundle.main.executableURL?.path.lowercased(), path.contains("\\scoop\\apps\\") || path.contains("/scoop/apps/") {
            throw KeyhopError("Keyhop was installed with Scoop, so update it there: scoop update keyhop")
        }
        let how = try await WindowsInstaller.install(release, quiet: json)
        #else
        let how = try await LinuxInstaller.install(release, quiet: json)
        #endif
        if json {
            try Output.json(UpdateDocument(current: release.version, latest: release.version, available: false, page: release.page,
                                           channel: channel.rawValue))
        } else {
            print("Installed Keyhop \(release.version) \(how).")
        }
        #endif
    }

    /// `0` lets the system pick a free port. A named port is how a test runner owns the address.
    private static func port(_ raw: String?) throws -> UInt16 {
        guard let raw else { return 0 }
        guard let port = UInt16(raw), port > 0 else {
            throw UsageError("--port needs a number from 1 to 65535.")
        }
        return port
    }

    static func dashboard(_ args: inout Arguments) async throws {
        let sample = args.flag("--sample")
        let noOpen = args.flag("--no-open")
        let json = args.flag("--json")
        let section = try args.option("--section") ?? "overview"
        let port = try Self.port(try args.option("--port"))
        guard Dashboard.sections.contains(section) else {
            throw UsageError("Unknown section '\(section)'. Use \(Dashboard.sections.joined(separator: ", ")).")
        }
        try args.finish()
        try await Dashboard.run(sample: sample, section: section, open: !noOpen, json: json, port: port)
    }

    /// Insights is the dashboard's Usage section; `--output` saves the dashboard as one file instead.
    static func insights(_ args: inout Arguments) async throws {
        let noOpen = args.flag("--no-open")
        let skipLogs = args.flag("--no-read")
        let sample = args.flag("--sample")
        let output = try args.option("--output")
        try args.finish()

        guard let output else {
            try await Dashboard.run(sample: sample, section: "usage", open: !noOpen, json: false)
            return
        }
        let page = try await Dashboard.staticPage(sample: sample, readLogs: !skipLogs)
        let file = URL(fileURLWithPath: output)
        // It lists account emails, so it gets the same private permissions as everything else Keyhop writes.
        try Files.writeAtomically(Data(page.utf8), to: file)
        print(file.path)
        if !noOpen, !Desktop.open(file.absoluteString) {
            Output.error("Couldn't open a browser. Open \(file.path) yourself.")
        }
    }

    // MARK: Merge folder

    struct MergeDocument: Encodable {
        let folder: String?
        let file: String
        var machines: Int?
        var exported: Int?
        var imported: Int?
    }

    static func merge(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let word = args.nextPositional() ?? "status"
        switch word {
        case "status":
            try args.finish()
            let settings = MergeFolder.Settings.load()
            let document = MergeDocument(folder: settings.folder, file: MergeFolder.machineFile())
            if json {
                try Output.json(document)
            } else if let folder = settings.folder {
                print("Merging through \(folder) as \(document.file).")
                if let last = settings.lastSync { print("Last pass: \(Output.relative(last))") }
                if let problem = settings.lastError { print("Last pass failed: \(problem)") }
            } else {
                print("Merging is off. Point it at a folder your machines already sync: keyhop merge <folder>")
            }
        case "off":
            try args.finish()
            var settings = MergeFolder.Settings.load()
            guard settings.folder != nil else { throw UsageError("Merging is already off.") }
            settings.folder = nil
            settings.lastSync = nil
            try settings.save()
            print("Merging is off. The files already in the folder stay as they are.")
        case "now":
            try args.finish()
            let workspace = try Workspace.open()
            let outcome = try await MergeFolder.sync(tracker: workspace.tracker, accounts: await workspace.service.accounts)
            try reportMerge(outcome, json: json)
        default:
            try args.finish()
            let url = URL(fileURLWithPath: (word as NSString).expandingTildeInPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw UsageError("\(word) isn't a folder. Pick one your machines already sync, like one in iCloud Drive.")
            }
            var settings = MergeFolder.Settings.load()
            // Saved absolute: the app's working directory is not the terminal's.
            settings.folder = url.path
            try settings.save()
            let workspace = try Workspace.open()
            let outcome = try await MergeFolder.sync(tracker: workspace.tracker, accounts: await workspace.service.accounts)
            if !json { print("Merging through \(word) as \(MergeFolder.machineFile()). Run the same command on your other machines.") }
            try reportMerge(outcome, json: json)
        }
    }

    private static func reportMerge(_ outcome: MergeFolder.Outcome, json: Bool) throws {
        let settings = MergeFolder.Settings.load()
        if json {
            try Output.json(MergeDocument(folder: settings.folder, file: MergeFolder.machineFile(),
                                          machines: outcome.machines, exported: outcome.exported, imported: outcome.imported))
        } else {
            let others = outcome.machines == 1 ? "1 other machine" : "\(outcome.machines) other machines"
            print("Wrote \(outcome.exported) new events, read \(outcome.imported) from \(others).")
        }
    }

    static func doctor(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        try args.finish()
        let document = await doctorDocument(sample: false)
        if json { try Output.json(document) } else { print(Reports.doctor(document)) }
    }

    /// The providers' own status pages, for every tool that has one.
    static func services(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let sample = args.flag("--sample")
        try args.finish()
        let health = sample ? SampleData.services() : await ServiceStatus.check(Provider.allCases)
        if json { try Output.json(health) } else { print(Reports.services(health)) }
    }

    /// What Keyhop can see on this computer. Sample data reads no logins.
    static func doctorDocument(sample: Bool) async -> DoctorDocument {
        if !sample { PriceCatalog.load(from: Platform.dataDirectory) }
        var tools: [DoctorDocument.Tool] = []
        let sampleEmails: [Provider: String] = [.claude: "me@personal.dev", .cursor: "me@personal.dev", .codex: "me@personal.dev", .gemini: "me@personal.dev"]
        for provider in Provider.allCases {
            var email: String?
            var problem: String?
            if sample {
                email = sampleEmails[provider]
            } else if let adapter = Adapters.all[provider] {
                do {
                    email = try await adapter.readLive()?.email
                } catch {
                    problem = error.localizedDescription
                }
                if email == nil, problem == nil, ToolDetection.installed(provider) {
                    problem = adapter.blocker().map(Output.plain) ?? ToolDetection.note(provider)
                }
            }
            tools.append(DoctorDocument.Tool(id: provider.rawValue, name: provider.name, installed: sample || ToolDetection.installed(provider),
                                             signedInAs: email, problem: problem, loginLocation: ToolDetection.loginLocation(provider),
                                             overrides: sample ? [] : Overrides.list(for: provider)))
        }
        return DoctorDocument(
            version: AppVersion.current,
            platform: Platform.name,
            dataDirectory: Platform.dataDirectory.path,
            secretStore: sample ? "sample data" : Vault().storeName,
            savedAccounts: sample ? SampleData.accounts().count : AccountService.loadAccounts(from: Platform.dataDirectory).count,
            prices: .current,
            tools: tools,
            trayInstalled: ToolDetection.trayInstalled,
            statusNotifierHost: ToolDetection.statusNotifierHost
        )
    }

    static func reset(_ args: inout Arguments) async throws {
        let confirmed = args.flag("--yes", "-y")
        try args.finish()
        if !confirmed {
            guard Output.isTerminal, Terminal.inputIsInteractive else {
                throw UsageError("Add --yes to confirm when not running in a terminal.")
            }
            print("This removes every saved login, your usage history and Keyhop's settings. Your tools stay signed in.")
            print("Type yes to continue: ", terminator: "")
            guard readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "yes" else {
                print("Nothing was removed.")
                return
            }
        }
        print(await ResetAll.run())
    }

    // MARK: Helpers

    static func tool(_ word: String) throws -> Provider {
        guard let provider = Provider(rawValue: word.lowercased()) else {
            throw UsageError("Unknown tool '\(word)'. Use \(Provider.wordList).")
        }
        return provider
    }

    static func toolOption(_ args: inout Arguments) throws -> Provider? {
        try args.option("--tool").map(tool)
    }

    /// Finds a saved account by email, name or the start of its ID.
    static func resolve(_ reference: String, tool: Provider?, in accounts: [Account]) throws -> Account {
        let needle = reference.lowercased()
        let pool = accounts.filter { tool == nil || $0.provider == tool }
        let exact = pool.filter {
            $0.email.lowercased() == needle || $0.label?.lowercased() == needle || $0.id.uuidString.lowercased() == needle
        }
        let matches = exact.isEmpty ? pool.filter { $0.id.uuidString.lowercased().hasPrefix(needle) } : exact
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty {
            throw UsageError("No saved account matches '\(reference)'. Run `keyhop status` to see them.")
        }
        let listed = matches.map { "\($0.provider.rawValue) \($0.email) (\($0.id.uuidString.prefix(8).lowercased()))" }.joined(separator: ", ")
        throw UsageError("'\(reference)' matches \(matches.count) accounts: \(listed). Add --tool, or use the ID.")
    }

    private static func budgetScope(_ target: String, tool: Provider?, accounts: [Account]) throws -> (id: String, name: String) {
        if target.lowercased() == Budget.everything { return (Budget.everything, "all accounts") }
        let account = try resolve(target, tool: tool, in: accounts)
        return (Budget.scope(for: account.id), account.displayName)
    }
}

/// What's installed and where each tool keeps its login, for `keyhop doctor`.
enum ToolDetection {
    static func installed(_ provider: Provider) -> Bool {
        switch provider {
        case .claude:
            return Shell.which("claude") != nil || FileManager.default.fileExists(atPath: Files.home.appendingPathComponent(".claude").path)
        case .cursor:
            return CursorApp.isInstalled
        case .codex:
            return Shell.which("codex") != nil || FileManager.default.fileExists(atPath: Files.home.appendingPathComponent(".codex").path)
        case .gemini:
            return Shell.which("gemini") != nil || FileManager.default.fileExists(atPath: GeminiAdapter.directory.path)
        case .opencode:
            return Shell.which("opencode") != nil || FileManager.default.fileExists(atPath: OpenCodeAdapter.directory.path)
        case .pi:
            return Shell.which("pi") != nil || FileManager.default.fileExists(atPath: PiAdapter.directory.path)
        case .copilot:
            // Copilot signs in as a GitHub account, so gh is what Keyhop needs to switch it.
            return Shell.which("copilot") != nil || Shell.which("gh") != nil
                || FileManager.default.fileExists(atPath: CopilotAdapter.cliDirectory.path)
        case .windsurf:
            return WindsurfAdapter.isAppInstalled || FileManager.default.fileExists(atPath: WindsurfAdapter.directory.path)
        case .codebuff:
            return Shell.which("codebuff") != nil || Shell.which("manicode") != nil
                || FileManager.default.fileExists(atPath: CodebuffAdapter.directory.path)
        case .amp, .goose, .qwen, .kimi, .grok, .kilo, .openclaw:
            return MeasuredFeeds.present(provider)
        }
    }

    /// What to tell someone whose tool is here but shows no login, when that could be Keyhop's doing.
    static func note(_ provider: Provider) -> String? {
        switch provider {
        case .windsurf:
            // Honest about the one adapter Keyhop couldn't test: an empty result may be its miss.
            "No login found in \(WindsurfAdapter.credentialsURL.path). If Windsurf is signed in, it keeps its login somewhere this version of Keyhop doesn't read yet."
        case .codebuff where ProcessInfo.processInfo.environment["CODEBUFF_API_KEY"]?.isEmpty == false:
            "CODEBUFF_API_KEY is set. Environment-only credentials cannot be switched; run `codebuff login` to create a saved account."
        default:
            nil
        }
    }

    static func loginLocation(_ provider: Provider) -> String {
        switch provider {
        case .claude:
            #if os(macOS)
            let service = ClaudeAdapter.keychainService(environment: ProcessInfo.processInfo.environment)
            return "Keychain item \"\(service)\""
            #else
            return ClaudeAdapter.configDirectory(environment: ProcessInfo.processInfo.environment, home: Files.home)
                .appendingPathComponent(".credentials.json").path
            #endif
        case .cursor:
            return CursorAdapter.databaseURL.path
        case .codex:
            return CodexAdapter.homeDirectory.appendingPathComponent("auth.json").path
        case .gemini:
            return GeminiAdapter.credentialsURL.path
        case .opencode:
            return OpenCodeAdapter.credentialsURL.path
        case .pi:
            return PiAdapter.credentialsURL.path
        case .copilot:
            return "The GitHub CLI's login for \(CopilotAdapter.host), in \(CopilotAdapter.hostsURL.path)"
        case .windsurf:
            return WindsurfAdapter.credentialsURL.path
        case .codebuff:
            return CodebuffAdapter.credentialsURL.path
        case .amp, .goose, .qwen, .kimi, .grok, .kilo, .openclaw:
            return MeasuredFeeds.usageLocation(provider)
        }
    }

    static var trayInstalled: Bool {
        #if os(macOS)
        return Bundle.main.bundlePath.hasSuffix(".app")
        #elseif os(Windows)
        return Bundle.main.executableURL.map {
            FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().appendingPathComponent("keyhop-tray.exe").path)
        } ?? false
        #else
        return Shell.which("keyhop-tray") != nil
        #endif
    }

    /// Whether the desktop shows tray icons (GNOME needs the AppIndicator extension). Nil off Linux.
    static var statusNotifierHost: Bool? {
        #if os(Linux)
        guard let gdbus = Shell.which("gdbus"),
              let result = try? Shell.run(gdbus, ["call", "--session", "--dest", "org.freedesktop.DBus", "--object-path", "/org/freedesktop/DBus",
                                                 "--method", "org.freedesktop.DBus.NameHasOwner", "org.kde.StatusNotifierWatcher"]),
              result.status == 0 else { return false }
        return String(decoding: result.stdout, as: UTF8.self).contains("true")
        #else
        return nil
        #endif
    }
}

/// Removes everything Keyhop stores. The tools' own current logins stay as they are.
enum ResetAll {
    static func run() async -> String {
        let directory = Platform.dataDirectory
        let accounts = AccountService.loadAccounts(from: directory)
        let vault = Vault()
        for account in accounts {
            await vault.delete(account.id)
        }
        CloudLink.remove()
        try? FileManager.default.removeItem(at: directory)
        #if os(macOS)
        if Bundle.main.bundlePath.hasSuffix(".app") {
            try? await SMAppService.mainApp.unregister()
        }
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        #elseif os(Windows)
        if let reg = Shell.which("reg.exe") {
            _ = try? Shell.run(reg, ["delete", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", "Keyhop", "/f"])
            _ = try? Shell.run(reg, ["delete", "HKCU\\Software\\Keyhop", "/f"])
        }
        #else
        try? FileManager.default.removeItem(at: Platform.configDirectory.appendingPathComponent("keyhop"))
        try? FileManager.default.removeItem(at: Platform.configDirectory.appendingPathComponent("autostart/app.keyhop.Keyhop.desktop"))
        #endif
        return "Removed \(accounts.count) saved login\(accounts.count == 1 ? "" : "s"), usage history and settings."
    }
}

#if os(Windows)
/// Installs a release over this copy. Windows won't overwrite a running program, but it will
/// rename one, so the files in use step aside first and are deleted on a later run.
enum WindowsInstaller {
    private static let leftoverMarker = ".keyhop-old-"

    static func install(_ release: ReleaseInfo, quiet: Bool) async throws -> String {
        let native = ProcessInfo.processInfo.environment["PROCESSOR_ARCHITECTURE"]?.uppercased() == "ARM64" ? "arm64" : "x86_64"
        let names = ["keyhop-\(release.version)-windows-\(native).zip", "keyhop-\(release.version)-windows-x86_64.zip"]
        guard let sumsURL = release.assets["SHA256SUMS"] else {
            throw KeyhopError("This release has no checksum file, so Keyhop won't install it.")
        }
        guard let name = names.first(where: { release.assets[$0] != nil }), let url = release.assets[name] else {
            throw KeyhopError("Release \(release.version) has no Windows download.")
        }
        let sums = String(decoding: try await Releases.download(sumsURL), as: UTF8.self)
        guard let expected = Releases.expectedHash(in: sums, for: name) else {
            throw KeyhopError("\(name) isn't in the release checksums, so Keyhop won't install it.")
        }
        if !quiet { print("Downloading \(name)…") }
        let data = try await Releases.download(url)
        guard try Releases.sha256(data) == expected else {
            throw KeyhopError("The download didn't match the release checksum, so nothing was installed.")
        }
        guard let destination = Bundle.main.executableURL?.deletingLastPathComponent() else {
            throw KeyhopError("Couldn't tell where Keyhop is installed.")
        }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("keyhop-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let archive = work.appendingPathComponent(name)
        try data.write(to: archive)
        // Windows 10 and 11 ship bsdtar, which reads zip files.
        guard let tar = Shell.which("tar.exe") else { throw KeyhopError("tar.exe isn't available to unpack the update.") }
        let unpack = try Shell.run(tar, ["-xf", archive.path, "-C", work.path])
        guard unpack.status == 0 else { throw KeyhopError("Couldn't unpack \(name): \(unpack.stderr)") }
        let source = work.appendingPathComponent("keyhop-\(release.version)")

        for file in try fm.contentsOfDirectory(atPath: source.path) {
            let from = source.appendingPathComponent(file)
            let to = destination.appendingPathComponent(file)
            if fm.fileExists(atPath: to.path) {
                try fm.moveItem(at: to, to: destination.appendingPathComponent(file + leftoverMarker + UUID().uuidString.prefix(8)))
            }
            try fm.copyItem(at: from, to: to)
        }
        cleanUp()
        return "in \(destination.path)"
    }

    /// Deletes files an earlier update moved aside; the ones still in use stay until next time.
    static func cleanUp() {
        guard let folder = Bundle.main.executableURL?.deletingLastPathComponent(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.contains(leftoverMarker) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
#endif

#if os(Linux)
/// Installs a release over this copy: the RPM through dnf when Keyhop came from an RPM,
/// otherwise the tarball into ~/.local. Nothing installs unless its checksum matches.
enum LinuxInstaller {
    static func install(_ release: ReleaseInfo, quiet: Bool) async throws -> String {
        let arch = try architecture()
        guard let sumsURL = release.assets["SHA256SUMS"] else {
            throw KeyhopError("This release has no checksum file, so Keyhop won't install it.")
        }
        let sums = String(decoding: try await Releases.download(sumsURL), as: UTF8.self)
        let manager = PackageManager.owning()
        let name: String
        switch manager {
        case .rpm: name = "keyhop-\(release.version)-1.\(arch).rpm"
        case .deb: name = "keyhop_\(release.version)_\(arch == "x86_64" ? "amd64" : "arm64").deb"
        case .pacman: name = "keyhop-\(release.version)-1-\(arch).pkg.tar.zst"
        case nil: name = "keyhop-\(release.version)-linux-\(arch).tar.gz"
        }
        guard let url = release.assets[name], let expected = Releases.expectedHash(in: sums, for: name) else {
            throw KeyhopError("Release \(release.version) has no \(name) for this computer.")
        }
        if !quiet { print("Downloading \(name)…") }
        let data = try await Releases.download(url)
        guard try Releases.sha256(data) == expected else {
            throw KeyhopError("The download didn't match the release checksum, so nothing was installed.")
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appendingPathComponent(name)
        try data.write(to: file)

        if let manager {
            guard let command = manager.installCommand(for: file.path) else {
                throw KeyhopError("\(manager.tool) isn't available. Install \(file.path) with your package manager.")
            }
            let status: Int32
            if Output.isTerminal, Terminal.inputIsInteractive, let sudo = Shell.which("sudo") {
                status = try Shell.runInteractive(sudo, command)
            } else if let pkexec = Shell.which("pkexec") {
                // pkexec shows the desktop's own password dialog, for updates started from the tray.
                status = try Shell.run(pkexec, command).status
            } else {
                throw KeyhopError("Couldn't ask for administrator rights. Run: sudo \(command.joined(separator: " "))")
            }
            guard status == 0 else { throw KeyhopError("\(manager.tool) didn't install the update (exit \(status)).") }
            return "with \(manager.tool)"
        }

        guard let tar = Shell.which("tar") else { throw KeyhopError("tar isn't installed.") }
        let unpack = try Shell.run(tar, ["-xzf", file.path, "-C", work.path])
        guard unpack.status == 0 else { throw KeyhopError("Couldn't unpack \(name).") }
        let installer = work.appendingPathComponent("keyhop-\(release.version)/install-local.sh")
        let result = try Shell.run("/bin/sh", [installer.path])
        guard result.status == 0 else { throw KeyhopError("The installer failed: \(result.stderr)") }
        return "into ~/.local"
    }

    static func architecture() throws -> String {
        let result = try Shell.run(Shell.which("uname") ?? "/bin/uname", ["-m"])
        let machine = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["x86_64", "aarch64"].contains(machine) else {
            throw KeyhopError("Keyhop releases are built for x86_64 and aarch64, not \(machine).")
        }
        return machine
    }

    /// The package manager that installed this copy, if one did.
    enum PackageManager {
        case rpm, deb, pacman

        var tool: String {
            switch self {
            case .rpm: "dnf"
            case .deb: "apt"
            case .pacman: "pacman"
            }
        }

        func installCommand(for path: String) -> [String]? {
            switch self {
            case .rpm:
                if let dnf = Shell.which("dnf") { return [dnf, "install", "-y", path] }
                if let zypper = Shell.which("zypper") { return [zypper, "--non-interactive", "install", "--allow-unsigned-rpm", path] }
                return nil
            case .deb:
                return Shell.which("apt-get").map { [$0, "install", "-y", path] }
            case .pacman:
                return Shell.which("pacman").map { [$0, "-U", "--noconfirm", path] }
            }
        }

        static func owning() -> PackageManager? {
            let executable = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath().path
            guard executable.hasPrefix("/usr/") else { return nil }
            func owns(_ tool: String, _ arguments: [String]) -> Bool {
                guard let path = Shell.which(tool), let result = try? Shell.run(path, arguments + [executable]) else { return false }
                return result.status == 0
            }
            if owns("dpkg", ["-S"]) { return .deb }
            if owns("pacman", ["-Qo"]) { return .pacman }
            if owns("rpm", ["-qf"]) { return .rpm }
            return nil
        }
    }
}
#endif
