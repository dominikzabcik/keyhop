import SwiftUI

@main
struct KeyhopApp: App {
    @StateObject private var store = ProcessInfo.processInfo.arguments.contains("--sample")
        ? Store(sample: ()) : Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Brand.text)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            if store.isLinked { SeasonView() } else { LinkView() }
        }
    }
}

/// Before anything is linked. The phone reads a leaderboard; it never sees this computer's accounts,
/// so there is nothing to set up beyond saying who you are.
struct LinkView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            KeyhopMark(size: 44)
            Text("Keyhop")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Brand.text)
                .padding(.top, 18)
            Text("Your season, standings and quests.")
                .font(.system(size: 15))
                .foregroundStyle(Brand.muted)
                .padding(.top, 6)

            if let pending = store.pending {
                Card {
                    VStack(spacing: 10) {
                        Text("Approve this code")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Brand.text)
                        Text(pending.userCode)
                            .font(.system(size: 26, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Brand.text)
                            .tracking(2)
                        Text("Keyhop opened your browser. This screen notices by itself.")
                            .font(.system(size: 13))
                            .foregroundStyle(Brand.subtle)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 32)

                Button("Cancel") { store.cancelLink() }
                    .font(.system(size: 15))
                    .foregroundStyle(Brand.muted)
                    .padding(.top, 16)
            } else {
                Button {
                    Task { await store.startLink() }
                } label: {
                    Text("Link with GitHub")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Brand.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Brand.text, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.top, 36)

                Text("Keyhop sends daily totals from your computer. This phone only reads them.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.subtle)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
            }

            if let problem = store.problem {
                Text(problem)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.41))
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
    }
}

/// Once linked: where this season stands, then the board, the quests and the badges.
struct SeasonView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAlerts = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    problem
                    limits
                    standing
                    quests
                    badges
                    board
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Brand.background)
            .navigationTitle("Keyhop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Alerts") { showingAlerts = true }
                        if let url = store.link?.profileURL {
                            Link("Open my profile", destination: url)
                        }
                        Button("Unlink this phone", role: .destructive) { Task { await store.unlink() } }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Brand.muted)
                    }
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

    @ViewBuilder private var problem: some View {
        if let message = store.problem {
            Card {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.wrong)
                    .padding(16)
            }
        }
    }

    /// Where the accounts stand, when the computer is sharing it. The two arms of the mark carry the
    /// two nearest limits, the same way they do in the Mac's menu bar.
    @ViewBuilder private var limits: some View {
        let accounts = store.limitAccounts
        if accounts.isEmpty {
            if store.season != nil || store.board != nil {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("See your limits here")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Brand.text)
                        Text("In Keyhop on your computer, open Settings and choose Share limits. This phone can then tell you when an account comes back.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Brand.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                }
            }
        } else {
            Card {
                // Ticks with the clock, so a countdown on screen is never a stale number.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            KeyhopMark(size: 18, arms: nearest(accounts))
                            Text("Limits")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Brand.text)
                            Spacer(minLength: 8)
                            if let updated = store.limits.updated {
                                Text(sent(updated, at: context.date))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Brand.subtle)
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
        let seconds = Int(now.timeIntervalSince(updated))
        if seconds < 90 { return "just now" }
        return "\(Format.until(now, from: updated)) ago"
    }
    private var standing: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let season = store.season {
                    HStack(spacing: 12) {
                        TierMark(key: season.you?.tier.key ?? "bronze", height: 22)
                        Text(Format.tier(season.you?.tier ?? .init(key: "bronze", name: "Bronze", division: 3)))
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Brand.tier(season.you?.tier.key ?? "bronze"))
                        Spacer()
                        Text(season.over ? "Finished" : "\(season.daysLeft) days left")
                            .font(.system(size: 13))
                            .foregroundStyle(Brand.subtle)
                    }
                    Text(season.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Brand.text)
                    if let you = season.you {
                        Text(you.rank.map { "#\($0) of \(season.players) · \(Format.tokens(you.tokens)) tokens" }
                            ?? "Not ranked yet this season")
                            .font(.system(size: 13))
                            .foregroundStyle(Brand.muted)
                        if let next = you.next {
                            Text("\(Format.tokens(next.tokens)) more for \(next.label)")
                                .font(.system(size: 13))
                                .foregroundStyle(Brand.subtle)
                        }
                    }
                } else {
                    Text(store.loading ? "Reading your season…" : "No season yet")
                        .font(.system(size: 14))
                        .foregroundStyle(Brand.muted)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder private var badges: some View {
        if let badges = store.quests?.badges, !badges.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Badges")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.text)
                        .padding(.bottom, 12)
                    ForEach(Array(badges.enumerated()), id: \.element.key) { index, badge in
                        if index > 0 { Divider().overlay(Brand.border).padding(.vertical, 10) }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: badge.earned ? "checkmark.seal.fill" : "seal")
                                .foregroundStyle(badge.earned ? Brand.good : Brand.subtle)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(badge.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Brand.text)
                                Text(badge.note)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Brand.muted)
                            }
                            Spacer(minLength: 8)
                            Text(badge.earned ? "Earned" : "Locked")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(badge.earned ? Brand.good : Brand.subtle)
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    @ViewBuilder private var quests: some View {
        if let list = store.quests?.quests, !list.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Quests")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.text)
                        .padding(.bottom, 12)
                    ForEach(Array(list.enumerated()), id: \.element.key) { index, quest in
                        if index > 0 { Divider().overlay(Brand.border).padding(.vertical, 10) }
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(quest.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Brand.text)
                                Text(quest.note)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Brand.muted)
                            }
                            Spacer(minLength: 8)
                            Text(quest.complete ? "Done" : "\(Int((Double(quest.done) / Double(max(quest.target, 1))) * 100))%")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(quest.complete ? Brand.good : Brand.subtle)
                        }
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
                    Text("This week")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.text)
                        .padding(.bottom, 12)
                    ForEach(Array(entries.prefix(10).enumerated()), id: \.element.login) { index, entry in
                        if index > 0 { Divider().overlay(Brand.border).padding(.vertical, 9) }
                        HStack(spacing: 12) {
                            Text("\(entry.rank)")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Brand.subtle)
                                .frame(width: 22, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name ?? entry.login)
                                    .font(.system(size: 14, weight: entry.isYou ? .semibold : .regular))
                                    .foregroundStyle(Brand.text)
                                Text("@\(entry.login)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Brand.subtle)
                            }
                            Spacer(minLength: 8)
                            Text(Format.tokens(entry.tokens))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Brand.muted)
                        }
                    }
                }
                .padding(18)
            }
        }
    }
}

/// One account's windows. Every row sits on the same columns, so the measures and the countdowns
/// line up down the card however long a window's name happens to be.
struct LimitRows: View {
    let account: LimitAccount
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(account.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.text)
                Spacer(minLength: 8)
                // Only while the account is actually spent: with room left this repeated a number
                // the rows below already carry.
                if let tightest = account.tightest, tightest.usedPercent >= AlertPlan.fullEnough,
                   let reset = tightest.resetDate, reset > now {
                    Text("back in \(Format.until(reset, from: now))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.subtle)
                        .fixedSize()
                }
            }
            ForEach(account.windows) { window in
                HStack(spacing: 12) {
                    Text(window.windowLabel)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.muted)
                        .frame(width: 46, alignment: .leading)
                    CapacityTrack(usedPercent: window.usedPercent)
                    Text("\(Int(window.usedPercent.rounded()))%")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(window.usedPercent >= 95 ? Brand.spent : Brand.muted)
                        .fixedSize()
                        .frame(width: 44, alignment: .trailing)
                    Text(window.resetDate.map { $0 > now ? Format.until($0, from: now) : "now" } ?? "")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Brand.subtle)
                        // Wide enough for the longest countdown ("4d 15h") at its natural width, so
                        // nothing is ever squeezed to fit.
                        .fixedSize()
                        .frame(width: 64, alignment: .trailing)
                }
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

/// What the phone may say, and whether iOS is letting it.
struct AlertsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            row(title: "When a limit comes back",
                                note: "Only for an account that is nearly spent, at the moment it resets.",
                                on: $store.alertsForLimits)
                            Divider().overlay(Brand.border).padding(.vertical, 12)
                            row(title: "Seasons and quests",
                                note: "The season's last evening, and tonight if today's goals are still open.",
                                on: $store.alertsForSeason)
                        }
                        .padding(18)
                    }

                    if store.notificationsAllowed == false {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notifications are off for Keyhop")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Brand.text)
                                Text("Turn them on in iOS Settings and these come back.")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Brand.muted)
                            }
                            .padding(18)
                        }
                    }

                    Text("Every alert is set on this phone, against a moment Keyhop already knows. Nothing is pushed to you, and nothing about what you asked or wrote ever leaves your computer.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Brand.background)
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Brand.text)
                }
            }
        }
        .task { await store.readAlertPermission() }
    }

    private func row(title: String, note: String, on: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.text)
                Text(note)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { on.wrappedValue }, set: { asked in
                on.wrappedValue = asked
                // The prompt arrives with a reason attached: they just asked for this alert.
                if asked { Task { await store.allowAlerts() } }
            }))
            .labelsHidden()
            .tint(Brand.good)
            .accessibilityLabel(title)
        }
    }
}
