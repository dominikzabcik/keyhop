import Foundation

enum InsightsRange: String, CaseIterable, Identifiable {
    case today, week, month, thirtyDays

    var id: String { rawValue }

    /// Accepts the words the command line uses: today, week, month, 30d.
    init?(argument: String) {
        switch argument.lowercased() {
        case "today", "day": self = .today
        case "week", "7d": self = .week
        case "month": self = .month
        case "30d", "30days", "thirty": self = .thirtyDays
        default: return nil
        }
    }

    var argument: String {
        switch self {
        case .today: "today"
        case .week: "week"
        case .month: "month"
        case .thirtyDays: "30d"
        }
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "This month"
        case .thirtyDays: "30 days"
        }
    }

    var bucket: Bucket { self == .today ? .hour : .day }

    func interval(now: Date) -> DateInterval {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        switch self {
        case .today:
            return DateInterval(start: startOfToday, end: endOfToday)
        case .week:
            return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: startOfToday)!, end: endOfToday)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: startOfToday, end: endOfToday)
        case .thirtyDays:
            return DateInterval(start: calendar.date(byAdding: .day, value: -29, to: startOfToday)!, end: endOfToday)
        }
    }

    /// The interval of the same length just before this one.
    func previous(now: Date) -> DateInterval {
        let current = interval(now: now)
        return DateInterval(start: current.start.addingTimeInterval(-current.duration), duration: current.duration)
    }
}
