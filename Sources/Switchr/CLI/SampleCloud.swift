import Foundation

extension SampleData {
    /// Made-up people for `switchr dashboard --sample`, ranked the way the website ranks them.
    static func leaderboard(period: String, metric: String, team: String?) -> DashboardLeaderboard {
        let days: Double = ["today": 1, "week": 7, "month": 30, "all": 180][period] ?? 7
        // Millions of tokens a day, and the Claude, Cursor and Codex shares.
        let people: [(login: String, name: String?, daily: Double, mix: [Double], you: Bool, onTeam: Bool)] = [
            ("mira", "Mira K.", 9.1, [0.7, 0.2, 0.1], false, true),
            ("jonas", nil, 7.4, [0.3, 0.6, 0.1], false, true),
            ("you", "You", 6.2, [0.55, 0.15, 0.3], true, true),
            ("priya", "Priya", 5.0, [0.5, 0.1, 0.4], false, false),
            ("tomas", nil, 2.9, [0.1, 0.8, 0.1], false, true),
            ("alex", nil, 1.6, [0.45, 0.1, 0.45], false, false),
        ]
        let prices = [4.2, 2.1, 3.1]
        let tools = ["claude", "cursor", "codex"]
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
        return DashboardLeaderboard(board: CloudBoard(period: period, metric: metric, entries: entries),
                                    teams: [CloudTeam(slug: "night-shift", name: "Night Shift", role: "member", members: 4)],
                                    team: team, website: "https://switchr.example")
    }
}
