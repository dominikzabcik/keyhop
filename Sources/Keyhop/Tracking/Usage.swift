import Foundation

struct TokenCounts: Equatable {
    var input = 0
    var cacheWrite = 0
    /// Anthropic's one-hour cache writes, billed at twice the input rate.
    var cacheWrite1h = 0
    var cacheRead = 0
    /// Includes reasoning tokens.
    var output = 0
    var reasoning = 0

    var total: Int { input + cacheWrite + cacheWrite1h + cacheRead + output }

    static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, cacheWrite: a.cacheWrite + b.cacheWrite, cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h,
                    cacheRead: a.cacheRead + b.cacheRead, output: a.output + b.output, reasoning: a.reasoning + b.reasoning)
    }
}

struct Totals: Equatable {
    var tokens = TokenCounts()
    /// What the tokens would cost at standard API prices.
    var cost = 0.0
    /// What the provider actually charged, where it reports that (Cursor on-demand usage).
    var billed = 0.0
    var requests = 0

    static func + (a: Totals, b: Totals) -> Totals {
        Totals(tokens: a.tokens + b.tokens, cost: a.cost + b.cost, billed: a.billed + b.billed, requests: a.requests + b.requests)
    }

    static func += (a: inout Totals, b: Totals) { a = a + b }
}

/// One priced request, as stored in the usage database.
struct UsageRecord {
    enum Kind: String {
        /// A single model response.
        case request
        /// The growth of a session's running total, from logs that don't record single responses.
        case runningTotal
    }

    var key: String
    var provider: Provider
    /// Set when the source names the account (Cursor's export). Otherwise the account in use at
    /// `timestamp` is looked up from Keyhop's record of switches.
    var account: UUID?
    var session: String?
    var kind: Kind
    var timestamp: Date
    var model: String
    var tokens: TokenCounts
    var cost: Double
    var billed: Double?
    /// The repository or folder the work happened in, where the tool records one. See `Projects`.
    var project: String? = nil
}

enum Bucket {
    case hour, day

    var sqliteFormat: String { self == .hour ? "%Y-%m-%d %H" : "%Y-%m-%d" }
    var dateFormat: String { self == .hour ? "yyyy-MM-dd HH" : "yyyy-MM-dd" }
}

struct AccountKey: Hashable {
    let provider: Provider
    /// Nil for usage from before Keyhop knew which account was signed in.
    let account: UUID?
}

/// One model on one tool. The same short name on two tools stays two rows.
struct ModelKey: Hashable, CustomStringConvertible {
    let provider: Provider
    let model: String
    var description: String { "\(provider.shortName) · \(model)" }
}

struct UsageDigest {
    struct Point: Identifiable {
        let start: Date
        let key: AccountKey
        let model: String
        let totals: Totals
        var id: String { "\(start.timeIntervalSince1970)|\(key.provider.rawValue)|\(key.account?.uuidString ?? "-")|\(model)" }
    }

    /// A conversation or session the tool named, rolled up for the Usage list.
    struct Session {
        let id: String
        let provider: Provider
        let account: UUID?
        let model: String
        let from: Date
        let to: Date
        let totals: Totals
    }

    var points: [Point] = []
    var byAccount: [AccountKey: Totals] = [:]
    var byModel: [ModelKey: Totals] = [:]
    var byProvider: [Provider: Totals] = [:]
    /// Keyed by project path. Usage no tool placed in a folder is under "".
    var byProject: [String: Totals] = [:]
    var sessions: [Session] = []
    var total = Totals()
    var previous = Totals()
}

enum BudgetPeriod: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "per day"
        case .week: "per week"
        case .month: "per month"
        }
    }

    var adjective: String {
        switch self {
        case .day: "daily"
        case .week: "weekly"
        case .month: "monthly"
        }
    }

    func interval(containing date: Date) -> DateInterval {
        let component: Calendar.Component = switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return Calendar.current.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86400)
    }

    func elapsed(at date: Date) -> Double {
        let interval = interval(containing: date)
        return min(max(date.timeIntervalSince(interval.start) / interval.duration, 0), 1)
    }
}

struct Budget: Identifiable, Equatable {
    static let everything = "all"

    /// `"all"` or `"account:<uuid>"`.
    var scope: String
    /// USD at API prices.
    var amount: Double
    var period: BudgetPeriod

    var id: String { scope }

    static func scope(for account: UUID) -> String { "account:\(account.uuidString)" }

    var account: UUID? {
        scope.hasPrefix("account:") ? UUID(uuidString: String(scope.dropFirst("account:".count))) : nil
    }
}

enum Numbers {
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        func trimmed(_ number: Double, _ suffix: String) -> String {
            let text = number >= 100 ? String(format: "%.0f", number) : String(format: "%.1f", number)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + suffix
        }
        switch value {
        case 1e9...: return trimmed(value / 1e9, "B")
        case 1e6...: return trimmed(value / 1e6, "M")
        case 1e3...: return trimmed(value / 1e3, "K")
        default: return "\(count)"
        }
    }

    static func usd(_ amount: Double) -> String {
        if amount >= 1000 {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return "$" + (formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount))
        }
        return amount >= 100 ? String(format: "$%.0f", amount) : String(format: "$%.2f", amount)
    }
}
