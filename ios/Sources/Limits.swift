import Foundation

/// One account as the phone shows it: every window the computer reported, tightest first.
struct LimitAccount: Identifiable, Equatable {
    let key: String
    let tool: String
    let label: String?
    let windows: [CloudLimit]

    var id: String { key }

    /// "Codex · Work" when the account was named on the computer, "Codex" when it wasn't. The email
    /// the Mac falls back to never leaves it, so there is nothing else to fall back to here.
    var name: String {
        guard let label, !label.isEmpty else { return Format.tool(tool) }
        return "\(Format.tool(tool)) · \(label)"
    }

    /// The window with least room left: the one that decides whether this account can be used.
    var tightest: CloudLimit? { windows.max { $0.usedPercent < $1.usedPercent } }

    /// Groups a reading into accounts, fullest account first, so what is nearly spent reads first.
    static func group(_ limits: [CloudLimit]) -> [LimitAccount] {
        var order: [String] = []
        var byKey: [String: [CloudLimit]] = [:]
        for limit in limits {
            if byKey[limit.accountKey] == nil { order.append(limit.accountKey) }
            byKey[limit.accountKey, default: []].append(limit)
        }
        return order.compactMap { key -> LimitAccount? in
            guard let windows = byKey[key], let first = windows.first else { return nil }
            return LimitAccount(key: key, tool: first.tool, label: first.label,
                                windows: windows.sorted { $0.usedPercent > $1.usedPercent })
        }
        .sorted { ($0.tightest?.usedPercent ?? 0) > ($1.tightest?.usedPercent ?? 0) }
    }
}

/// One notification the phone intends to raise, worked out before anything is scheduled so the
/// rules can be read and tested on their own.
struct PlannedAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let at: Date
}

/// What the phone will say, and when.
///
/// Every alert here is scheduled locally against a moment already known: a limit's own reset, the
/// last evening of the season, tonight. Nothing is pushed, so the phone needs no server reaching it
/// and no permission beyond notifications.
enum AlertPlan {
    /// A window with room to spare doesn't need announcing when it turns over.
    static let fullEnough = 85.0
    /// Scheduling further out than this is guessing: the reading will have moved by then.
    static let horizon: TimeInterval = 7 * 86400
    /// iOS keeps 64 pending notifications. Staying well under leaves room for the ones that matter.
    static let most = 24

    static func alerts(limits: [CloudLimit], season: CloudSeason?, quests: CloudQuests?,
                       wantsLimits: Bool, wantsSeason: Bool, now: Date = Date(),
                       calendar: Calendar = .current) -> [PlannedAlert] {
        var planned: [PlannedAlert] = []
        if wantsLimits { planned += limitAlerts(limits, now: now) }
        if wantsSeason {
            if let alert = seasonAlert(season, now: now, calendar: calendar) { planned.append(alert) }
            if let alert = questAlert(quests, now: now, calendar: calendar) { planned.append(alert) }
        }
        return Array(planned.sorted { $0.at < $1.at }.prefix(most))
    }

    /// A limit that is nearly spent, announced the moment it comes back.
    private static func limitAlerts(_ limits: [CloudLimit], now: Date) -> [PlannedAlert] {
        LimitAccount.group(limits).flatMap { account in
            account.windows.compactMap { window -> PlannedAlert? in
                guard window.usedPercent >= fullEnough, let reset = window.resetDate else { return nil }
                // A reset less than a minute out would land after the fact; one past the horizon is a guess.
                guard reset > now.addingTimeInterval(60), reset < now.addingTimeInterval(horizon) else { return nil }
                return PlannedAlert(id: "limit|\(window.id)|\(Int(reset.timeIntervalSince1970))",
                                    title: "\(account.name) is ready",
                                    body: "The \(window.windowLabel) limit just reset.", at: reset)
            }
        }
    }

    /// The season's last evening, while there is still time to climb.
    private static func seasonAlert(_ season: CloudSeason?, now: Date, calendar: Calendar) -> PlannedAlert? {
        guard let season, !season.over, season.daysLeft >= 1, season.daysLeft <= 3 else { return nil }
        guard let lastDay = calendar.date(byAdding: .day, value: season.daysLeft - 1, to: calendar.startOfDay(for: now)),
              let at = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: lastDay), at > now else { return nil }
        let body: String
        if let you = season.you, let next = you.next {
            body = "You're \(Format.tier(you.tier)), \(Format.tokens(next.tokens)) tokens from \(next.label)."
        } else if let you = season.you {
            body = "You finish \(Format.tier(you.tier))."
        } else {
            body = "Sync some usage to take a place."
        }
        return PlannedAlert(id: "season|\(season.season)", title: "\(season.label) ends tonight", body: body, at: at)
    }

    /// Tonight, if today's goals are still open.
    private static func questAlert(_ quests: CloudQuests?, now: Date, calendar: Calendar) -> PlannedAlert? {
        let open = (quests?.quests ?? []).filter { $0.period == "day" && !$0.complete }
        guard !open.isEmpty else { return nil }
        guard let at = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now), at > now else { return nil }
        let day = calendar.startOfDay(for: now).timeIntervalSince1970
        let title = open.count == 1 ? "One quest still open" : "\(open.count) quests still open"
        return PlannedAlert(id: "quests|\(Int(day))", title: title,
                            body: open.map(\.name).joined(separator: ", ") + ".", at: at)
    }
}
