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

    static func load() -> CLIState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CLIState.self, from: Data(contentsOf: url))) ?? CLIState()
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
        let overview = refresh || workspace.state.refreshedAt == nil
            ? try await performRefresh(&workspace, claimAlerts: false)
            : try await currentOverview(workspace)
        try emit(overview, json: json)
    }

    static func refresh(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let claimAlerts = args.flag("--claim-alerts")
        try args.finish()
        var workspace = try Workspace.open()
        let overview = try await performRefresh(&workspace, claimAlerts: claimAlerts)
        try emit(overview, json: json)
    }

    /// Syncs every tool's login, reads limits with each account's own token, reads usage logs
    /// and Cursor's exports, and records limit samples for forecasts.
    static func performRefresh(_ workspace: inout Workspace, claimAlerts: Bool) async throws -> Overview {
        let service = workspace.service
        let tracker = workspace.tracker
        var notices: [String] = []
        for provider in Provider.allCases {
            switch await service.syncLive(provider) {
            case .saved(let id):
                if let account = await service.account(id) { notices.append("Saved \(account.email) to \(provider.name).") }
            case .failed(let message):
                notices.append(message)
            case .current, .signedOut:
                break
            }
        }
        let usage = await service.fetchUsage(previous: workspace.state.usageByID)
        let accounts = await service.accounts
        let active = await service.active
        let now = Date()

        for provider in Provider.allCases {
            try await tracker.noteActive(provider, account: active[provider], at: now)
        }
        try await tracker.ingestLocalLogs()
        for account in accounts where account.provider == .cursor {
            let key = account.id.uuidString
            if let last = workspace.state.cursorExports[key], now.timeIntervalSince(last) < 30 * 60 { continue }
            guard let secret = await service.secret(for: account.id),
                  let records = try? await CursorAdapter().usageExport(secret, account: account.id) else { continue }
            try await tracker.store(records)
            workspace.state.cursorExports[key] = now
        }
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
        await CloudSync.syncIfDue(tracker: tracker, now: now)
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
                                         budgets: budgets, budgetSpend: spend, now: now)
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

    // MARK: Accounts

    static func switchAccount(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let tool = try toolOption(&args)
        let reference = try args.positional("the account to switch to")
        try args.finish()
        var workspace = try Workspace.open()
        let account = try resolve(reference, tool: tool, in: await workspace.service.accounts)
        try await workspace.service.switchTo(account.id)
        let inUse = await workspace.service.active[account.provider]
        try await workspace.tracker.noteActive(account.provider, account: inUse, at: Date())
        workspace.state.active[account.provider.rawValue] = inUse?.uuidString
        workspace.state.save()

        let message = "Switched \(account.provider.name) to \(account.displayName)."
        let note = account.provider.switchNote.map(Output.plain)
        if json {
            try Output.json(ActionResult(ok: true, message: message, account: account.id, note: note))
        } else {
            print(message)
            if let note { print(note) }
        }
    }

    static func add(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let noWait = args.flag("--no-wait")
        let timeout = try args.option("--timeout").map { value -> Int in
            guard let seconds = Int(value), seconds > 0 else { throw UsageError("--timeout takes a number of seconds.") }
            return seconds
        } ?? 600
        let provider = try tool(try args.positional("a tool: claude, cursor or codex"))
        try args.finish()

        var workspace = try Workspace.open()
        let previous = try await workspace.service.signOutForAdding(provider)
        workspace.state.active[provider.rawValue] = nil
        workspace.state.save()
        let signedOut = "Signed \(provider.name) out on this computer\(previous == nil ? "" : ", after saving the login in use")."

        if noWait {
            let message = "\(signedOut) Sign in with the other account, then run `switchr refresh` to save it."
            if json { try Output.json(ActionResult(ok: true, message: Output.plain(message), account: nil, note: nil)) } else { print(message) }
            return
        }
        if !json {
            print(signedOut)
            print(Output.plain(provider.signInHint))
            print("Waiting up to \(timeout / 60) min for the new login. Press Ctrl+C to stop.")
        }
        guard let result = await workspace.service.waitForLogin(provider, attempts: max(1, timeout / 2)) else {
            throw SwitchrError("No new \(provider.name) login yet. After you sign in, run `switchr refresh` to save it.")
        }
        let message: String
        var saved: UUID?
        switch result.outcome {
        case .failed(let problem):
            throw SwitchrError(problem)
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

    static func usage(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        let skipLogs = args.flag("--no-read")
        let word = try args.option("--range") ?? "week"
        guard let range = InsightsRange(argument: word) else {
            throw UsageError("Unknown range '\(word)'. Use today, week, month or 30d.")
        }
        let tool = try toolOption(&args)
        try args.finish()

        let workspace = try Workspace.open()
        if !skipLogs { try await workspace.tracker.ingestLocalLogs() }
        let now = Date()
        let sole = await workspace.service.soleAccounts
        let digest = try await workspace.tracker.digest(interval: range.interval(now: now), previous: range.previous(now: now),
                                                        bucket: range.bucket, provider: tool, sole: sole)
        let accounts = await workspace.service.accounts
        let budgets = try await workspace.tracker.budgets()
        let spend = try await workspace.tracker.budgetSpend(for: budgets, now: now, sole: sole)
        if json {
            try Output.json(UsageDocument(range: range, now: now, digest: digest, accounts: accounts, budgets: budgets, spend: spend))
        } else {
            print(Reports.usage(range: range, digest: digest, accounts: accounts))
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
                print("No budgets yet. Set one with `switchr budget set all 200 --period month`.")
            } else {
                for document in documents {
                    print("\(document.name): \(Numbers.usd(document.spent)) of \(Numbers.usd(document.amount)) per \(document.period) at API prices")
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
            print("Budget for \(scope.name): \(Numbers.usd(amount)) \(period.title) at API prices. Switchr warns at 80% and 100%.")

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
        try args.finish()
        let release = try await Releases.latest()
        let current = AppVersion.current
        let available = Releases.isNewer(release.version, than: current)

        if checkOnly || !available {
            if json {
                try Output.json(UpdateDocument(current: current, latest: release.version, available: available, page: release.page))
            } else {
                print(available
                    ? "Switchr \(release.version) is available (you have \(current)). Run `switchr update` to install it."
                    : "Switchr \(current) is the latest version.")
            }
            return
        }
        #if os(macOS)
        print("Switchr \(release.version) is available. The menu bar app installs it automatically, or click the version number in its menu.")
        #else
        #if os(Windows)
        if let path = Bundle.main.executableURL?.path.lowercased(), path.contains("\\scoop\\apps\\") || path.contains("/scoop/apps/") {
            throw SwitchrError("Switchr was installed with Scoop, so update it there: scoop update switchr")
        }
        let how = try await WindowsInstaller.install(release, quiet: json)
        #else
        let how = try await LinuxInstaller.install(release, quiet: json)
        #endif
        if json {
            try Output.json(UpdateDocument(current: release.version, latest: release.version, available: false, page: release.page))
        } else {
            print("Installed Switchr \(release.version) \(how).")
        }
        #endif
    }

    static func dashboard(_ args: inout Arguments) async throws {
        let sample = args.flag("--sample")
        let noOpen = args.flag("--no-open")
        let json = args.flag("--json")
        let section = try args.option("--section") ?? "overview"
        guard Dashboard.sections.contains(section) else {
            throw UsageError("Unknown section '\(section)'. Use \(Dashboard.sections.joined(separator: ", ")).")
        }
        try args.finish()
        try await Dashboard.run(sample: sample, section: section, open: !noOpen, json: json)
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
        // It lists account emails, so it gets the same private permissions as everything else Switchr writes.
        try Files.writeAtomically(Data(page.utf8), to: file)
        print(file.path)
        if !noOpen, !Desktop.open(file.absoluteString) {
            Output.error("Couldn't open a browser. Open \(file.path) yourself.")
        }
    }

    static func doctor(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        try args.finish()
        let document = await doctorDocument(sample: false)
        if json { try Output.json(document) } else { print(Reports.doctor(document)) }
    }

    /// What Switchr can see on this computer. Sample data reads no logins.
    static func doctorDocument(sample: Bool) async -> DoctorDocument {
        var tools: [DoctorDocument.Tool] = []
        let sampleEmails: [Provider: String] = [.claude: "me@personal.dev", .cursor: "me@personal.dev", .codex: "me@personal.dev"]
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
            }
            tools.append(DoctorDocument.Tool(id: provider.rawValue, name: provider.name, installed: sample || ToolDetection.installed(provider),
                                             signedInAs: email, problem: problem, loginLocation: ToolDetection.loginLocation(provider)))
        }
        return DoctorDocument(
            version: AppVersion.current,
            platform: Platform.name,
            dataDirectory: Platform.dataDirectory.path,
            secretStore: sample ? "sample data" : Vault().storeName,
            savedAccounts: sample ? SampleData.accounts().count : AccountService.loadAccounts(from: Platform.dataDirectory).count,
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
            print("This removes every saved login, your usage history and Switchr's settings. Your tools stay signed in.")
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
            throw UsageError("Unknown tool '\(word)'. Use claude, cursor or codex.")
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
            throw UsageError("No saved account matches '\(reference)'. Run `switchr status` to see them.")
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

/// What's installed and where each tool keeps its login, for `switchr doctor`.
enum ToolDetection {
    static func installed(_ provider: Provider) -> Bool {
        switch provider {
        case .claude:
            return Shell.which("claude") != nil || FileManager.default.fileExists(atPath: Files.home.appendingPathComponent(".claude").path)
        case .cursor:
            return CursorApp.isInstalled
        case .codex:
            return Shell.which("codex") != nil || FileManager.default.fileExists(atPath: Files.home.appendingPathComponent(".codex").path)
        }
    }

    static func loginLocation(_ provider: Provider) -> String {
        switch provider {
        case .claude:
            #if os(macOS)
            return "Keychain item \"Claude Code-credentials\""
            #else
            return ClaudeAdapter.credentialsFile.path
            #endif
        case .cursor:
            return CursorAdapter.databaseURL.path
        case .codex:
            let base = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? Files.home.appendingPathComponent(".codex").path
            return base + "/auth.json"
        }
    }

    static var trayInstalled: Bool {
        #if os(macOS)
        return Bundle.main.bundlePath.hasSuffix(".app")
        #elseif os(Windows)
        return Bundle.main.executableURL.map {
            FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().appendingPathComponent("switchr-tray.exe").path)
        } ?? false
        #else
        return Shell.which("switchr-tray") != nil
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

/// Removes everything Switchr stores. The tools' own current logins stay as they are.
enum ResetAll {
    static func run() async -> String {
        let directory = Platform.dataDirectory
        let accounts = AccountService.loadAccounts(from: directory)
        let vault = Vault()
        for account in accounts {
            await vault.delete(account.id)
        }
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
            _ = try? Shell.run(reg, ["delete", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", "Switchr", "/f"])
            _ = try? Shell.run(reg, ["delete", "HKCU\\Software\\Switchr", "/f"])
        }
        #else
        try? FileManager.default.removeItem(at: Platform.configDirectory.appendingPathComponent("switchr"))
        try? FileManager.default.removeItem(at: Platform.configDirectory.appendingPathComponent("autostart/dev.switchr.Switchr.desktop"))
        #endif
        return "Removed \(accounts.count) saved login\(accounts.count == 1 ? "" : "s"), usage history and settings."
    }
}

#if os(Windows)
/// Installs a release over this copy. Windows won't overwrite a running program, but it will
/// rename one, so the files in use step aside first and are deleted on a later run.
enum WindowsInstaller {
    private static let leftoverMarker = ".switchr-old-"

    static func install(_ release: ReleaseInfo, quiet: Bool) async throws -> String {
        let native = ProcessInfo.processInfo.environment["PROCESSOR_ARCHITECTURE"]?.uppercased() == "ARM64" ? "arm64" : "x86_64"
        let names = ["switchr-\(release.version)-windows-\(native).zip", "switchr-\(release.version)-windows-x86_64.zip"]
        guard let sumsURL = release.assets["SHA256SUMS"] else {
            throw SwitchrError("This release has no checksum file, so Switchr won't install it.")
        }
        guard let name = names.first(where: { release.assets[$0] != nil }), let url = release.assets[name] else {
            throw SwitchrError("Release \(release.version) has no Windows download.")
        }
        let sums = String(decoding: try await Releases.download(sumsURL), as: UTF8.self)
        guard let expected = Releases.expectedHash(in: sums, for: name) else {
            throw SwitchrError("\(name) isn't in the release checksums, so Switchr won't install it.")
        }
        if !quiet { print("Downloading \(name)…") }
        let data = try await Releases.download(url)
        guard try Releases.sha256(data) == expected else {
            throw SwitchrError("The download didn't match the release checksum, so nothing was installed.")
        }
        guard let destination = Bundle.main.executableURL?.deletingLastPathComponent() else {
            throw SwitchrError("Couldn't tell where Switchr is installed.")
        }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("switchr-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let archive = work.appendingPathComponent(name)
        try data.write(to: archive)
        // Windows 10 and 11 ship bsdtar, which reads zip files.
        guard let tar = Shell.which("tar.exe") else { throw SwitchrError("tar.exe isn't available to unpack the update.") }
        let unpack = try Shell.run(tar, ["-xf", archive.path, "-C", work.path])
        guard unpack.status == 0 else { throw SwitchrError("Couldn't unpack \(name): \(unpack.stderr)") }
        let source = work.appendingPathComponent("switchr-\(release.version)")

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
/// Installs a release over this copy: the RPM through dnf when Switchr came from an RPM,
/// otherwise the tarball into ~/.local. Nothing installs unless its checksum matches.
enum LinuxInstaller {
    static func install(_ release: ReleaseInfo, quiet: Bool) async throws -> String {
        let arch = try architecture()
        guard let sumsURL = release.assets["SHA256SUMS"] else {
            throw SwitchrError("This release has no checksum file, so Switchr won't install it.")
        }
        let sums = String(decoding: try await Releases.download(sumsURL), as: UTF8.self)
        let manager = PackageManager.owning()
        let name: String
        switch manager {
        case .rpm: name = "switchr-\(release.version)-1.\(arch).rpm"
        case .deb: name = "switchr_\(release.version)_\(arch == "x86_64" ? "amd64" : "arm64").deb"
        case .pacman: name = "switchr-\(release.version)-1-\(arch).pkg.tar.zst"
        case nil: name = "switchr-\(release.version)-linux-\(arch).tar.gz"
        }
        guard let url = release.assets[name], let expected = Releases.expectedHash(in: sums, for: name) else {
            throw SwitchrError("Release \(release.version) has no \(name) for this computer.")
        }
        if !quiet { print("Downloading \(name)…") }
        let data = try await Releases.download(url)
        guard try Releases.sha256(data) == expected else {
            throw SwitchrError("The download didn't match the release checksum, so nothing was installed.")
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("switchr-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appendingPathComponent(name)
        try data.write(to: file)

        if let manager {
            guard let command = manager.installCommand(for: file.path) else {
                throw SwitchrError("\(manager.tool) isn't available. Install \(file.path) with your package manager.")
            }
            let status: Int32
            if Output.isTerminal, Terminal.inputIsInteractive, let sudo = Shell.which("sudo") {
                status = try Shell.runInteractive(sudo, command)
            } else if let pkexec = Shell.which("pkexec") {
                // pkexec shows the desktop's own password dialog, for updates started from the tray.
                status = try Shell.run(pkexec, command).status
            } else {
                throw SwitchrError("Couldn't ask for administrator rights. Run: sudo \(command.joined(separator: " "))")
            }
            guard status == 0 else { throw SwitchrError("\(manager.tool) didn't install the update (exit \(status)).") }
            return "with \(manager.tool)"
        }

        guard let tar = Shell.which("tar") else { throw SwitchrError("tar isn't installed.") }
        let unpack = try Shell.run(tar, ["-xzf", file.path, "-C", work.path])
        guard unpack.status == 0 else { throw SwitchrError("Couldn't unpack \(name).") }
        let installer = work.appendingPathComponent("switchr-\(release.version)/install-local.sh")
        let result = try Shell.run("/bin/sh", [installer.path])
        guard result.status == 0 else { throw SwitchrError("The installer failed: \(result.stderr)") }
        return "into ~/.local"
    }

    static func architecture() throws -> String {
        let result = try Shell.run(Shell.which("uname") ?? "/bin/uname", ["-m"])
        let machine = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["x86_64", "aarch64"].contains(machine) else {
            throw SwitchrError("Switchr releases are built for x86_64 and aarch64, not \(machine).")
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
