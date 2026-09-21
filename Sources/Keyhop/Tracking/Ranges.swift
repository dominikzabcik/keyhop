import Foundation

/// A span of usage history to read: one of the fixed ranges, everything since the first request
/// Keyhop saw, or days someone picked.
enum InsightsRange: Hashable, Identifiable {
    case today, week, month, thirtyDays, ninetyDays, year
    /// Every day since `since`. Parsed as `.all(since: nil)`; `resolved(firstUse:)` fills in the
    /// first day with usage once the history can be asked.
    case all(since: Date?)
    /// Whole days, `from` through `through`, both included.
    case custom(from: Date, through: Date)

    /// The fixed ranges, in the order they're offered.
    static let presets: [InsightsRange] = [.today, .week, .month, .thirtyDays, .ninetyDays, .year]

    var id: String { argument }

    /// Accepts the words the command line uses: today, week, month, 30d, 90d, 12m, all, or two
    /// dates as `2026-01-01..2026-03-31` (either order; a single date is that one day).
    init?(argument: String) {
        switch argument.lowercased().trimmingCharacters(in: .whitespaces) {
        case "today", "day": self = .today
        case "week", "7d": self = .week
        case "month": self = .month
        case "30d", "30days", "thirty": self = .thirtyDays
        case "90d", "90days", "quarter": self = .ninetyDays
        case "12m", "year", "365d": self = .year
        case "all", "alltime", "all-time", "ever": self = .all(since: nil)
        case let word:
            let parts = word.components(separatedBy: "..")
            guard (1...2).contains(parts.count), let first = Self.day(parts[0]), let last = Self.day(parts.last!) else { return nil }
            self = .custom(from: min(first, last), through: max(first, last))
        }
    }

    var argument: String {
        switch self {
        case .today: "today"
        case .week: "week"
        case .month: "month"
        case .thirtyDays: "30d"
        case .ninetyDays: "90d"
        case .year: "12m"
        case .all: "all"
        case let .custom(from, through): "\(Self.dayText(from))..\(Self.dayText(through))"
        }
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "This month"
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        case .year: "12 months"
        case .all: "All time"
        case let .custom(from, through):
            from == through ? Self.readable(from, year: true) : "\(Self.readable(from, year: !Self.sameYear(from, through))) to \(Self.readable(through, year: true))"
        }
    }

    /// Everything since the first day with usage, or today alone when there's none yet.
    func resolved(firstUse: Date?) -> InsightsRange {
        guard case .all(nil) = self else { return self }
        return .all(since: Calendar.current.startOfDay(for: firstUse ?? Date()))
    }

    /// The first day with usage, for everything since the start. The interval may begin a little
    /// earlier, on the Monday or the 1st its first bucket starts on.
    var since: Date? {
        if case let .all(since) = self { return since }
        return nil
    }

    /// The finest step that still gives a readable chart: hours for a day or two, days for up to
    /// three months, weeks for up to two years, months beyond.
    var bucket: Bucket {
        switch self {
        case .today: return .hour
        case .week, .month, .thirtyDays, .ninetyDays: return .day
        case .year: return .week
        case .all, .custom:
            let days = interval(now: Date()).duration / 86_400
            return days <= 2 ? .hour : days <= 92 ? .day : days <= 731 ? .week : .month
        }
    }

    /// Whether a period of the same length just before this one means anything. Everything since
    /// the start has nothing before it.
    var hasPrevious: Bool {
        if case .all = self { return false }
        return true
    }

    func interval(now: Date) -> DateInterval {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        func last(_ days: Int) -> DateInterval {
            DateInterval(start: calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday)!, end: endOfToday)
        }
        let plain: DateInterval
        switch self {
        case .today: plain = DateInterval(start: startOfToday, end: endOfToday)
        case .week: plain = last(7)
        case .month: plain = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: startOfToday, end: endOfToday)
        case .thirtyDays: plain = last(30)
        case .ninetyDays: plain = last(90)
        case .year: plain = last(365)
        case let .all(since):
            plain = DateInterval(start: min(calendar.startOfDay(for: since ?? now), startOfToday), end: endOfToday)
        case let .custom(from, through):
            let start = calendar.startOfDay(for: from)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through))!
            plain = DateInterval(start: start, end: max(end, start))
        }
        // Week and month buckets begin on a Monday or the 1st, so the first one is whole and each
        // bucket's label is where it really starts.
        return DateInterval(start: bucketFor(plain).start(of: plain.start), end: plain.end)
    }

    /// The bucket for an interval, without asking `interval` again.
    private func bucketFor(_ plain: DateInterval) -> Bucket {
        switch self {
        case .all, .custom:
            let days = plain.duration / 86_400
            return days <= 2 ? .hour : days <= 92 ? .day : days <= 731 ? .week : .month
        default: return bucket
        }
    }

    /// The interval of the same length just before this one. For everything since the start,
    /// an empty one, so there's nothing to compare against.
    func previous(now: Date) -> DateInterval {
        let current = interval(now: now)
        guard hasPrevious else { return DateInterval(start: current.start, duration: 0) }
        return DateInterval(start: current.start.addingTimeInterval(-current.duration), duration: current.duration)
    }

    // MARK: Days as text

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    private static func day(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = formatter("yyyy-MM-dd").date(from: trimmed),
              dayText(date) == trimmed else { return nil }
        return date
    }

    private static func dayText(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }

    private static func readable(_ date: Date, year: Bool) -> String {
        formatter(year ? "MMM d, yyyy" : "MMM d").string(from: date)
    }

    private static func sameYear(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.component(.year, from: a) == Calendar.current.component(.year, from: b)
    }
}
