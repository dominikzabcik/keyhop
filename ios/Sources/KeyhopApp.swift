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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    standing
                    quests
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
                        if let url = store.link?.profileURL {
                            Link("Open my profile", destination: url)
                        }
                        Button("Unlink this phone", role: .destructive) { store.unlink() }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Brand.muted)
                    }
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
        }
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
