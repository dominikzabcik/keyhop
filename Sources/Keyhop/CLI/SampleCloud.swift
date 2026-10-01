import Foundation

extension SampleData {
    static func pet() -> CloudPet { .sample }

    /// Made-up people for `keyhop dashboard --sample`, ranked the way the website ranks them.
    static func leaderboard(period: String, metric: String, team: String?, season asked: String? = nil) -> DashboardLeaderboard {
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
        let rows = people.filter { team == nil || $0.onTeam }.map { person -> (person: (login: String, name: String?, daily: Double, mix: [Double], you: Bool, onTeam: Bool), tokens: Int, cost: Double, requests: Int, commits: Int, split: [String: Int]) in
            let split = Dictionary(uniqueKeysWithValues: tools.enumerated().map { ($1, Int(person.daily * days * 1_000_000 * person.mix[$0])) })
            let tokens = split.values.reduce(0, +)
            let cost = tools.enumerated().reduce(0.0) { $0 + Double(split[$1.element] ?? 0) / 1_000_000 * prices[$1.offset] }
            return (person, tokens, (cost * 100).rounded() / 100, tokens / 42_000, Int(person.daily * days), split)
        }
        let sorted = rows.sorted {
            switch metric {
            case "cost": $0.cost > $1.cost
            case "requests": $0.requests > $1.requests
            case "commits": $0.commits > $1.commits
            case "lines": $0.commits > $1.commits
            default: $0.tokens > $1.tokens
            }
        }
        let entries = sorted.enumerated().map { index, row in
            CloudBoard.Entry(rank: index + 1, login: row.person.login, name: row.person.name, avatarUrl: nil, isPublic: true,
                             tokens: row.tokens, cost: row.cost, requests: row.requests, activeDays: min(Int(days), Int(days * 0.8) + 1),
                             tools: row.split, isYou: row.person.you, commits: row.commits, insertions: row.commits * 40, deletions: row.commits * 6)
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
            badges: [
                CloudQuests.Badge(key: "streak", name: "Five days", note: "Use Keyhop on five days in a week.", earned: true, day: "2026-09-20"),
                CloudQuests.Badge(key: "house", name: "Full house", note: "Use every tracked tool in a week.", earned: false, day: nil),
            ])

        // The sample season counts the same made-up people over a month.
        let mine = rows.first { $0.person.you }
        let seasonTokens = Int((mine?.person.daily ?? 0) * 26 * 1_000_000)
        let silver = CloudSeason.Tier(key: "silver", name: "Silver", division: 2)
        let earlier = asked == "2026-08"
        let season = CloudSeason(
            season: earlier ? "2026-08" : "2026-09", label: earlier ? "August 2026" : "September 2026",
            daysLeft: earlier ? 0 : 18, over: earlier, players: entries.count,
            you: CloudSeason.You(rank: 3, tokens: seasonTokens,
                                 tier: silver,
                                 next: CloudSeason.Step(label: "Silver I", tokens: 94_000_000)),
            entries: [
                CloudSeason.Standing(rank: 1, login: "mira", name: "Mira K.", tokens: 240_000_000, isYou: false, tier: CloudSeason.Tier(key: "gold", name: "Gold", division: 3)),
                CloudSeason.Standing(rank: 2, login: "jonas", name: nil, tokens: 180_000_000, isYou: false, tier: silver),
                CloudSeason.Standing(rank: 3, login: "you", name: "You", tokens: seasonTokens, isYou: true, tier: silver),
            ],
            seasons: [
                CloudSeason.SeasonRef(id: "2026-09", label: "September 2026"),
                CloudSeason.SeasonRef(id: "2026-08", label: "August 2026"),
            ])
        let members: [CloudMember]
        switch team {
        case "studio":
            members = [
                CloudMember(login: "you", name: "You", role: "owner"),
                CloudMember(login: "mira", name: "Mira K.", role: "member"),
            ]
        case "night-shift": members = Self.nightShift
        default: members = []
        }
        return DashboardLeaderboard(board: CloudBoard(period: period, metric: metric, entries: entries),
                                    teams: Self.sampleTeams, team: team, website: "https://keyhop.example",
                                    season: season, quests: sampleQuests, members: members)
    }

    /// A made-up team day, so the window can show the same reading the website would.
    static func day(team _: String?, date: String?) -> DashboardDay {
        let today = utcDay()
        let asked = date.flatMap { $0.isEmpty ? nil : $0 } ?? today
        let day = asked > today ? today : asked
        let following = shift(day, by: 1)
        let named = CloudTeamDay.Team(slug: "night-shift", name: "Night Shift")
        let quiet = day != today
        let people = quiet
            ? [person(login: "you", name: "You", you: true, tokens: 1_200_000, title: "Notes",
                      subject: "write down what yesterday shipped", sha: "a1b2c3d", commits: 1, insertions: 20, deletions: 2)]
            : [
                person(login: "mira", name: "Mira K.", you: false, tokens: 9_100_000, title: "Auth",
                       subject: "keep the session alive", sha: "f00ba12", commits: 1, insertions: 140, deletions: 18),
                person(login: "you", name: "You", you: true, tokens: 6_200_000, title: "Day",
                       subject: "read a day back as the work it was", sha: "c0ffee1", commits: 1, insertions: 80, deletions: 9),
            ]
        return DashboardDay(teams: sampleTeams, team: named, day: day, today: today, previous: shift(day, by: -1),
                            next: following <= today ? following : nil, people: people, website: "https://keyhop.example",
                            members: nightShift)
    }

    private static func person(login: String, name: String, you: Bool, tokens: Int, title: String, subject: String,
                               sha: String, commits: Int, insertions: Int, deletions: Int) -> CloudTeamDay.Person {
        let line = CloudTeamDay.Line(sha: sha, subject: subject, repo: "acme/atlas")
        let task = CloudTeamDay.Task(title: title, repos: ["acme/atlas"], insertions: insertions, deletions: deletions,
                                  span: "09:12 to 11:40", commits: [line])
        let repo = CloudTeamDay.Repo(repo: "acme/atlas", commits: commits, insertions: insertions, deletions: deletions)
        return CloudTeamDay.Person(login: login, name: name, isYou: you, tokens: tokens, commits: commits,
                               insertions: insertions, deletions: deletions, indexing: nil, repos: [repo], tasks: [task])
    }

    static let sampleTeams = [
        CloudTeam(slug: "night-shift", name: "Night Shift", role: "member", members: 4),
        CloudTeam(slug: "studio", name: "Studio", role: "owner", members: 2),
    ]

    static let nightShift = [
        CloudMember(login: "mira", name: "Mira K.", role: "owner"),
        CloudMember(login: "you", name: "You", role: "member"),
    ]

    private static func utcDay(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func shift(_ day: String, by days: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return day }
        return formatter.string(from: date.addingTimeInterval(Double(days) * 86_400))
    }
}
