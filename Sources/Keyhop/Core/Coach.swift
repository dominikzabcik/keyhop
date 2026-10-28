import Foundation

/// Efficiency coaching from this computer's own store: where the last thirty days' spend went and
/// what it produced. Three readings, nothing sent anywhere.
///
/// - optimize: cache hit and premium-model share per tool, the heaviest sessions, and what to change.
/// - compare: the last thirty days against the thirty before.
/// - yield: tokens and API value per commit and per merge, from the repositories Keyhop counts.
struct CoachReport: Encodable {
    struct ToolMix: Encodable {
        let tool: Provider
        let toolName: String
        let tokens: Int
        let apiValue: Double
        /// Cache reads over all context read (input plus cache reads), in percent. Nil without context.
        let cacheHit: Double?
        /// The share of API value spent on premium models, in percent.
        let premiumShare: Double
    }

    struct HeavySession: Encodable {
        let tool: Provider
        let toolName: String
        let model: String
        let from: Date
        let minutes: Int
        let tokens: Int
        let apiValue: Double
        /// This session's share of the period's API value, in percent.
        let share: Double
    }

    struct Finding: Encodable {
        let kind: String
        let text: String
    }

    struct Optimize: Encodable {
        let tools: [ToolMix]
        let sessions: [HeavySession]
        let findings: [Finding]
    }

    struct Delta: Encodable {
        let label: String
        let now: Double
        let before: Double
        /// Percent change, or nil when the earlier period was empty.
        let change: Double?
    }

    struct Compare: Encodable {
        let tokens: Delta
        let apiValue: Delta
        let requests: Delta
        let cacheHit: Delta
        let tools: [Delta]
        let models: [Delta]
    }

    struct RepoYield: Encodable {
        let repo: String
        let path: String
        let commits: Int
        let merges: Int
        let tokens: Int
        let apiValue: Double
        let tokensPerCommit: Int?
        let valuePerMerge: Double?
    }

    struct Yield: Encodable {
        let enabled: Bool
        let commits: Int
        let merges: Int
        let tokens: Int
        let apiValue: Double
        let tokensPerCommit: Int?
        let valuePerCommit: Double?
        let tokensPerMerge: Int?
        let valuePerMerge: Double?
        let repos: [RepoYield]
        let note: String?
    }

    let days: Int
    let optimize: Optimize
    let compare: Compare
    let yield: Yield

    /// Output priced at or above this, in dollars per million, counts as a premium model.
    static let premiumOutput = 15.0

    static func build(digest: UsageDigest, sessions: [UsageDigest.Session], work: WorkYield?, days: Int = 30) -> CoachReport {
        CoachReport(days: days, optimize: optimize(digest: digest, sessions: sessions), compare: compare(digest: digest),
                    yield: yield(digest: digest, work: work))
    }

    static func cacheHit(_ tokens: TokenCounts) -> Double? {
        let context = tokens.input + tokens.cacheRead + tokens.cacheWrite + tokens.cacheWrite1h
        return context > 0 ? Double(tokens.cacheRead) / Double(context) * 100 : nil
    }

    static func isPremium(_ model: String) -> Bool {
        (Pricing.price(for: model)?.output ?? 0) >= premiumOutput
    }

    private static func optimize(digest: UsageDigest, sessions: [UsageDigest.Session]) -> Optimize {
        var tools: [ToolMix] = []
        for (provider, totals) in digest.byProvider where totals.tokens.total > 0 {
            let premium = digest.byModel.filter { $0.key.provider == provider && isPremium($0.key.model) }.reduce(0.0) { $0 + $1.value.cost }
            let share = totals.cost > 0 ? premium / totals.cost * 100 : 0
            tools.append(ToolMix(tool: provider, toolName: provider.name, tokens: totals.tokens.total, apiValue: round2(totals.cost),
                                 cacheHit: cacheHit(totals.tokens).map { ($0 * 10).rounded() / 10 }, premiumShare: (share * 10).rounded() / 10))
        }
        tools.sort { $0.apiValue > $1.apiValue }
        let total = max(digest.total.cost, 0.000001)
        let heavy = sessions.sorted { $0.totals.cost > $1.totals.cost }.prefix(5).map { session in
            HeavySession(tool: session.provider, toolName: session.provider.name, model: session.model, from: session.from,
                         minutes: Int(session.to.timeIntervalSince(session.from) / 60), tokens: session.totals.tokens.total,
                         apiValue: round2(session.totals.cost), share: (session.totals.cost / total * 1000).rounded() / 10)
        }
        var findings: [Finding] = []
        for mix in tools {
            if let hit = mix.cacheHit, hit < 40, mix.tokens >= 1_000_000 {
                findings.append(Finding(kind: "cache", text: "Only \(Int(hit.rounded()))% of \(mix.toolName)'s context came from cache. Longer sessions and fewer fresh starts raise it, and cached reads cost a tenth."))
            }
            if mix.premiumShare >= 70, mix.apiValue >= 5 {
                let saving = mix.apiValue * (mix.premiumShare / 100) * 0.6
                findings.append(Finding(kind: "premium", text: "\(Int(mix.premiumShare.rounded()))% of \(mix.toolName)'s API value went to premium models. Routine edits and searches on a cheaper model would keep about \(Numbers.usd(saving)) of it."))
            }
        }
        if let biggest = heavy.first, biggest.share >= 25 {
            findings.append(Finding(kind: "session", text: "One \(biggest.toolName) session on \(biggest.model) cost \(Numbers.usd(biggest.apiValue)), \(Int(biggest.share.rounded()))% of the period. Splitting work like that into shorter sessions keeps each context small."))
        }
        if findings.isEmpty && digest.total.requests > 0 {
            findings.append(Finding(kind: "fine", text: "Nothing stands out: cache hits are healthy and spend is spread across sessions."))
        }
        if digest.total.requests == 0 {
            findings.append(Finding(kind: "quiet", text: "No usage in the last thirty days to coach on."))
        }
        return Optimize(tools: tools, sessions: Array(heavy), findings: findings)
    }

    private static func delta(_ label: String, _ now: Double, _ before: Double) -> Delta {
        Delta(label: label, now: round2(now), before: round2(before), change: before > 0 ? ((now - before) / before * 1000).rounded() / 10 : nil)
    }

    private static func compare(digest: UsageDigest) -> Compare {
        let hitNow = cacheHit(digest.total.tokens) ?? 0
        let hitBefore = cacheHit(digest.previous.tokens) ?? 0
        // A tool or model that was used only before still gets a row, so a drop to nothing is seen.
        let toolKeys = Set(digest.byProvider.keys).union(digest.previousByProvider.keys)
        let tools = toolKeys.map { delta($0.name, digest.byProvider[$0]?.cost ?? 0, digest.previousByProvider[$0]?.cost ?? 0) }
            .sorted { ($0.now, $0.before) > ($1.now, $1.before) }
        let modelKeys = Set(digest.byModel.keys).union(digest.previousByModel.keys)
        let models = modelKeys.map { delta($0.description, digest.byModel[$0]?.cost ?? 0, digest.previousByModel[$0]?.cost ?? 0) }
            .sorted { ($0.now, $0.before) > ($1.now, $1.before) }.prefix(8)
        return Compare(tokens: delta("Tokens", Double(digest.total.tokens.total), Double(digest.previous.tokens.total)),
                       apiValue: delta("API value", digest.total.cost, digest.previous.cost),
                       requests: delta("Requests", Double(digest.total.requests), Double(digest.previous.requests)),
                       cacheHit: Delta(label: "Cache hit", now: (hitNow * 10).rounded() / 10, before: (hitBefore * 10).rounded() / 10,
                                       change: hitBefore > 0 ? ((hitNow - hitBefore) * 10).rounded() / 10 : nil),
                       tools: tools, models: Array(models))
    }

    private static func yield(digest: UsageDigest, work: WorkYield?) -> Yield {
        guard let work, work.enabled else {
            return Yield(enabled: false, commits: 0, merges: 0, tokens: digest.total.tokens.total, apiValue: round2(digest.total.cost),
                         tokensPerCommit: nil, valuePerCommit: nil, tokensPerMerge: nil, valuePerMerge: nil, repos: [],
                         note: "Turn commit counting on under Settings, Activity, and Keyhop will say what each commit and each merge cost.")
        }
        var repos: [RepoYield] = []
        for repo in work.repos {
            // Usage that a tool placed inside this repository's folder.
            let inside = digest.byProject.filter { $0.key == repo.path || $0.key.hasPrefix(repo.path + "/") }
            let totals = inside.values.reduce(Totals(), +)
            repos.append(RepoYield(repo: repo.name, path: repo.path, commits: repo.commits, merges: repo.merges,
                                   tokens: totals.tokens.total, apiValue: round2(totals.cost),
                                   tokensPerCommit: repo.commits > 0 && totals.tokens.total > 0 ? totals.tokens.total / repo.commits : nil,
                                   valuePerMerge: repo.merges > 0 && totals.cost > 0 ? round2(totals.cost / Double(repo.merges)) : nil))
        }
        repos.sort { ($0.commits, $0.tokens) > ($1.commits, $1.tokens) }
        let commits = repos.reduce(0) { $0 + $1.commits }
        let merges = repos.reduce(0) { $0 + $1.merges }
        // Per commit and per merge count only the usage a tool placed inside the counted repositories,
        // the same figure each row shows, so work elsewhere never inflates what a commit cost.
        let inside = repos.reduce(0) { $0 + $1.tokens }
        let insideValue = repos.reduce(0.0) { $0 + $1.apiValue }
        let note: String? = commits == 0 ? "No commits of yours in these repositories in the last thirty days."
            : inside == 0 ? "No usage was placed inside the counted repositories, so nothing can be laid against the commits yet."
            : nil
        return Yield(enabled: true, commits: commits, merges: merges, tokens: digest.total.tokens.total, apiValue: round2(digest.total.cost),
                     tokensPerCommit: commits > 0 && inside > 0 ? inside / commits : nil,
                     valuePerCommit: commits > 0 && inside > 0 ? round2(insideValue / Double(commits)) : nil,
                     tokensPerMerge: merges > 0 && inside > 0 ? inside / merges : nil,
                     valuePerMerge: merges > 0 && inside > 0 ? round2(insideValue / Double(merges)) : nil,
                     repos: repos,
                     note: note)
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

/// What the counted repositories produced in a period: commits you authored and merges that landed.
struct WorkYield {
    struct Repo {
        let name: String
        let path: String
        let commits: Int
        let merges: Int
    }

    let enabled: Bool
    let repos: [Repo]

    /// Reads every counted repository. Merges are the merge commits the person landed along the first
    /// parent of the current branch: a pull request they merged, or a branch they folded in by hand.
    ///
    /// Only counts are needed, so no per-file statistics are read, and the repositories are read side
    /// by side: each is its own git process with nothing shared.
    static func read(settings: WorkSettings, since day: String, login: String?) -> WorkYield {
        guard settings.enabled, GitWork.isAvailable else { return WorkYield(enabled: false, repos: []) }
        let found = GitWork.repositories(under: settings.rootURLs)
        let slots = Slots(count: found.count)
        DispatchQueue.concurrentPerform(iterations: found.count) { i in
            let repo = found[i]
            let mine = GitWork.identities(repo: repo, extra: settings.emails, login: login)
            let commits = GitWork.commits(in: repo, since: day, mine: mine, stats: false).count
            let merges = GitWork.merges(in: repo, since: day, mine: mine)
            guard commits > 0 || merges > 0 else { return }
            slots.put(i, Repo(name: GitWork.name(of: repo), path: repo.path, commits: commits, merges: merges))
        }
        return WorkYield(enabled: true, repos: slots.values)
    }

    /// One slot per repository, filled from many threads, read back in the order they were found.
    private final class Slots: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Repo?]
        init(count: Int) { items = Array(repeating: nil, count: count) }
        func put(_ i: Int, _ repo: Repo) { lock.lock(); items[i] = repo; lock.unlock() }
        var values: [Repo] { lock.lock(); defer { lock.unlock() }; return items.compactMap { $0 } }
    }
}
