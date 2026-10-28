#if os(macOS)
import SwiftUI

// The pieces the notch and the menu are both built from, so the two read as one surface: a
// group of limit rows per tool, the read time, and today's line.

/// The same reading as everywhere: 15% or less left is out, 40% or less is getting there.
enum LimitTone {
    case ok, low, out

    init(left: Int) {
        self = left <= 15 ? .out : left <= 40 ? .low : .ok
    }

    var color: Color {
        switch self {
        case .ok: Brand.good
        case .low: Brand.warn
        case .out: Brand.red
        }
    }
}

/// One tool's limits on the login it reads: the login in use, or the roomiest one when none is
/// read. Its windows come tightest first; a signed-out login has none.
struct LimitGroup: Identifiable {
    struct Line {
        let window: String
        let left: Int
        let reset: String
        let tone: LimitTone
    }

    let provider: Provider
    let login: Account
    let signedOut: Bool
    let lines: [Line]
    var id: String { provider.rawValue }

    var left: Int { signedOut ? 0 : lines.first?.left ?? 100 }
    var tone: LimitTone { signedOut ? .out : lines.first?.tone ?? .ok }

    /// Tightest first, so what needs you leads.
    @MainActor
    static func make(store: AccountStore, now: Date = Date()) -> [LimitGroup] {
        var groups: [LimitGroup] = []
        for provider in Provider.allCases {
            let logins = store.accounts.filter { $0.provider == provider }
            func read(_ account: Account) -> (signedOut: Bool, windows: [UsageWindow])? {
                guard let snapshot = store.usage[account.id] else { return nil }
                if snapshot.signedOut == true { return (true, []) }
                return snapshot.windows.isEmpty ? nil : (false, snapshot.windows)
            }
            let active = logins.first { $0.id == store.active[provider] && read($0) != nil }
            let roomiest = logins
                .compactMap { account in read(account).flatMap { $0.signedOut ? nil : (account, $0.windows) } }
                .max { tightest($0.1, now) < tightest($1.1, now) }?.0
            guard let login = active ?? roomiest, let reading = read(login) else { continue }
            let lines = reading.windows
                .sorted { SmartHop.room($0, now) < SmartHop.room($1, now) }
                .map { window -> Line in
                    let left = Int(SmartHop.room(window, now).rounded())
                    return Line(window: window.label.lowercased(), left: left,
                                reset: window.resetText(at: now), tone: LimitTone(left: left))
                }
            groups.append(LimitGroup(provider: provider, login: login, signedOut: reading.signedOut, lines: lines))
        }
        return groups.sorted { $0.left < $1.left }
    }

    private static func tightest(_ windows: [UsageWindow], _ now: Date) -> Double {
        windows.map { SmartHop.room($0, now) }.min() ?? 100
    }

    /// Rows are fixed-height, so a panel can be sized before it lays out.
    var height: CGFloat { LimitRows.leadHeight + CGFloat(max(lines.count - 1, 0)) * LimitRows.subHeight }
}

/// A tool's group: its mark and name beside the tightest window at full weight, the other windows
/// as quiet rows under it. Each row is the window, a thin bar of what is left, and the figure.
struct LimitRows: View {
    let group: LimitGroup

    static let leadHeight: CGFloat = 30
    static let subHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            if group.signedOut {
                row(window: "", left: 0, caption: "signed out", tone: .out, lead: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(group.provider.shortName), \(group.login.displayName), signed out")
            }
            ForEach(Array(group.lines.enumerated()), id: \.offset) { index, line in
                row(window: line.window, left: line.left,
                    caption: line.reset.isEmpty ? "\(line.left)%" : "\(line.left)% · \(line.reset)",
                    tone: line.tone, lead: index == 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(group.provider.shortName), \(line.window) window, \(line.left)% left"
                        + (line.reset.isEmpty ? "" : ", resets in \(line.reset)"))
            }
        }
    }

    private func row(window: String, left: Int, caption: String, tone: LimitTone, lead: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                if lead {
                    Image(nsImage: Marks.image(for: group.provider))
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(group.tone.color)
                    Text(group.provider.shortName)
                        .font(Brand.sans(12.5, weight: .semibold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                }
            }
            .frame(width: 100, alignment: .leading)
            Text(window)
                .font(Brand.sans(11))
                .foregroundStyle(Brand.subtle)
                .lineLimit(1)
                .frame(width: 66, alignment: .trailing)
            Capsule()
                .fill(Brand.raisedHover)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(tone.color)
                            .frame(width: max(geo.size.width * CGFloat(left) / 100, left > 0 ? 4 : 0))
                    }
                }
                .clipShape(Capsule())
            Text(caption)
                .font(lead ? Brand.mono(12, weight: tone == .out ? .semibold : .medium) : Brand.mono(11))
                .foregroundStyle(lead ? (tone == .out ? Brand.bad : Brand.muted) : Brand.subtle)
                .lineLimit(1)
                .frame(width: 112, alignment: .trailing)
        }
        .frame(height: lead ? Self.leadHeight : Self.subHeight)
    }
}

/// When the limits were last read, amber once the reading is ten minutes old.
struct ReadTime: View {
    let readAt: Date?
    let now: Date

    var body: some View {
        if let readAt {
            let minutes = Int(now.timeIntervalSince(readAt) / 60)
            Text(minutes < 1 ? "read now" : minutes < 60 ? "read \(minutes)m ago" : "read \(minutes / 60)h ago")
                .font(Brand.mono(11, weight: .medium))
                .foregroundStyle(minutes >= 10 ? Brand.warn : Brand.subtle)
                .lineLimit(1)
                .accessibilityLabel("Limits read \(readAt.formatted(.relative(presentation: .named)))")
        }
    }
}

/// Today's tokens and their API value, and how they split across tools. Before the first read of
/// the logs there is no figure yet, and it says so instead of showing a zero.
struct TodayLine: View {
    let today: Today?

    struct Today {
        let tokens: Int
        let cost: Double
        /// Each tool's share of today's tokens, largest first.
        let shares: [(provider: Provider, fraction: Double)]

        @MainActor
        init?(tracker: UsageTracker) {
            guard tracker.lastUpdate != nil else { return nil }
            let total = tracker.todayTotal
            tokens = total.tokens.total
            cost = total.cost
            shares = tracker.todayByProvider
                .filter { $0.value.tokens.total > 0 }
                .sorted { $0.value.tokens.total > $1.value.tokens.total }
                .prefix(6)
                .map { (provider: $0.key, fraction: Double($0.value.tokens.total) / Double(max(total.tokens.total, 1))) }
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let today {
                (Text(Numbers.tokens(today.tokens)).font(Brand.mono(13, weight: .semibold)).foregroundStyle(Brand.text)
                    + Text(" tokens today").font(Brand.sans(12)).foregroundStyle(Brand.subtle)
                    + Text(today.cost > 0 ? " · \(Numbers.usd(today.cost))" : "").font(Brand.mono(12.5, weight: .medium))
                    .foregroundStyle(Brand.muted))
                    .lineLimit(1)
                    .fixedSize()
                ShareBar(shares: today.shares)
            } else {
                Text("Reading today's tokens")
                    .font(Brand.sans(12))
                    .foregroundStyle(Brand.subtle)
                    .lineLimit(1)
            }
        }
    }
}

/// Today's tokens by tool as thin grey segments, largest first: the window's share greys.
struct ShareBar: View {
    let shares: [(provider: Provider, fraction: Double)]

    private static let greys = ["#cfcbc3", "#b3afa7", "#96928a", "#78746d", "#5a5751", "#3a3731"]

    var body: some View {
        if shares.count > 1 {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        Capsule()
                            .fill(Color(hex: Self.greys[min(index, Self.greys.count - 1)]))
                            .frame(width: max((geo.size.width - CGFloat(shares.count - 1) * 2) * share.fraction, 2))
                    }
                }
            }
            .frame(maxWidth: 64)
            .frame(height: 2)
            .accessibilityLabel("Share of today's tokens: " + shares.map {
                "\($0.provider.shortName) \(Int(($0.fraction * 100).rounded()))%"
            }.joined(separator: ", "))
        }
    }
}
#endif
