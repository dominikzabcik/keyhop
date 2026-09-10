import Foundation

/// Owns the usage database: reads logs into it, records which account was in use when, and
/// answers the questions the menu and the Insights window ask.
actor TrackerEngine {
    private let db: Database

    init(url: URL) throws {
        db = try Database(url: url)
        try db.script(Self.schema)
    }

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
        billed REAL
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
    func ingestLocalLogs() throws -> Int {
        var added = 0
        for feed in LogFeed.all {
            for root in feed.roots where FileManager.default.fileExists(atPath: root.path) {
                let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
                while let url = files?.nextObject() as? URL {
                    guard url.pathExtension == "jsonl" else { continue }
                    added += try ingest(url, feed: feed)
                }
            }
        }
        return added
    }

    func store(_ records: [UsageRecord]) throws {
        try db.transaction {
            for record in records { try insert(record) }
        }
    }

    /// Reads only what was appended since the last pass, and only whole lines.
    private func ingest(_ url: URL, feed: LogFeed) throws -> Int {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
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
                var lineStart = pending.startIndex
                while let newline = pending[lineStart...].firstIndex(of: 0x0A) {
                    let line = pending[lineStart..<newline]
                    lineStart = newline + 1
                    guard feed.markers.contains(where: { line.range(of: $0) != nil }),
                          let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                          let record = feed.parse(object, url, &state) else { continue }
                    records.append(record)
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
        try db.execute("""
            INSERT OR IGNORE INTO events
                (key, provider, account, session, kind, ts, model, input, cache_write, cache_write_1h, cache_read, output, reasoning, cost, billed)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(record.key), .text(record.provider.rawValue), .text(record.account?.uuidString), .text(record.session),
                .text(record.kind.rawValue), .real(record.timestamp.timeIntervalSince1970), .text(record.model),
                .int(Int64(t.input)), .int(Int64(t.cacheWrite)), .int(Int64(t.cacheWrite1h)), .int(Int64(t.cacheRead)),
                .int(Int64(t.output)), .int(Int64(t.reasoning)), .real(record.cost), record.billed.map(SQL.real) ?? .null,
            ])
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

    /// What each budget has used so far in its current period.
    func budgetSpend(for budgets: [Budget], now: Date, sole: [Provider: UUID]) throws -> [String: Double] {
        var spend: [String: Double] = [:]
        for period in Set(budgets.map(\.period)) {
            let totals = try accountTotals(in: period.interval(containing: now), sole: sole)
            for budget in budgets where budget.period == period {
                spend[budget.scope] = budget.account.map { totals.byAccount[$0]?.cost ?? 0 } ?? totals.all.cost
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

    /// The account in use when the request happened, unless the source already named one.
    private static let accountColumn = """
        COALESCE(e.account, (SELECT p.account FROM periods p WHERE p.provider = e.provider AND p.since <= e.ts ORDER BY p.since DESC LIMIT 1))
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

    /// Totals per account in an interval. `sole` assigns unattributed usage to a tool's only saved account.
    func accountTotals(in interval: DateInterval, sole: [Provider: UUID]) throws -> (byAccount: [UUID: Totals], all: Totals) {
        var byAccount: [UUID: Totals] = [:]
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
            if let id = row.text(1).flatMap({ UUID(uuidString: $0) }) ?? provider.flatMap({ sole[$0] }) {
                byAccount[id, default: Totals()] += totals
            }
        }
        return (byAccount, all)
    }

    func digest(interval: DateInterval, previous: DateInterval, bucket: Bucket, provider: Provider?, sole: [Provider: UUID]) throws -> UsageDigest {
        var digest = UsageDigest()
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = bucket.dateFormat

        var points: [String: (start: Date, key: AccountKey, totals: Totals)] = [:]
        let providerFilter: SQL = provider.map { .text($0.rawValue) } ?? .null
        try db.query("""
            SELECT e.provider, \(Self.accountColumn), e.model, strftime(?1, e.ts, 'unixepoch', 'localtime'), \(Self.sums)
            FROM events e
            WHERE e.ts >= ?2 AND e.ts < ?3 AND (?4 IS NULL OR e.provider = ?4) AND \(Self.notDoubleCounted)
            GROUP BY 1, 2, 3, 4
            """, [.text(bucket.sqliteFormat), .real(interval.start.timeIntervalSince1970), .real(interval.end.timeIntervalSince1970), providerFilter]) { row in
            guard let provider = Provider(rawValue: row.text(0) ?? ""), let label = row.text(3), let start = parser.date(from: label) else { return }
            let account = row.text(1).flatMap { UUID(uuidString: $0) } ?? sole[provider]
            let key = AccountKey(provider: provider, account: account)
            let totals = Self.totals(row, from: 4)
            digest.total += totals
            digest.byAccount[key, default: Totals()] += totals
            digest.byModel[Pricing.normalize(row.text(2) ?? "unknown"), default: Totals()] += totals
            let pointKey = "\(label)|\(provider.rawValue)|\(account?.uuidString ?? "-")"
            var point = points[pointKey] ?? (start, key, Totals())
            point.totals += totals
            points[pointKey] = point
        }
        digest.points = points.values
            .map { UsageDigest.Point(start: $0.start, key: $0.key, totals: $0.totals) }
            .sorted { $0.start < $1.start }

        try db.query("""
            SELECT \(Self.sums) FROM events e
            WHERE e.ts >= ?1 AND e.ts < ?2 AND (?3 IS NULL OR e.provider = ?3) AND \(Self.notDoubleCounted)
            """, [.real(previous.start.timeIntervalSince1970), .real(previous.end.timeIntervalSince1970), providerFilter]) { row in
            digest.previous = Self.totals(row, from: 0)
        }
        return digest
    }
}
