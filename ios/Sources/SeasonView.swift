import SwiftUI

/// Once linked: where the accounts stand, where this season stands, then quests, badges and the board.
struct SeasonView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAlerts = ProcessInfo.processInfo.arguments.contains("--show-alerts")

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 14) {
                        problem
                        if store.hasRead {
                            limits
                            standing
                            quests
                            badges
                            board.id("board")
                        } else {
                            reading
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    // Cards settle into place when a read lands; nothing fades in from nothing.
                    .animation(.snappy(duration: 0.35), value: store.hasRead)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    // For screenshots of the lower cards in sample mode.
                    if ProcessInfo.processInfo.arguments.contains("--scroll-end") { reader.scrollTo("board", anchor: .bottom) }
                }
            }
            .background(Brand.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Brand.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        HopMark(size: 16, hopping: store.loading, period: 0.9)
                        Text("Keyhop").font(.ui(16, .semibold, .headline)).foregroundStyle(Brand.text)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(store.loading ? "Keyhop, updating" : "Keyhop")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Alerts…") { showingAlerts = true }
                        if let url = store.link?.profileURL {
                            Link("Open my profile", destination: url)
                        }
                        Divider()
                        Button("Unlink this phone", role: .destructive) { Task { await store.unlink() } }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Brand.muted)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More")
                }
            }
            .sheet(isPresented: $showingAlerts) { AlertsView() }
            .refreshable { await store.refresh() }
            .task {
                await store.readAlertPermission()
                await store.refresh()
            }
        }
    }

    // MARK: States

    @ViewBuilder private var problem: some View {
        if let message = store.problem {
            Card {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(message)
                        .font(.ui(13, .regular, .footnote))
                        .foregroundStyle(Brand.wrong)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Try again") { Task { await store.refresh() } }
                        .font(.ui(13, .semibold, .footnote))
                        .foregroundStyle(Brand.text)
                        .disabled(store.loading)
                }
                .padding(16)
            }
            .transition(.offset(y: -8))
        }
    }

    /// Before the first read lands. The mark hops so the wait reads as Keyhop working, not as empty.
    private var reading: some View {
        Card {
            HStack(spacing: 14) {
                HopMark(size: 28, hopping: store.loading, period: 1.0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.loading ? "Reading your season" : "Nothing read yet")
                        .font(.ui(15, .semibold, .headline))
                        .foregroundStyle(Brand.text)
                    Text(store.loading ? "Limits, standings and quests from keyhop.app." : "Pull down to try again.")
                        .font(.ui(12.5, .regular, .footnote))
                        .foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    // MARK: Limits

    /// Where the accounts stand, when the computer is sharing it. The two arms of the mark carry the
    /// two nearest limits, the same way they do in the Mac's menu bar.
    @ViewBuilder private var limits: some View {
        let accounts = store.limitAccounts
        if accounts.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    CardHead(title: "Limits")
                    Text("In Keyhop on your computer, open Settings and choose Share limits. This phone can then count down to a reset and tell you when an account comes back.")
                        .font(.ui(12.5, .regular, .footnote))
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
        } else {
            Card {
                // Ticks with the clock, so a countdown on screen is never a stale number.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            HopMark(size: 18, hopping: store.loading, period: 0.9, arms: nearest(accounts))
                            CardHead(title: "Limits") {
                                if let updated = store.limits.updated {
                                    Text(sent(updated, at: context.date))
                                }
                            }
                        }
                        .padding(.bottom, 14)

                        ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 { Divider().overlay(Brand.border).padding(.vertical, 12) }
                            LimitRows(account: account, now: context.date)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    /// The two limits closest to being spent, for the mark's arms.
    private func nearest(_ accounts: [LimitAccount]) -> [Double] {
        let sorted = accounts.flatMap(\.windows).map(\.usedPercent).sorted(by: >)
        return (0..<2).map { $0 < sorted.count ? sorted[$0] / 100 : 0 }
    }

    private func sent(_ updated: Date, at now: Date) -> String {
        now.timeIntervalSince(updated) < 90 ? "just now" : "\(Format.until(now, from: updated)) ago"
    }

    // MARK: Season

    private var standing: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let season = store.season {
                    let tier = season.you?.tier ?? .init(key: "bronze", name: "Bronze", division: 3)
                    HStack(alignment: .center, spacing: 12) {
                        TierMark(key: tier.key, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Format.tier(tier))
                                .font(.ui(21, .semibold, .title3))
                                .foregroundStyle(Brand.tier(tier.key))
                            Text(season.label)
                                .font(.ui(13, .regular, .footnote))
                                .foregroundStyle(Brand.muted)
                        }
                        Spacer(minLength: 8)
                        if let rank = season.you?.rank {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("#\(rank)")
                                    .font(.ui(21, .semibold, .title3).monospacedDigit())
                                    .foregroundStyle(Brand.text)
                                    .contentTransition(.numericText(value: Double(rank)))
                                Text("of \(season.players)")
                                    .font(.ui(12.5, .regular, .footnote).monospacedDigit())
                                    .foregroundStyle(Brand.subtle)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Rank \(rank) of \(season.players)")
                        }
                    }

                    // How much of the month is gone: the season's own clock.
                    VStack(alignment: .leading, spacing: 6) {
                        QuestTrack(share: Format.seasonProgress(season), complete: false)
                        HStack {
                            Text(season.over ? "Season finished" : season.daysLeft == 1 ? "Last day" : "\(season.daysLeft) days left")
                            Spacer()
                            if let you = season.you { Text("\(Format.tokens(you.tokens)) tokens") }
                        }
                        .font(.ui(12.5, .regular, .footnote).monospacedDigit())
                        .foregroundStyle(Brand.subtle)
                    }

                    if let next = season.you?.next {
                        Text("\(Format.tokens(next.tokens)) more for \(next.label)")
                            .font(.ui(13, .medium, .footnote))
                            .foregroundStyle(Brand.muted)
                    } else if season.you == nil {
                        Text("Sync some usage this month to take a place.")
                            .font(.ui(13, .regular, .footnote))
                            .foregroundStyle(Brand.muted)
                    }
                } else {
                    CardHead(title: "Season")
                    Text("No season to show yet.")
                        .font(.ui(13, .regular, .footnote))
                        .foregroundStyle(Brand.muted)
                }
            }
            .padding(18)
        }
        .animation(.snappy, value: store.season?.you?.rank)
    }

    @ViewBuilder private var quests: some View {
        if let list = store.quests?.quests, !list.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    CardHead(title: "Quests") {
                        Text("\(list.filter(\.complete).count) of \(list.count) done")
                    }
                    .padding(.bottom, 12)
                    ForEach(Array(list.enumerated()), id: \.element.key) { index, quest in
                        if index > 0 { Divider().overlay(Brand.border).padding(.vertical, 10) }
                        QuestRow(quest: quest)
                    }
                }
                .padding(18)
            }
        }
    }

    @ViewBuilder private var badges: some View {
        if let badges = store.quests?.badges, !badges.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    CardHead(title: "Badges") {
                        Text("\(badges.filter(\.earned).count) of \(badges.count)")
                    }
                    .padding(.bottom, 12)
                    // Earned first: what someone has done reads before what is left to do.
                    let ordered = badges.filter(\.earned) + badges.filter { !$0.earned }
                    ForEach(Array(ordered.enumerated()), id: \.element.key) { index, badge in
                        if index > 0 { Divider().overlay(Brand.border).padding(.vertical, 10) }
                        BadgeRow(badge: badge)
                    }
                }
                .padding(18)
            }
        }
    }

    @ViewBuilder private var board: some View {
        if let entries = store.board?.entries, !entries.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    CardHead(title: "This week") { Text("tokens") }
                        .padding(.bottom, 10)
                    ForEach(Array(entries.prefix(10).enumerated()), id: \.element.login) { index, entry in
                        if index > 0, !entry.isYou, !entries[index - 1].isYou {
                            Divider().overlay(Brand.border)
                        }
                        BoardRow(entry: entry)
                    }
                }
                .padding(18)
            }
        }
    }
}

// MARK: Rows

/// One account's windows. Every row sits on the same columns, so the measures and the countdowns
/// line up down the card however long a window's name happens to be, and at any text size.
struct LimitRows: View {
    let account: LimitAccount
    let now: Date
    @ScaledMetric(relativeTo: .footnote) private var labelWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .footnote) private var percentWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .footnote) private var resetWidth: CGFloat = 62

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(account.name)
                    .font(.ui(14, .medium, .subheadline))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                // Only while the account is actually spent: with room left this repeated a number
                // the rows below already carry.
                if let tightest = account.tightest, tightest.usedPercent >= AlertPlan.fullEnough,
                   let reset = tightest.resetDate, reset > now {
                    Text("back in \(Format.until(reset, from: now))")
                        .font(.ui(12.5, .medium, .footnote).monospacedDigit())
                        .foregroundStyle(Brand.spent)
                        .contentTransition(.numericText())
                        .fixedSize()
                }
            }
            ForEach(account.windows) { window in
                HStack(spacing: 12) {
                    Text(window.windowLabel)
                        .font(.ui(12.5, .regular, .footnote))
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                        .frame(width: labelWidth, alignment: .leading)
                    CapacityTrack(usedPercent: window.usedPercent)
                    Text("\(Int(window.usedPercent.rounded()))%")
                        .font(.ui(12.5, .medium, .footnote).monospacedDigit())
                        .foregroundStyle(window.usedPercent >= 95 ? Brand.spent : Brand.muted)
                        .contentTransition(.numericText(value: window.usedPercent))
                        .fixedSize()
                        .frame(width: percentWidth, alignment: .trailing)
                    // Monospaced digits, not a monospaced face: numbers line up, spaces stay narrow.
                    Text(window.resetDate.map { $0 > now ? Format.until($0, from: now) : "now" } ?? "")
                        .font(.ui(12.5, .regular, .footnote).monospacedDigit())
                        .foregroundStyle(Brand.subtle)
                        .contentTransition(.numericText())
                        .fixedSize()
                        .frame(width: resetWidth, alignment: .trailing)
                }
                .animation(.snappy, value: window.usedPercent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(reading(window))
            }
        }
    }

    private func reading(_ window: CloudLimit) -> String {
        var text = "\(account.name), \(window.windowLabel) limit \(Int(window.usedPercent.rounded())) percent used"
        if let reset = window.resetDate, reset > now { text += ", back in \(Format.until(reset, from: now))" }
        return text
    }
}

/// A goal and how far along it is, with the same track the desktop shows beside it.
struct QuestRow: View {
    let quest: CloudQuests.Quest
    @ScaledMetric(relativeTo: .footnote) private var measureWidth: CGFloat = 72

    private var share: Double { min(Double(quest.done) / Double(max(quest.target, 1)), 1) }

    private var state: String {
        if quest.complete { return "Done" }
        // Small counts read as counts; big ones, like token goals, read better as a share.
        return quest.target <= 7 ? "\(quest.done) of \(quest.target)" : "\(Int(share * 100))%"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(quest.name)
                    .font(.ui(14, .medium, .subheadline))
                    .foregroundStyle(Brand.text)
                Text(quest.note)
                    .font(.ui(12.5, .regular, .footnote))
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(state)
                    .font(.ui(12.5, .medium, .footnote).monospacedDigit())
                    .foregroundStyle(quest.complete ? Brand.good : Brand.muted)
                    .contentTransition(.numericText())
                QuestTrack(share: share, complete: quest.complete)
            }
            .frame(width: measureWidth, alignment: .trailing)
        }
        .animation(.snappy, value: quest.done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(quest.name), \(quest.note), \(quest.complete ? "done" : state)")
    }
}

/// A quest's measure: the same capsule as a limit, but it fills toward something good.
struct QuestTrack: View {
    let share: Double
    let complete: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.raised)
                Capsule()
                    .fill(complete ? Brand.good.opacity(0.85) : Brand.muted.opacity(0.6))
                    .frame(width: max(share * geometry.size.width, share > 0 ? 4 : 0))
            }
        }
        .frame(height: 4)
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: share)
        .accessibilityHidden(true)
    }
}

/// A badge: the Keyhop mark, lit when earned and dim when not, with the day it was won.
struct BadgeRow: View {
    let badge: CloudQuests.Badge

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            KeyhopMark(size: 18)
                .opacity(badge.earned ? 1 : 0.22)
            VStack(alignment: .leading, spacing: 2) {
                Text(badge.name)
                    .font(.ui(14, .medium, .subheadline))
                    .foregroundStyle(badge.earned ? Brand.text : Brand.muted)
                Text(badge.note)
                    .font(.ui(12.5, .regular, .footnote))
                    .foregroundStyle(Brand.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(badge.earned ? (badge.day.flatMap(Format.day) ?? "Earned") : "Locked")
                .font(.ui(12.5, .medium, .footnote).monospacedDigit())
                .foregroundStyle(badge.earned ? Brand.good : Brand.subtle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(badge.name), \(badge.note), \(badge.earned ? "earned" : "locked")")
    }
}

/// One place on the weekly board. Your own row sits on a raised band so it is found at a glance.
struct BoardRow: View {
    let entry: CloudBoard.Entry
    @ScaledMetric(relativeTo: .footnote) private var rankWidth: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.ui(13, .medium, .footnote).monospacedDigit())
                .foregroundStyle(entry.isYou ? Brand.text : Brand.subtle)
                .frame(width: rankWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.isYou ? "You" : (entry.name ?? entry.login))
                    .font(.ui(14, entry.isYou ? .semibold : .regular, .subheadline))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text("@\(entry.login)")
                    .font(.ui(12, .regular, .caption))
                    .foregroundStyle(Brand.subtle)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Format.tokens(entry.tokens))
                .font(.ui(13, .medium, .footnote).monospacedDigit())
                .foregroundStyle(entry.isYou ? Brand.text : Brand.muted)
        }
        .padding(.vertical, 9)
        // The band reaches past the text by the same amount on both sides, so every row's text
        // still starts on the card's own margin.
        .padding(.horizontal, 10)
        .background {
            if entry.isYou {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.raised)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Brand.border, lineWidth: 1))
            }
        }
        .padding(.horizontal, -10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.isYou ? "You" : (entry.name ?? entry.login)), rank \(entry.rank), \(Format.tokens(entry.tokens)) tokens")
    }
}
