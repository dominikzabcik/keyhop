import Foundation

/// Owns the usage database: reads logs into it, records which account was in use when, and
/// answers the questions the menu and the Insights window ask.
actor TrackerEngine {
    private let db: Database

    private let directory: URL

    init(url: URL) throws {
        db = try Database(url: url)
        directory = url.deletingLastPathComponent()
        try db.script(Self.schema)
        try Self.addProjects(to: db)
        try Self.addOrigin(to: db)
        PriceCatalog.load(from: directory)
    }

    /// Reads models.dev when the saved prices are a day old, then prices whatever was stored at
    /// nothing because its model had no price yet. Returns how many records gained a price.
    @discardableResult
    func refreshPrices(now: Date = Date()) async -> Int {
        await PriceCatalog.refreshIfStale(in: directory, now: now)
        return (try? priceUnpriced()) ?? 0
    }

    /// Records stored at no cost that now have a price get one, at the same rates `Pricing.cost`
    /// uses. Anything that already has a cost keeps it: history is valued at the price it was
    /// read with, and a tool's own reported cost is never replaced.
    func priceUnpriced() throws -> Int {
        var models: [String] = []
        try db.query("""
            SELECT DISTINCT model FROM events
            WHERE cost = 0 AND (input + cache_write + cache_write_1h + cache_read + output) > 0
            """) { row in if let model = row.text(0) { models.append(model) } }
        var priced = 0
        for model in models {
            guard let price = Pricing.price(for: model) else { continue }
            let cacheWrite = price.cacheWrite ?? price.input * 1.25
            try db.execute("""
                UPDATE events SET cost = (input * ?1 + cache_write * ?2 + cache_write_1h * ?3 + cache_read * ?4 + output * ?5) / 1000000.0
                WHERE model = ?6 AND cost = 0 AND (input + cache_write + cache_write_1h + cache_read + output) > 0
                """, [.real(price.input), .real(cacheWrite), .real(price.input * 2), .real(price.cacheRead ?? price.input),
                      .real(price.output), .text(model)])
            priced += db.changes
        }
        return priced
    }

    /// A database made before projects existed gets the column, and its logs are read again once so
    /// the history already stored is filed under projects too. Reading again can't count anything
    /// twice: every record keeps its key, and the second read only fills in the project.
    private static func addProjects(to db: Database) throws {
        var present = false
        try db.query("PRAGMA table_info(events)") { row in
            if row.text(1) == "project" { present = true }
        }
        guard !present else { return }
        try db.script("""
            ALTER TABLE events ADD COLUMN project TEXT;
            CREATE INDEX IF NOT EXISTS events_by_project ON events (project, ts);
            DELETE FROM sources;
            """)
    }

    private static func addOrigin(to db: Database) throws {
        var present = false
        try db.query("PRAGMA table_info(events)") { row in
            if row.text(1) == "origin" { present = true }
        }
        guard !present else { return }
        try db.script("ALTER TABLE events ADD COLUMN origin TEXT;")
    }

    /// `origin` is NULL for everything this machine read itself, and the sending machine's name
    /// on rows that arrived through the merge folder. Only NULL rows are exported, so merged
    /// usage can never bounce between machines.
    private static let schema = """
    CREATE TABLE IF NOT EXISTS events (
        key TEXT PRIMARY KEY,
        provider TEXT NOT NULL,
        account TEXT,
        session TEXT,
        kind TEXT NOT NULL,
        ts REAL NOT NULL,
        model TEXT NOT NULL,
        input INTEGER NOT NULL,
        cache_write INTEGER NOT NULL,
        cache_write_1h INTEGER NOT NULL,
        cache_read INTEGER NOT NULL,
        output INTEGER NOT NULL,
        reasoning INTEGER NOT NULL,
        cost REAL NOT NULL,
        billed REAL,
        origin TEXT
    );
    CREATE INDEX IF NOT EXISTS events_by_time ON events (ts, provider);
    CREATE INDEX IF NOT EXISTS events_by_session ON events (kind, session);
    CREATE TABLE IF NOT EXISTS sources (path TEXT PRIMARY KEY, size INTEGER NOT NULL, offset INTEGER NOT NULL, state TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS periods (provider TEXT NOT NULL, account TEXT, since REAL NOT NULL, PRIMARY KEY (provider, since));
    CREATE TABLE IF NOT EXISTS samples (account TEXT NOT NULL, label TEXT NOT NULL, used REAL NOT NULL, resets REAL, ts REAL NOT NULL);
    CREATE INDEX IF NOT EXISTS samples_by_window ON samples (account, label, ts);
    CREATE TABLE IF NOT EXISTS budgets (scope TEXT PRIMARY KEY, amount REAL NOT NULL, period TEXT NOT NULL);
    """

    // MARK: Ingest

    @discardableResult
    func ingestLocalLogs(progress: ProgressHandler? = nil) throws -> Int {
        var files: [(url: URL, feed: LogFeed, size: Int64)] = []
        for feed in LogFeed.all {
            for root in feed.roots() where FileManager.default.fileExists(atPath: root.path) {
                let found = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
                while let url = found?.nextObject() as? URL {
                    guard url.pathExtension == "jsonl" else { continue }
                    let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                    files.append((url, feed, size))
                }
            }
        }

        // What is left to read, so the first read of a long history can say how far it has got.
        var total: Int64 = 0
        if progress != nil {
            var offsets: [String: Int64] = [:]
            try db.query("SELECT path, offset FROM sources") { row in
                if let path = row.text(0) { offsets[path] = row.int(1) }
            }
            for file in files {
                let offset = offsets[file.url.path] ?? 0
                total += file.size < offset ? file.size : file.size - offset
            }
        }
        var done: Int64 = 0
        var reported = -1
        func report(_ bytes: Int64, force: Bool = false) {
            guard let progress else { return }
            done += bytes
            // Whole percents are plenty for a bar, and keep a big read from reporting per chunk.
            let percent = total > 0 ? Int(done * 100 / total) : 100
            guard force || percent != reported else { return }
            reported = percent
            progress(WorkProgress(step: .history, done: Int(min(done, total) / 1024), total: Int(total / 1024)))
        }
        report(0, force: true)

        var added = 0
        for file in files {
            added += try ingest(file.url, feed: file.feed, size: file.size) { report($0) }
        }
        added += try ingestOpenCode()
        if progress != nil {
            done = total
            report(0, force: true)
        }
        return added
    }

    /// OpenCode stores messages in SQLite instead of JSONL. The source row reuses `offset` as a
    /// millisecond `time_updated` watermark; querying `>=` plus event primary keys makes equal-time
    /// writes safe and idempotent.
    private func ingestOpenCode() throws -> Int {
        let url = OpenCodeAdapter.databaseURL
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        var previousSize: Int64 = 0
        var watermark: Int64 = 0
        try db.query("SELECT size, offset FROM sources WHERE path = ?", [.text(url.path)]) { row in
            previousSize = row.int(0)
            watermark = row.int(1)
        }
        if size < previousSize { watermark = 0 }
        let result = try OpenCodeFeed.records(databaseURL: url, since: watermark)
        try db.transaction {
            for record in result.records { try insert(record) }
            try db.execute("INSERT OR REPLACE INTO sources (path, size, offset, state) VALUES (?, ?, ?, ?)",
                           [.text(url.path), .int(size), .int(result.watermark), .text("{}")])
        }
        return result.records.count
    }

    func store(_ records: [UsageRecord]) throws {
        try db.transaction {
            for record in records { try insert(record) }
        }
    }

    /// Reads only what was appended since the last pass, and only whole lines.
    private func ingest(_ url: URL, feed: LogFeed, size: Int64, read: (Int64) -> Void = { _ in }) throws -> Int {
        var offset: Int64 = 0
        var state: [String: String] = [:]
        try db.query("SELECT offset, state FROM sources WHERE path = ?", [.text(url.path)]) { row in
            offset = row.int(0)
            state = row.text(1).flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } ?? [:]
        }
        if size < offset {
            // The file was replaced or truncated.
            offset = 0
            state = [:]
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))

        var records: [UsageRecord] = []
        var pending = Data()
        var consumed = offset
        var finished = false
        while !finished {
            // File reads and decoded JSON are autoreleased; draining the pool per chunk keeps a
            // first read of a large history from holding every chunk until the file ends.
            try autoreleasepool {
                guard let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty else {
                    finished = true
                    return
                }
                pending.append(chunk)
                read(Int64(chunk.count))
                var lineStart = pending.startIndex
                while let newline = pending[lineStart...].firstIndex(of: 0x0A) {
                    let line = pending[lineStart..<newline]
                    lineStart = newline + 1
                    guard feed.markers.contains(where: { line.range(of: $0) != nil }),
                          let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
                    records.append(contentsOf: feed.parse(object, url, &state))
                }
                consumed += Int64(lineStart - pending.startIndex)
                pending = Data(pending[lineStart...])
            }
        }

        let stateJSON = (try? JSONEncoder().encode(state)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        try db.transaction {
            for record in records { try insert(record) }
            try db.execute("INSERT OR REPLACE INTO sources (path, size, offset, state) VALUES (?, ?, ?, ?)",
                           [.text(url.path), .int(size), .int(consumed), .text(stateJSON)])
        }
        return records.count
    }

    private func insert(_ record: UsageRecord) throws {
        let t = record.tokens
        // A record seen before keeps everything it had. The one thing a later read can add is the
        // project, for history stored before projects were recorded.
        try db.execute("""
            INSERT INTO events
                (key, provider, account, session, kind, ts, model, input, cache_write, cache_write_1h, cache_read, output, reasoning, cost, billed, project)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET project = excluded.project
            WHERE events.project IS NULL AND excluded.project IS NOT NULL
            """, [
                .text(record.key), .text(record.provider.rawValue), .text(record.account?.uuidString), .text(record.session),
                .text(record.kind.rawValue), .real(record.timestamp.timeIntervalSince1970), .text(record.model),
                .int(Int64(t.input)), .int(Int64(t.cacheWrite)), .int(Int64(t.cacheWrite1h)), .int(Int64(t.cacheRead)),
                .int(Int64(t.output)), .int(Int64(t.reasoning)), .real(record.cost), record.billed.map(SQL.real) ?? .null,
                .text(record.project),
            ])
    }

    // MARK: Merge folder

    struct MergeBatch {
        let lines: [String]
        let lastRow: Int64
    }

    /// Rows this machine read itself, after `row`, as JSON lines. The account is resolved the
    /// same way reports resolve it and written as the account's identity, so another machine
    /// can match it to its own saved account for the same login.
    func exportMergeEvents(after row: Int64, identities: [String: String], limit: Int = 20000) throws -> MergeBatch {
        var lines: [String] = []
        var lastRow = row
        try db.query("""
            SELECT e.rowid, e.key, e.provider, \(Self.accountColumn), e.session, e.kind, e.ts, e.model,
                   e.input, e.cache_write, e.cache_write_1h, e.cache_read, e.output, e.reasoning,
                   e.cost, e.billed, e.project
            FROM events e
            WHERE e.origin IS NULL AND e.rowid > ?
            ORDER BY e.rowid
            LIMIT ?
            """, [.int(row), .int(Int64(limit))]) { row in
            lastRow = row.int(0)
            var object: [String: Any] = [
                "key": row.text(1) ?? "",
                "provider": row.text(2) ?? "",
                "kind": row.text(5) ?? "",
                "ts": row.double(6),
                "model": row.text(7) ?? "",
                "input": row.int(8), "cacheWrite": row.int(9), "cacheWrite1h": row.int(10),
                "cacheRead": row.int(11), "output": row.int(12), "reasoning": row.int(13),
                "cost": row.double(14),
            ]
            if let account = row.text(3), let identity = identities[account] { object["account"] = identity }
            if let session = row.text(4) { object["session"] = session }
            if !row.isNull(15) { object["billed"] = row.double(15) }
            if let project = row.text(16) { object["project"] = project }
            if let line = try? JSON.string(object) { lines.append(line) }
        }
        return MergeBatch(lines: lines, lastRow: lastRow)
    }

    /// Stores lines another machine exported. The provider string is kept as written, so usage
    /// from a tool this build doesn't know yet survives until an update can read it. A key seen
    /// before keeps what it has: this machine's own reading always wins.
    @discardableResult
    func importMergeLines<S: Sequence>(_ lines: S, origin: String, accountsByIdentity: [String: String]) throws -> Int where S.Element: StringProtocol {
        var imported = 0
        try db.transaction {
            for line in lines {
                guard let object = JSON.object(String(line)),
                      let key = object["key"] as? String, !key.isEmpty,
                      let provider = object["provider"] as? String, !provider.isEmpty,
                      let kind = object["kind"] as? String,
                      let ts = JSON.number(object["ts"]),
                      let model = object["model"] as? String else { continue }
                func count(_ name: String) -> Int64 { Int64(JSON.number(object[name]) ?? 0) }
                let identity = object["account"] as? String
                let account = identity.flatMap { accountsByIdentity["\(provider)|\($0)"] }
                try db.execute("""
                    INSERT INTO events
                        (key, provider, account, session, kind, ts, model, input, cache_write, cache_write_1h,
                         cache_read, output, reasoning, cost, billed, project, origin)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(key) DO NOTHING
                    """, [
                        .text(key), .text(provider), .text(account), .text(object["session"] as? String),
                        .text(kind), .real(ts), .text(model),
                        .int(count("input")), .int(count("cacheWrite")), .int(count("cacheWrite1h")),
                        .int(count("cacheRead")), .int(count("output")), .int(count("reasoning")),
                        .real(JSON.number(object["cost"]) ?? 0),
                        JSON.number(object["billed"]).map(SQL.real) ?? .null,
                        .text(object["project"] as? String), .text(origin),
                    ])
                imported += db.changes
            }
        }
        return imported
    }

    /// The read position of a merge file, shared with the log readers' bookkeeping.
    func sourceMark(_ path: String) throws -> (size: Int64, offset: Int64)? {
        var mark: (Int64, Int64)?
        try db.query("SELECT size, offset FROM sources WHERE path = ?", [.text(path)]) { row in
            mark = (row.int(0), row.int(1))
        }
        return mark
    }

    func setSourceMark(_ path: String, size: Int64, offset: Int64) throws {
        try db.execute("INSERT OR REPLACE INTO sources (path, size, offset, state) VALUES (?, ?, ?, '{}')",
                       [.text(path), .int(size), .int(offset)])
    }

    // MARK: Accounts over time

    /// Records the account in use from now on, if it changed.
    func noteActive(_ provider: Provider, account: UUID?, at date: Date) throws {
        var found = false
        var latest: String?
        try db.query("SELECT account FROM periods WHERE provider = ? ORDER BY since DESC LIMIT 1", [.text(provider.rawValue)]) { row in
            found = true
            latest = row.text(0)
        }
        let value = account?.uuidString
        if found ? latest == value : value == nil { return }
        try db.execute("INSERT OR REPLACE INTO periods (provider, account, since) VALUES (?, ?, ?)",
                       [.text(provider.rawValue), .text(value), .real(date.timeIntervalSince1970)])
    }

    // MARK: Limit samples and forecasts

    func addSamples(account: UUID, windows: [UsageWindow], at date: Date) throws {
        let ts = date.timeIntervalSince1970
        try db.transaction {
            for window in windows {
                var seen = false
                try db.query("SELECT 1 FROM samples WHERE account = ? AND label = ? AND ts = ?",
                             [.text(account.uuidString), .text(window.label), .real(ts)]) { _ in seen = true }
                if seen { continue }
                try db.execute("INSERT INTO samples (account, label, used, resets, ts) VALUES (?, ?, ?, ?, ?)",
                               [.text(account.uuidString), .text(window.label), .real(window.usedPercent),
                                window.resetsAt.map { .real($0.timeIntervalSince1970) } ?? .null, .real(ts)])
            }
            try db.execute("DELETE FROM samples WHERE ts < ?", [.real(ts - 8 * 86400)])
        }
    }

    private struct Sample {
        let time: Double
        let used: Double
    }

    /// When the window reaches 100% at its rate over the last 90 minutes, if that's before it resets.
    func forecast(account: UUID, window: UsageWindow, now: Date) throws -> Date? {
        guard window.usedPercent < 100 else { return nil }
        var samples: [Sample] = []
        try db.query("SELECT ts, used FROM samples WHERE account = ? AND label = ? AND ts >= ? ORDER BY ts",
                     [.text(account.uuidString), .text(window.label), .real(now.timeIntervalSince1970 - 90 * 60)]) { row in
            samples.append(Sample(time: row.double(0), used: row.double(1)))
        }
        // A drop means the window reset; only the stretch since then says anything about the rate.
        if let reset = samples.indices.last(where: { $0 > 0 && samples[$0].used < samples[$0 - 1].used - 1 }) {
            samples.removeFirst(reset)
        }
        guard samples.count >= 3, let first = samples.first, let last = samples.last, last.time - first.time >= 15 * 60 else { return nil }

        // Least-squares slope, in percent per second.
        let n = Double(samples.count)
        let meanTime = samples.reduce(0) { $0 + $1.time } / n
        let meanUsed = samples.reduce(0) { $0 + $1.used } / n
        let covariance = samples.reduce(0) { $0 + ($1.time - meanTime) * ($1.used - meanUsed) }
        let variance = samples.reduce(0) { $0 + ($1.time - meanTime) * ($1.time - meanTime) }
        guard variance > 0 else { return nil }
        let rate = covariance / variance
        guard rate > 0 else { return nil }

        let eta = now.addingTimeInterval((100 - window.usedPercent) / rate)
        if let resetsAt = window.resetsAt, eta >= resetsAt { return nil }
        return eta
    }

    // MARK: Budgets

    func budgets() throws -> [Budget] {
        var budgets: [Budget] = []
        try db.query("SELECT scope, amount, period FROM budgets ORDER BY scope") { row in
            guard let scope = row.text(0), let period = row.text(2).flatMap(BudgetPeriod.init(rawValue:)) else { return }
            budgets.append(Budget(scope: scope, amount: row.double(1), period: period))
        }
        return budgets
    }

    /// What a budget counts: what the provider actually charged where it reports that, and the value
    /// of the tokens at standard API prices everywhere else. Cursor's on-demand usage is the first
    /// kind, and counting it at API prices would let real money go by unnoticed.
    static func charged(_ totals: Totals) -> Double {
        max(totals.billed, totals.cost)
    }

    /// What each budget has used so far in its current period.
    func budgetSpend(for budgets: [Budget], now: Date, sole: [Provider: UUID]) throws -> [String: Double] {
        var spend: [String: Double] = [:]
        for period in Set(budgets.map(\.period)) {
            let totals = try accountTotals(in: period.interval(containing: now), sole: sole)
            for budget in budgets where budget.period == period {
                spend[budget.scope] = budget.account.map { totals.byAccount[$0].map(Self.charged) ?? 0 }
                    ?? Self.charged(totals.all)
            }
        }
        return spend
    }

    func setBudget(_ budget: Budget?, scope: String) throws {
        if let budget {
            try db.execute("INSERT OR REPLACE INTO budgets (scope, amount, period) VALUES (?, ?, ?)",
                           [.text(scope), .real(budget.amount), .text(budget.period.rawValue)])
        } else {
            try db.execute("DELETE FROM budgets WHERE scope = ?", [.text(scope)])
        }
    }

    // MARK: Reports

    /// The account in use when the request happened, unless the source already named one. Rows
    /// that arrived through the merge folder never fall back to this machine's switch history:
    /// they were resolved on the machine that read them, or they stay unattributed.
    private static let accountColumn = """
        COALESCE(e.account, CASE WHEN e.origin IS NULL THEN
            (SELECT p.account FROM periods p WHERE p.provider = e.provider AND p.since <= e.ts ORDER BY p.since DESC LIMIT 1) END)
        """
    private static let sums = """
        SUM(e.input), SUM(e.cache_write), SUM(e.cache_write_1h), SUM(e.cache_read), SUM(e.output), SUM(e.reasoning),
        SUM(e.cost), SUM(COALESCE(e.billed, 0)), COUNT(*)
        """
    /// Where a Codex session has per-response records, its running totals would count everything twice.
    private static let notDoubleCounted = """
        NOT (e.kind = 'runningTotal' AND e.session IN
            (SELECT r.session FROM events r WHERE r.kind = 'request' AND r.provider = 'codex' AND r.session IS NOT NULL))
        """

    private static func totals(_ row: DBRow, from column: Int32) -> Totals {
        Totals(
            tokens: TokenCounts(input: Int(row.int(column)), cacheWrite: Int(row.int(column + 1)), cacheWrite1h: Int(row.int(column + 2)),
                                cacheRead: Int(row.int(column + 3)), output: Int(row.int(column + 4)), reasoning: Int(row.int(column + 5))),
            cost: row.double(column + 6),
            billed: row.double(column + 7),
            requests: Int(row.int(column + 8))
        )
    }

    /// Totals per account and per tool in an interval. `sole` assigns unattributed usage to a
    /// tool's only saved account. Measured-only tools never have accounts, so `byProvider` and
    /// `all` are the totals that cover everything.
    func accountTotals(in interval: DateInterval, sole: [Provider: UUID]) throws -> (byAccount: [UUID: Totals], byProvider: [Provider: Totals], all: Totals) {
        var byAccount: [UUID: Totals] = [:]
        var byProvider: [Provider: Totals] = [:]
        var all = Totals()
        try db.query("""
            SELECT e.provider, \(Self.accountColumn), \(Self.sums)
            FROM events e
            WHERE e.ts >= ? AND e.ts < ? AND \(Self.notDoubleCounted)
            GROUP BY 1, 2
            """, [.real(interval.start.timeIntervalSince1970), .real(interval.end.timeIntervalSince1970)]) { row in
            let totals = Self.totals(row, from: 2)
            all += totals
            let provider = Provider(rawValue: row.text(0) ?? "")
            if let provider { byProvider[provider, default: Totals()] += totals }
            if let id = row.text(1).flatMap({ UUID(uuidString: $0) }) ?? provider.flatMap({ sole[$0] }) {
                byAccount[id, default: Totals()] += totals
            }
        }
        return (byAccount, byProvider, all)
    }

    func digest(interval: DateInterval, previous: DateInterval, bucket: Bucket, provider: Provider?, sole: [Provider: UUID]) throws -> UsageDigest {
        var digest = UsageDigest()
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = bucket.dateFormat

        var points: [String: (start: Date, key: AccountKey, model: String, totals: Totals)] = [:]
        let providerFilter: SQL = provider.map { .text($0.rawValue) } ?? .null
        try db.query("""
            SELECT e.provider, \(Self.accountColumn), e.model, \(bucket.sqliteLabel("e.ts")), \(Self.sums)
            FROM events e
            WHERE e.ts >= ?1 AND e.ts < ?2 AND (?3 IS NULL OR e.provider = ?3) AND \(Self.notDoubleCounted)
            GROUP BY 1, 2, 3, 4
            """, [.real(interval.start.timeIntervalSince1970), .real(interval.end.timeIntervalSince1970), providerFilter]) { row in
            guard let provider = Provider(rawValue: row.text(0) ?? ""), let label = row.text(3), let start = parser.date(from: label) else { return }
            let account = row.text(1).flatMap { UUID(uuidString: $0) } ?? sole[provider]
            let key = AccountKey(provider: provider, account: account)
            let model = Pricing.normalize(row.text(2) ?? "unknown")
            let totals = Self.totals(row, from: 4)
            digest.total += totals
            digest.byAccount[key, default: Totals()] += totals
            digest.byModel[ModelKey(provider: provider, model: model), default: Totals()] += totals
            digest.byProvider[provider, default: Totals()] += totals
            let pointKey = "\(label)|\(provider.rawValue)|\(account?.uuidString ?? "-")|\(model)"
            var point = points[pointKey] ?? (start, key, model, Totals())
            point.totals += totals
            points[pointKey] = point
        }
        digest.points = points.values
            .map { UsageDigest.Point(start: $0.start, key: $0.key, model: $0.model, totals: $0.totals) }
            .sorted { $0.start < $1.start }

        try db.query("""
            SELECT COALESCE(e.project, ''), \(Self.sums) FROM events e
            WHERE e.ts >= ?1 AND e.ts < ?2 AND (?3 IS NULL OR e.provider = ?3) AND \(Self.notDoubleCounted)
            GROUP BY 1
            """, [.real(interval.start.timeIntervalSince1970), .real(interval.end.timeIntervalSince1970), providerFilter]) { row in
            digest.byProject[row.text(0) ?? "", default: Totals()] += Self.totals(row, from: 1)
        }

        try db.query("""
            SELECT \(Self.sums) FROM events e
            WHERE e.ts >= ?1 AND e.ts < ?2 AND (?3 IS NULL OR e.provider = ?3) AND \(Self.notDoubleCounted)
            """, [.real(previous.start.timeIntervalSince1970), .real(previous.end.timeIntervalSince1970), providerFilter]) { row in
            digest.previous = Self.totals(row, from: 0)
        }
        return digest
    }

    /// Named sessions in the range, newest last activity first. Requests the tool never labelled
    /// as a session are left out, so the list is conversations rather than every single response.
    /// When the first usage Keyhop has on record happened, for everything since the start.
    func firstUse(provider: Provider?) throws -> Date? {
        var first: Date?
        try db.query("SELECT MIN(ts) FROM events WHERE (?1 IS NULL OR provider = ?1)",
                     [provider.map { .text($0.rawValue) } ?? .null]) { row in
            if !row.isNull(0) { first = Date(timeIntervalSince1970: row.double(0)) }
        }
        return first
    }

    func sessions(in interval: DateInterval, provider: Provider?, sole: [Provider: UUID], limit: Int = 40) throws -> [UsageDigest.Session] {
        var sessions: [UsageDigest.Session] = []
        let providerFilter: SQL = provider.map { .text($0.rawValue) } ?? .null
        try db.query("""
            SELECT e.session, e.provider, \(Self.accountColumn), e.model, MIN(e.ts), MAX(e.ts), \(Self.sums)
            FROM events e
            WHERE e.ts >= ?1 AND e.ts < ?2 AND (?3 IS NULL OR e.provider = ?3)
              AND e.session IS NOT NULL AND e.session != ''
              AND \(Self.notDoubleCounted)
            GROUP BY 1, 2, 3, 4
            ORDER BY MAX(e.ts) DESC
            LIMIT ?4
            """, [
                .real(interval.start.timeIntervalSince1970), .real(interval.end.timeIntervalSince1970),
                providerFilter, .int(Int64(limit)),
            ]) { row in
            guard let id = row.text(0), let provider = Provider(rawValue: row.text(1) ?? "") else { return }
            sessions.append(UsageDigest.Session(
                id: id,
                provider: provider,
                account: row.text(2).flatMap { UUID(uuidString: $0) } ?? sole[provider],
                model: Pricing.normalize(row.text(3) ?? "unknown"),
                from: Date(timeIntervalSince1970: row.double(4)),
                to: Date(timeIntervalSince1970: row.double(5)),
                totals: Self.totals(row, from: 6)
            ))
        }
        return sessions
    }
}
