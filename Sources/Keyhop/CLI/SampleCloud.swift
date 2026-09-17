import Foundation

extension SampleData {
    /// Made-up people for `keyhop dashboard --sample`, ranked the way the website ranks them.
    static func leaderboard(period: String, metric: String, team: String?) -> DashboardLeaderboard {
        let days: Double = ["today": 1, "week": 7, "month": 30, "all": 180][period] ?? 7
        // Millions of tokens a day, and each supported tool's share.
        let people: [(login: String, name: String?, daily: Double, mix: [Double], you: Bool, onTeam: Bool)] = [
            ("mira", "Mira K.", 9.1, [0.6, 0.2, 0.1, 0.1], false, true),
            ("jonas", nil, 7.4, [0.2, 0.55, 0.1, 0.15], false, true),
            ("you", "You", 6.2, [0.45, 0.15, 0.25, 0.15], true, true),
            ("priya", "Priya", 5.0, [0.4, 0.1, 0.3, 0.2], false, false),
            ("tomas", nil, 2.9, [0.1, 0.65, 0.1, 0.15], false, true),
            ("alex", nil, 1.6, [0.35, 0.1, 0.35, 0.2], false, false),
        ]
        let prices = [4.2, 2.1, 3.1, 2.0]
        let tools = ["claude", "cursor", "codex", "gemini"]
        let rows = people.filter { team == nil || $0.onTeam }.map { person -> (person: (login: String, name: String?, daily: Double, mix: [Double], you: Bool, onTeam: Bool), tokens: Int, cost: Double, requests: Int, split: [String: Int]) in
            let split = Dictionary(uniqueKeysWithValues: tools.enumerated().map { ($1, Int(person.daily * days * 1_000_000 * person.mix[$0])) })
            let tokens = split.values.reduce(0, +)
            let cost = tools.enumerated().reduce(0.0) { $0 + Double(split[$1.element] ?? 0) / 1_000_000 * prices[$1.offset] }
            return (person, tokens, (cost * 100).rounded() / 100, tokens / 42_000, split)
        }
        let sorted = rows.sorted {
            switch metric {
            case "cost": $0.cost > $1.cost
            case "requests": $0.requests > $1.requests
            default: $0.tokens > $1.tokens
            }
        }
        let entries = sorted.enumerated().map { index, row in
            CloudBoard.Entry(rank: index + 1, login: row.person.login, name: row.person.name, avatarUrl: nil, isPublic: true,
                             tokens: row.tokens, cost: row.cost, requests: row.requests, activeDays: min(Int(days), Int(days * 0.8) + 1),
                             tools: row.split, isYou: row.person.you)
        }
        let sampleQuests = CloudQuests(
            quests: [
                CloudQuests.Quest(key: "today", name: "Get going", note: "Use any tool today.", period: "day", done: 1, target: 1, complete: true),
                CloudQuests.Quest(key: "two-tools", name: "Two tools", note: "Use two different tools today.", period: "day", done: 1, target: 2, complete: false),
                CloudQuests.Quest(key: "beat-yesterday", name: "Beat yesterday", note: "Pass yesterday's 6,200K tokens.", period: "day", done: 4_100_000, target: 6_200_000, complete: false),
                CloudQuests.Quest(key: "five-days", name: "Five days", note: "Use Keyhop on five days this week.", period: "week", done: 5, target: 5, complete: true),
                CloudQuests.Quest(key: "every-tool", name: "Every tool", note: "Use all 6 tracked tools this week.", period: "week", done: 6, target: 6, complete: true),
                CloudQuests.Quest(key: "beat-last-week", name: "Beat last week", note: "Pass last week's total.", period: "week", done: 38_000_000, target: 44_000_000, complete: false),
            ],
            badges: [])

        // The sample season counts the same made-up people over a month.
        let mine = rows.first { $0.person.you }
        let seasonTokens = Int((mine?.person.daily ?? 0) * 26 * 1_000_000)
        let season = CloudSeason(
            season: "2026-09", label: "September 2026", daysLeft: 18, over: false, players: entries.count,
            you: CloudSeason.You(rank: 3, tokens: seasonTokens,
                                 tier: CloudSeason.Tier(key: "silver", name: "Silver", division: 2),
                                 next: CloudSeason.Step(label: "Silver I", tokens: 94_000_000)))
        return DashboardLeaderboard(board: CloudBoard(period: period, metric: metric, entries: entries),
                                    teams: [CloudTeam(slug: "night-shift", name: "Night Shift", role: "member", members: 4)],
                                    team: team, website: "https://keyhop.example", season: season, quests: sampleQuests)
    }
}
