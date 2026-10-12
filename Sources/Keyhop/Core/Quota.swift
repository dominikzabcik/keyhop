import Foundation

/// One reading of a limit window, as the tracker keeps them for eight days.
struct LimitSample: Equatable {
    let account: UUID
    let label: String
    let used: Double
    let resets: Date?
    let ts: Date
}

/// A saved login and the last limits Keyhop read for it.
struct QuotaInput {
    let account: Account
    let snapshot: UsageSnapshot?
    let active: Bool

    static func list(accounts: [Account], usage: [UUID: UsageSnapshot], active: [Provider: UUID]) -> [QuotaInput] {
        accounts.map { QuotaInput(account: $0, snapshot: usage[$0.id], active: active[$0.provider] == $0.id) }
    }
}

/// Every login's remaining limit pooled: what is left now, how fast it drains, where it stood over
/// the past week and where it is heading, with resets stepping it back up. Counted on this computer
/// from the last limits read and the kept samples; nothing is sent.
struct QuotaReport: Encodable {
    struct Reset: Encodable {
        let at: Date
        let gain: Double
        let account: String
        let tool: String
    }

    struct Window: Encodable {
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
        let windowSeconds: Double?
        let drainPerHour: Double
        let emptyAt: Date?

        private enum CodingKeys: String, CodingKey { case label, usedPercent, resetsAt, windowSeconds, drainPerHour, emptyAt }

        /// Unknowns are written as null rather than left out, so the window can rely on every key.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(label, forKey: .label)
            try c.encode(usedPercent, forKey: .usedPercent)
            try c.encode(resetsAt, forKey: .resetsAt)
            try c.encode(windowSeconds, forKey: .windowSeconds)
            try c.encode(drainPerHour, forKey: .drainPerHour)
            try c.encode(emptyAt, forKey: .emptyAt)
        }
    }

    struct Login: Encodable {
        let id: UUID
        let tool: Provider
        let toolName: String
        let name: String
        let email: String
        let plan: String?
        let active: Bool
        let error: String?
        /// Expired logins are listed but left out of every pool.
        let counted: Bool
        let remaining: Double
        /// The tightest window, the one that decides what is left.
        let binding: String?
        let drainPerHour: Double
        let emptyAt: Date?
        let backAt: Date?
        let lastSeen: Date?
        let windows: [Window]
        let past: [Double?]
        let forecast: [Double]

        private enum CodingKeys: String, CodingKey {
            case id, tool, toolName, name, email, plan, active, error, counted, remaining, binding, drainPerHour, emptyAt, backAt, lastSeen, windows, past, forecast
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(tool, forKey: .tool)
            try c.encode(toolName, forKey: .toolName)
            try c.encode(name, forKey: .name)
            try c.encode(email, forKey: .email)
            try c.encode(plan, forKey: .plan)
            try c.encode(active, forKey: .active)
            try c.encode(error, forKey: .error)
            try c.encode(counted, forKey: .counted)
            try c.encode(remaining, forKey: .remaining)
            try c.encode(binding, forKey: .binding)
            try c.encode(drainPerHour, forKey: .drainPerHour)
            try c.encode(emptyAt, forKey: .emptyAt)
            try c.encode(backAt, forKey: .backAt)
            try c.encode(lastSeen, forKey: .lastSeen)
            try c.encode(windows, forKey: .windows)
            try c.encode(past, forKey: .past)
            try c.encode(forecast, forKey: .forecast)
        }
    }

    struct Pool: Encodable {
        /// "all", or a tool's id.
        let tool: String
        let name: String
        let accounts: Int
        let capacity: Double
        let remaining: Double
        let drainPerHour: Double
        let emptyAt: Date?
        let nextReset: Reset?
        let past: [Double?]
        let forecast: [Double]
        /// How fast the pool drained over the past, in percent an hour per step.
        let drain: [Double?]

        private enum CodingKeys: String, CodingKey {
            case tool, name, accounts, capacity, remaining, drainPerHour, emptyAt, nextReset, past, forecast, drain
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(tool, forKey: .tool)
            try c.encode(name, forKey: .name)
            try c.encode(accounts, forKey: .accounts)
            try c.encode(capacity, forKey: .capacity)
            try c.encode(remaining, forKey: .remaining)
            try c.encode(drainPerHour, forKey: .drainPerHour)
            try c.encode(emptyAt, forKey: .emptyAt)
            try c.encode(nextReset, forKey: .nextReset)
            try c.encode(past, forKey: .past)
            try c.encode(forecast, forKey: .forecast)
            try c.encode(drain, forKey: .drain)
        }
    }

    let generatedAt: Date
    let step: Int
    let pastStart: Date
    let forecastStart: Date
    let pools: [Pool]
    let accounts: [Login]

    /// Everyday names for window labels, the same ones the window uses.
    static func windowName(_ label: String) -> String {
        ["5h": "5-hour", "Week": "Weekly", "Opus": "Opus weekly", "Sonnet": "Sonnet weekly"][label] ?? label
    }

    /// How long a window lasts when the provider doesn't say, from its label.
    static func period(label: String) -> TimeInterval? {
        switch label {
        case "5h": 5 * 3600
        case "Day": 86400
        case "Week", "Opus", "Sonnet": 7 * 86400
        default: nil
        }
    }

    // MARK: Building

    /// One window projected forward: its rate now for the first three hours, its usual rate after,
    /// back to zero at each reset.
    private struct Projection {
        let label: String
        let used: Double
        let resetsAt: Date?
        let windowSeconds: TimeInterval?
        let period: TimeInterval?
        let rateNow: Double
        let rateTypical: Double
        let now: Date

        var switchAt: Date { now.addingTimeInterval(3 * 3600) }

        private func grow(_ used: Double, from start: Date, to end: Date) -> Double {
            guard end > start else { return used }
            var u = used
            if start < switchAt { u += rateNow * min(end, switchAt).timeIntervalSince(start) / 3600 }
            if end > switchAt { u += rateTypical * end.timeIntervalSince(max(start, switchAt)) / 3600 }
            return min(100, u)
        }

        /// Used at a time; on a reset's own instant, `after` says which side of it.
        func used(at time: Date, after: Bool = true) -> Double {
            var u = used, t = now, reset = resetsAt
            while true {
                let stop = reset.map { min($0, time) } ?? time
                u = grow(u, from: t, to: stop)
                t = max(t, stop)
                guard let r = reset, r < time || (r == time && after) else { return u }
                u = 0
                reset = period.map { r.addingTimeInterval($0) }
            }
        }

        func resets(until end: Date) -> [Date] {
            var found: [Date] = []
            var reset = resetsAt
            while let r = reset, r <= end {
                found.append(r)
                reset = period.map { r.addingTimeInterval($0) }
            }
            return found
        }

        /// The first moment the window fills, nil if it already has or never does before `end`.
        func firstFull(until end: Date) -> Date? {
            guard used < 99.5 else { return nil }
            var u = used, t = now, reset = resetsAt
            while t < end {
                var stop = end
                if let r = reset, r < stop { stop = r }
                if t < switchAt, switchAt < stop { stop = switchAt }
                let rate = t < switchAt ? rateNow : rateTypical
                if rate > 0 {
                    let full = t.addingTimeInterval((100 - u) / rate * 3600)
                    if full <= stop { return full }
                }
                u = min(100, u + rate * stop.timeIntervalSince(t) / 3600)
                t = stop
                if let r = reset, t >= r {
                    u = 0
                    reset = period.map { r.addingTimeInterval($0) }
                }
            }
            return nil
        }
    }

    private struct Member {
        let input: QuotaInput
        let counted: Bool
        let windows: [Projection]
        let remaining: Double
        let firstSample: Date?
        let lastSample: Date?
        /// Used per label at every past point, nil where the label wasn't known yet.
        let pastUsed: [String: [Double?]]
        let past: [Double?]
        let forecast: [Double]

        var tool: Provider { input.account.provider }
        var binding: Projection? { windows.max { $0.used < $1.used } }

        func remaining(at time: Date, after: Bool) -> Double {
            Self.remaining(windows, at: time, after: after)
        }

        static func remaining(_ windows: [Projection], at time: Date, after: Bool) -> Double {
            guard let used = windows.map({ $0.used(at: time, after: after) }).max() else { return 0 }
            return min(100, max(0, 100 - used))
        }
    }

    static func build(accounts inputs: [QuotaInput], samples: [LimitSample], now: Date,
                      step: TimeInterval = 1800, past: TimeInterval = 7 * 86400, ahead: TimeInterval = 7 * 86400) -> QuotaReport {
        let pastCount = Int(past / step)
        let aheadCount = Int(ahead / step)
        let pastStart = now.addingTimeInterval(-Double(pastCount) * step)
        let pastTimes = (0...pastCount).map { pastStart.addingTimeInterval(Double($0) * step) }
        let forecastTimes = (0...aheadCount).map { now.addingTimeInterval(Double($0) * step) }
        let horizon = forecastTimes.last ?? now

        var byAccount: [UUID: [String: [LimitSample]]] = [:]
        for sample in samples where sample.ts <= now { byAccount[sample.account, default: [:]][sample.label, default: []].append(sample) }
        for (id, labels) in byAccount {
            for (label, list) in labels { byAccount[id]?[label] = list.sorted { $0.ts < $1.ts } }
        }

        var members: [Member] = []
        for input in inputs {
            let history = byAccount[input.account.id] ?? [:]
            var windows = input.snapshot?.windows ?? []
            // A login whose limits can't be read now still has what the samples last saw.
            if windows.isEmpty {
                windows = history.keys.sorted().compactMap { label in
                    history[label]?.last.map { UsageWindow(label: label, usedPercent: $0.used, resetsAt: $0.resets, windowSeconds: nil) }
                }
            }
            let error = input.snapshot?.error
            guard !windows.isEmpty || error != nil else { continue }

            let projections = windows.map { window -> Projection in
                let period = window.windowSeconds.flatMap { $0 > 0 ? $0 : nil } ?? Self.period(label: window.label)
                var used = min(100, max(0, window.usedPercent))
                var resetsAt = window.resetsAt
                // A reset that passed since the read has emptied the window.
                if let passed = resetsAt, passed <= now {
                    used = 0
                    resetsAt = nil
                    if let period {
                        var next = passed
                        while next <= now { next = next.addingTimeInterval(period) }
                        resetsAt = next
                    }
                }
                let list = history[window.label] ?? []
                // An expired login can't be drawn on, so it holds where it is until its resets.
                guard error == nil else {
                    return Projection(label: window.label, used: used, resetsAt: resetsAt, windowSeconds: window.windowSeconds,
                                      period: period, rateNow: 0, rateTypical: 0, now: now)
                }
                let measured = recentRate(list, now: now)
                let elapsed: Double? = {
                    guard let period, let resetsAt else { return nil }
                    let hours = (period - resetsAt.timeIntervalSince(now)) / 3600
                    return hours >= 0.25 ? hours : nil
                }()
                let current = measured ?? elapsed.map { used / $0 }
                let typical = typicalRate(list, now: now) ?? current ?? 0
                return Projection(label: window.label, used: used, resetsAt: resetsAt, windowSeconds: window.windowSeconds,
                                  period: period, rateNow: max(0, current ?? typical), rateTypical: max(0, typical), now: now)
            }
            let remaining = Member.remaining(projections, at: now, after: true)

            // The past, label by label: the latest reading at each point, empty once its reset passed.
            var pastUsed: [String: [Double?]] = [:]
            for (label, list) in history {
                var values = [Double?](repeating: nil, count: pastTimes.count)
                var index = -1
                for (i, time) in pastTimes.enumerated() {
                    while index + 1 < list.count, list[index + 1].ts <= time { index += 1 }
                    guard index >= 0 else { continue }
                    let sample = list[index]
                    values[i] = (sample.resets.map { $0 <= time } ?? false) ? 0 : sample.used
                }
                pastUsed[label] = values
            }
            for projection in projections {
                var values = pastUsed[projection.label] ?? [Double?](repeating: nil, count: pastTimes.count)
                values[values.count - 1] = projection.used
                pastUsed[projection.label] = values
            }
            var pastValues: [Double?] = pastTimes.indices.map { i in
                let known = pastUsed.values.compactMap { $0[i] }
                return known.isEmpty ? nil : min(100, max(0, 100 - known.max()!))
            }
            pastValues[pastValues.count - 1] = remaining

            members.append(Member(
                input: input, counted: error == nil && !projections.isEmpty, windows: projections, remaining: remaining,
                firstSample: history.values.compactMap { $0.first?.ts }.min(), lastSample: history.values.compactMap { $0.last?.ts }.max(),
                pastUsed: pastUsed, past: pastValues,
                forecast: forecastTimes.map { Member.remaining(projections, at: $0, after: true) }))
        }

        let order = Dictionary(uniqueKeysWithValues: Provider.allCases.enumerated().map { ($1, $0) })
        members.sort { (order[$0.tool] ?? 0, $0.remaining) < (order[$1.tool] ?? 0, $1.remaining) }

        let logins = members.map { member -> Login in
            let account = member.input.account
            let binding = member.binding
            let windows = member.windows.map { window in
                Window(label: window.label, usedPercent: round1(window.used), resetsAt: window.resetsAt, windowSeconds: window.windowSeconds,
                       drainPerHour: round2(window.rateNow), emptyAt: window.firstFull(until: horizon))
            }
            let empty = member.remaining <= 0.5
            let full = member.windows.filter { $0.used >= 99.5 }
            let backAt: Date? = empty && !full.isEmpty && full.allSatisfy { $0.resetsAt != nil } ? full.compactMap(\.resetsAt).max() : nil
            let lastSeen = [member.input.snapshot?.fetchedAt, member.lastSample].compactMap { $0 }.max()
            return Login(
                id: account.id, tool: account.provider, toolName: account.provider.name, name: account.displayName, email: account.email,
                plan: account.plan, active: member.input.active, error: member.input.snapshot?.error, counted: member.counted,
                remaining: round1(member.remaining), binding: binding?.label, drainPerHour: round2(binding?.rateNow ?? 0),
                emptyAt: empty ? nil : windows.compactMap(\.emptyAt).min(), backAt: backAt, lastSeen: lastSeen, windows: windows,
                past: member.past.map { $0.map(round1) }, forecast: member.forecast.map(round1))
        }

        func pool(tool: String, name: String, members: [Member]) -> Pool {
            let forecast = forecastTimes.indices.map { i in members.reduce(0) { $0 + $1.forecast[i] } }
            let remaining = members.reduce(0) { $0 + $1.remaining }
            var past: [Double?] = pastTimes.indices.map { i in
                guard members.contains(where: { $0.firstSample.map { $0 <= pastTimes[i] } ?? false }) else { return nil }
                return members.reduce(0) { sum, member in
                    sum + (member.past[i] ?? member.past.compactMap { $0 }.first ?? member.remaining)
                }
            }
            past[past.count - 1] = remaining
            let drain: [Double?] = pastTimes.indices.map { i in
                guard i > 0, past[i] != nil else { return nil }
                let rise = members.reduce(0.0) { sum, member in
                    sum + (member.pastUsed.values.compactMap { values -> Double? in
                        guard let before = values[i - 1], let after = values[i] else { return nil }
                        return max(0, after - before)
                    }.max() ?? 0)
                }
                return rise * 3600 / step
            }
            var emptyAt: Date?
            if let first = forecast.first, first > 0.5 {
                // When the logins are truly spent, so a pool of one empties when its login does; a pool
                // that only ever gets within half a point of empty says so at the first such step.
                let spent = forecast.indices.first { forecast[$0] <= 0.000001 }
                if let i = spent ?? forecast.indices.first(where: { forecast[$0] <= 0.5 }) {
                    let floor = spent == nil ? 0.5 : 0.000001
                    func left(_ time: Date) -> Double { members.reduce(0) { $0 + $1.remaining(at: time, after: true) } }
                    var low = forecastTimes[i - 1], high = forecastTimes[i]
                    for _ in 0..<30 {
                        let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                        if left(middle) <= floor { high = middle } else { low = middle }
                    }
                    emptyAt = high
                }
            }
            var resets: [Reset] = []
            for member in members {
                for time in Set(member.windows.flatMap { $0.resets(until: horizon) }) where time > now {
                    let gain = member.remaining(at: time, after: true) - member.remaining(at: time, after: false)
                    if gain >= 1 {
                        resets.append(Reset(at: time, gain: round1(gain), account: member.input.account.displayName, tool: member.tool.rawValue))
                    }
                }
            }
            return Pool(
                tool: tool, name: name, accounts: members.count, capacity: Double(members.count) * 100, remaining: round1(remaining),
                drainPerHour: round2(members.reduce(0) { $0 + ($1.binding?.rateNow ?? 0) }),
                emptyAt: emptyAt, nextReset: resets.min { ($0.at, -$0.gain) < ($1.at, -$1.gain) },
                past: past.map { $0.map(round1) }, forecast: forecast.map(round1), drain: drain.map { $0.map(round1) })
        }

        let counted = members.filter(\.counted)
        var pools = [pool(tool: "all", name: "All", members: counted)]
        for provider in Provider.allCases {
            let mine = counted.filter { $0.tool == provider }
            if !mine.isEmpty { pools.append(pool(tool: provider.rawValue, name: provider.name, members: mine)) }
        }
        return QuotaReport(generatedAt: now, step: Int(step), pastStart: pastStart, forecastStart: now, pools: pools, accounts: logins)
    }

    /// Least-squares slope over the last three hours since the last reset, in percent an hour.
    static func recentRate(_ samples: [LimitSample], now: Date) -> Double? {
        var recent = samples.filter { $0.ts <= now && $0.ts >= now.addingTimeInterval(-3 * 3600) }
        if let reset = recent.indices.last(where: { $0 > 0 && didReset(recent[$0 - 1], recent[$0]) }) {
            recent.removeFirst(reset)
        }
        guard recent.count >= 2, let first = recent.first, let last = recent.last, last.ts.timeIntervalSince(first.ts) >= 20 * 60 else { return nil }
        let n = Double(recent.count)
        let times = recent.map { $0.ts.timeIntervalSince(first.ts) }
        let meanTime = times.reduce(0, +) / n
        let meanUsed = recent.reduce(0) { $0 + $1.used } / n
        let covariance = zip(times, recent).reduce(0) { $0 + ($1.0 - meanTime) * ($1.1.used - meanUsed) }
        let variance = times.reduce(0) { $0 + ($1 - meanTime) * ($1 - meanTime) }
        guard variance > 0 else { return nil }
        return max(0, covariance / variance * 3600)
    }

    /// What the window usually burns: everything it climbed over the last week over the hours it was watched.
    static func typicalRate(_ samples: [LimitSample], now: Date) -> Double? {
        let week = samples.filter { $0.ts <= now && $0.ts >= now.addingTimeInterval(-7 * 86400) }
        guard let first = week.first, let last = week.last else { return nil }
        let hours = last.ts.timeIntervalSince(first.ts) / 3600
        guard hours >= 2 else { return nil }
        var climbed = 0.0
        for i in week.indices.dropFirst() {
            let before = week[i - 1], after = week[i]
            climbed += didReset(before, after) ? after.used : max(0, after.used - before.used)
        }
        return climbed / hours
    }

    /// A drop of more than a point, or a reset time that passed between two readings.
    private static func didReset(_ before: LimitSample, _ after: LimitSample) -> Bool {
        after.used < before.used - 1 || (before.resets.map { $0 <= after.ts } ?? false)
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
