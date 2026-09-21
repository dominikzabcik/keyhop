import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Whether a tool's own service is up, from the provider's public status page.
///
/// When Claude Code is slow or failing, the first question is whether it's the account or the
/// service. An account at its limit is worth switching away from; an outage follows every
/// account. Each provider publishes a status page, and Keyhop reads the parts of it that the
/// tool depends on. Nothing about the person is sent: these are plain requests for public pages.
struct ServiceHealth: Encodable, Equatable, Sendable {
    let tool: String
    let name: String
    /// The page a person would open to read more.
    let page: String
    let level: Level
    let incidents: [Incident]

    enum Level: String, Encodable, Comparable, Sendable {
        /// The page couldn't be read, so nothing is known either way.
        case unknown
        case operational
        case maintenance
        case degraded
        case partialOutage = "partial"
        case majorOutage = "major"

        private var rank: Int {
            switch self {
            case .unknown: 0
            case .operational: 1
            case .maintenance: 2
            case .degraded: 3
            case .partialOutage: 4
            case .majorOutage: 5
            }
        }

        static func < (a: Level, b: Level) -> Bool { a.rank < b.rank }

        var words: String {
            switch self {
            case .unknown: "Status unavailable"
            case .operational: "Operational"
            case .maintenance: "Under maintenance"
            case .degraded: "Degraded performance"
            case .partialOutage: "Partial outage"
            case .majorOutage: "Major outage"
            }
        }

        /// A status page's word for a component.
        init(component: String) {
            switch component {
            case "operational": self = .operational
            case "under_maintenance": self = .maintenance
            case "degraded_performance": self = .degraded
            case "partial_outage": self = .partialOutage
            case "major_outage": self = .majorOutage
            default: self = .unknown
            }
        }

        /// A status page's word for how badly an incident hurts.
        init(impact: String) {
            switch impact {
            case "minor": self = .degraded
            case "major": self = .partialOutage
            case "critical": self = .majorOutage
            case "maintenance": self = .maintenance
            default: self = .degraded
            }
        }
    }

    struct Incident: Encodable, Equatable, Sendable {
        let name: String
        /// Investigating, identified, monitoring, or in progress for maintenance.
        let stage: String
        let updated: Date?
        let link: String?
    }

    /// Worth telling someone about: anything short of working normally.
    var isTrouble: Bool { level > .operational }
}

enum ServiceStatus {
    struct Page: Sendable {
        let name: String
        let url: String
        /// The components this tool depends on, by the name the page gives them.
        let components: Set<String>
    }

    /// Tools whose provider runs a status page with a public API. Gemini CLI has none of its own,
    /// and OpenCode, Pi and Codebuff reach models through other providers' services.
    static let pages: [Provider: Page] = [
        .claude: Page(name: "Claude", url: "https://status.claude.com",
                      components: ["Claude Code", "Claude API (api.anthropic.com)", "claude.ai"]),
        .codex: Page(name: "OpenAI", url: "https://status.openai.com",
                     components: ["CLI", "Codex API", "Codex Web", "VS Code extension", "Login"]),
        .cursor: Page(name: "Cursor", url: "https://status.cursor.com", components: ["IDE", "CLI", "Cloud Agents"]),
        .copilot: Page(name: "GitHub", url: "https://www.githubstatus.com", components: ["Copilot", "Copilot AI Model Providers"]),
        .windsurf: Page(name: "Windsurf", url: "https://status.windsurf.com", components: ["Cascade", "Windsurf Tab"]),
    ]

    private static let cache = Cache()

    /// The status for each of these tools that has a page, most troubled first. Pages are read at
    /// most every five minutes; one that can't be read shows as unknown rather than as fine.
    static func check(_ tools: [Provider], now: Date = Date()) async -> [ServiceHealth] {
        let wanted = tools.filter { pages[$0] != nil }
        let results = await withTaskGroup(of: ServiceHealth.self) { group in
            for tool in wanted {
                group.addTask { await health(tool, now: now) }
            }
            var all: [ServiceHealth] = []
            for await result in group { all.append(result) }
            return all
        }
        return sorted(results)
    }

    /// Most troubled first, then in the order tools are listed everywhere else.
    static func sorted(_ results: [ServiceHealth]) -> [ServiceHealth] {
        func order(_ health: ServiceHealth) -> Int {
            Provider(rawValue: health.tool).flatMap { Provider.allCases.firstIndex(of: $0) } ?? Int.max
        }
        return results.sorted { $0.level != $1.level ? $0.level > $1.level : order($0) < order($1) }
    }

    private static func health(_ tool: Provider, now: Date) async -> ServiceHealth {
        let page = pages[tool]!
        if let known = cache.get(tool, now: now) { return known }
        var request = URLRequest(url: URL(string: page.url + "/api/v2/summary.json")!, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("keyhop/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let result: ServiceHealth
        if let (data, status) = try? await HTTP.send(request), status == 200 {
            result = parse(data, tool: tool, page: page)
        } else {
            result = ServiceHealth(tool: tool.rawValue, name: page.name, page: page.url, level: .unknown, incidents: [])
        }
        // An unreadable page is tried again sooner, so a blip doesn't hide an outage for long.
        cache.set(tool, result, until: now.addingTimeInterval(result.level == .unknown ? 60 : 300))
        return result
    }

    /// Reads a Statuspage-style summary: the worst of this tool's components, and the open
    /// incidents and maintenance that touch them. An incident that names no components could be
    /// about anything on the page, so it's counted too.
    static func parse(_ data: Data, tool: Provider, page: Page) -> ServiceHealth {
        let unknown = ServiceHealth(tool: tool.rawValue, name: page.name, page: page.url, level: .unknown, incidents: [])
        guard let body = JSON.object(data) else { return unknown }
        let components = (body["components"] as? [[String: Any]] ?? [])
            .filter { page.components.contains($0["name"] as? String ?? "") }
        var level = components.map { ServiceHealth.Level(component: $0["status"] as? String ?? "") }
            .filter { $0 != .unknown }.max() ?? .unknown
        guard level != .unknown || !components.isEmpty || body["page"] != nil else { return unknown }
        if level == .unknown { level = .operational }

        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainDates = ISO8601DateFormatter()
        func date(_ value: Any?) -> Date? {
            guard let text = value as? String else { return nil }
            return dates.date(from: text) ?? plainDates.date(from: text)
        }

        var incidents: [ServiceHealth.Incident] = []
        let open = (body["incidents"] as? [[String: Any]] ?? [])
            + (body["scheduled_maintenances"] as? [[String: Any]] ?? []).filter { ($0["status"] as? String) == "in_progress" }
        for incident in open {
            let status = incident["status"] as? String ?? ""
            guard status != "resolved", status != "completed", status != "postmortem" else { continue }
            let touched = (incident["components"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            guard touched.isEmpty || touched.contains(where: page.components.contains) else { continue }
            let impact = ServiceHealth.Level(impact: incident["impact"] as? String ?? "")
            level = max(level, impact)
            incidents.append(ServiceHealth.Incident(
                name: (incident["name"] as? String ?? "Incident").trimmingCharacters(in: .whitespacesAndNewlines),
                stage: status.replacingOccurrences(of: "_", with: " "),
                updated: date(incident["updated_at"]),
                link: incident["shortlink"] as? String))
        }
        return ServiceHealth(tool: tool.rawValue, name: page.name, page: page.url, level: level, incidents: incidents)
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [Provider: (ServiceHealth, Date)] = [:]

        func get(_ tool: Provider, now: Date) -> ServiceHealth? {
            lock.lock()
            defer { lock.unlock() }
            guard let (health, until) = entries[tool], until > now else { return nil }
            return health
        }

        func set(_ tool: Provider, _ health: ServiceHealth, until: Date) {
            lock.lock()
            entries[tool] = (health, until)
            lock.unlock()
        }
    }
}
