import Foundation

// What the tray shows, built from `keyhop status --json`. Nothing here touches Win32, so it
// compiles and runs on every system; `KeyhopTray --print-menu status.json` prints the menu.

struct TrayStatus: Decodable {
    struct Spend: Decodable {
        let tokens: Int
        let cost: Double
        let requests: Int
    }

    struct Limit: Decodable {
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
    }

    struct Account: Decodable {
        let id: UUID
        let email: String
        let label: String?
        let name: String
        let plan: String?
        let active: Bool
        let limits: [Limit]
        let error: String?
    }

    struct Tool: Decodable {
        let id: String
        let name: String
        let signInHint: String
        let switchNote: String?
        let activeAccount: UUID?
        let accounts: [Account]
    }

    struct Alert: Decodable {
        let key: String
        let title: String
        let body: String
        let switchTo: UUID?
    }

    struct Budget: Decodable {
        let scope: String
        let name: String
        let amount: Double
        let period: String
        let spent: Double
    }

    let version: String
    let refreshedAt: Date?
    let today: Spend
    let tools: [Tool]
    let alerts: [Alert]
    let notices: [String]
    let budgets: [Budget]

    static func decode(_ data: Data) throws -> TrayStatus {
        try TrayJSON.decoder.decode(TrayStatus.self, from: data)
    }

    func account(_ id: UUID) -> (tool: Tool, account: Account)? {
        for tool in tools {
            if let account = tool.accounts.first(where: { $0.id == id }) { return (tool, account) }
        }
        return nil
    }

    /// The budget across all accounts, the one the tray lets you set.
    var overallBudget: Budget? {
        budgets.first { $0.scope == "all" }
    }
}

struct TrayActionResult: Decodable {
    let ok: Bool
    let message: String
    let account: UUID?
    let note: String?
}

struct TrayUpdate: Decodable {
    let current: String
    let latest: String
    let available: Bool
}

enum TrayJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum TrayCommand: Equatable, Hashable {
    case switchTo(UUID)
    case add(String)
    case refresh
    case openDashboard
    case rename(UUID)
    case remove(UUID)
    case budget
    case toggleAutoRefresh
    case toggleAutoInstall
    case toggleStartAtSignIn
    case installUpdate
    case checkForUpdates
    case quit
}

struct TraySettings: Equatable {
    var autoRefresh = true
    var autoInstallUpdates = true
    var startsAtSignIn = false
    /// False when a package manager owns the install, such as Scoop.
    var canSelfUpdate = true
    /// The package manager to update through when Keyhop can't update itself.
    var updatedBy: String?
}

struct TrayMenuItem: Equatable {
    var title: String
    var command: TrayCommand?
    var checked = false
    var enabled = true
    var isSeparator = false
    var children: [TrayMenuItem] = []

    static let separator = TrayMenuItem(title: "", isSeparator: true)

    /// Plain text rows (tool names, today's usage) are shown, but can't be chosen.
    var isLabel: Bool { command == nil && children.isEmpty && !checked }
}

enum TrayMenu {
    static func build(status: TrayStatus?, busy: String?, update: TrayUpdate?, settings: TraySettings, now: Date = Date()) -> [TrayMenuItem] {
        let idle = busy == nil
        var items: [TrayMenuItem] = [TrayMenuItem(title: "Open Keyhop", command: .openDashboard), .separator]
        if let busy {
            items.append(TrayMenuItem(title: busy, enabled: false))
            items.append(.separator)
        }

        if let status {
            for tool in status.tools {
                items.append(TrayMenuItem(title: tool.name, enabled: false))
                for account in tool.accounts {
                    let detail = self.detail(account)
                    items.append(TrayMenuItem(
                        title: detail.isEmpty ? account.name : "\(account.name)\t\(detail)",
                        command: account.active ? nil : .switchTo(account.id),
                        checked: account.active,
                        enabled: idle || account.active
                    ))
                }
                items.append(TrayMenuItem(title: tool.accounts.isEmpty ? "Save the signed-in account…" : "Add account…",
                                          command: .add(tool.id), enabled: idle))
                items.append(.separator)
            }
            if status.today.requests > 0 {
                items.append(TrayMenuItem(title: "Today: \(tokens(status.today.tokens)) tokens, \(usd(status.today.cost)) at API prices", enabled: false))
            }
            items.append(TrayMenuItem(title: status.refreshedAt.map { "Limits read \(relative($0, now: now))" } ?? "Limits not read yet", enabled: false))
        } else {
            items.append(TrayMenuItem(title: "Reading your accounts…", enabled: false))
        }

        items.append(TrayMenuItem(title: "Refresh now", command: .refresh, enabled: idle))

        if let status {
            let saved = status.tools.flatMap { tool in tool.accounts.map { (tool, $0) } }
            if !saved.isEmpty {
                items.append(TrayMenuItem(title: "Accounts", children: saved.map { tool, account in
                    TrayMenuItem(title: "\(tool.name): \(account.name)", children: [
                        TrayMenuItem(title: "Rename…", command: .rename(account.id), enabled: idle),
                        TrayMenuItem(title: account.active ? "Remove… (in use)" : "Remove…", command: .remove(account.id), enabled: idle && !account.active),
                    ])
                }))
            }
            items.append(TrayMenuItem(title: budgetTitle(status), command: .budget, enabled: idle))
        }

        items.append(.separator)
        items.append(TrayMenuItem(title: "Check usage automatically", command: .toggleAutoRefresh, checked: settings.autoRefresh))
        if settings.canSelfUpdate {
            items.append(TrayMenuItem(title: "Install updates automatically", command: .toggleAutoInstall, checked: settings.autoInstallUpdates))
        }
        items.append(TrayMenuItem(title: "Open at sign-in", command: .toggleStartAtSignIn, checked: settings.startsAtSignIn))
        if let update, update.available {
            if settings.canSelfUpdate {
                items.append(TrayMenuItem(title: "Update to \(update.latest)", command: .installUpdate, enabled: idle))
            } else {
                items.append(TrayMenuItem(title: "Keyhop \(update.latest) is available through \(settings.updatedBy ?? "your package manager")", enabled: false))
            }
        } else {
            items.append(TrayMenuItem(title: "Check for updates (\(status?.version ?? update?.current ?? "…"))", command: .checkForUpdates, enabled: idle))
        }
        items.append(TrayMenuItem(title: "Quit Keyhop", command: .quit))
        return items
    }

    static func budgetTitle(_ status: TrayStatus) -> String {
        guard let budget = status.overallBudget else { return "Set a budget…" }
        return "Budget: \(usd(budget.spent)) of \(usd(budget.amount)) per \(budget.period)…"
    }

    /// The tightest limit, or why there isn't one.
    static func detail(_ account: TrayStatus.Account) -> String {
        if let tightest = account.limits.max(by: { $0.usedPercent < $1.usedPercent }) {
            return "\(Int(tightest.usedPercent.rounded()))% of \(tightest.label)"
        }
        if account.error != nil { return "limits unavailable" }
        return account.plan ?? ""
    }

    /// Windows cuts tray tooltips at 127 characters.
    static func tooltip(_ status: TrayStatus?) -> String {
        guard let status else { return "Keyhop" }
        var lines = ["Keyhop"]
        for tool in status.tools {
            guard let account = tool.accounts.first(where: { $0.active }),
                  let tightest = account.limits.max(by: { $0.usedPercent < $1.usedPercent }) else { continue }
            lines.append("\(tool.name): \(Int(tightest.usedPercent.rounded()))% of \(tightest.label)")
        }
        return String(lines.joined(separator: "\n").prefix(127))
    }

    /// The icon follows the account in use that's closest to a limit.
    static func glyphValues(_ status: TrayStatus?) -> [Double?] {
        let inUse = status?.tools.compactMap { tool in tool.accounts.first(where: { $0.active }) } ?? []
        guard let pressed = inUse.filter({ !$0.limits.isEmpty }).max(by: {
            ($0.limits.map(\.usedPercent).max() ?? 0) < ($1.limits.map(\.usedPercent).max() ?? 0)
        }) else { return [] }
        return pressed.limits.prefix(2).map { $0.usedPercent / 100 }
    }

    /// Parses a dollar amount typed into the budget prompt. Empty means no budget.
    static func budgetAmount(_ text: String) -> Double?? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        if cleaned.isEmpty { return .some(nil) }
        guard let value = Double(cleaned), value > 0, value.isFinite else { return nil }
        return .some(value)
    }

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
        amount >= 100 ? String(format: "$%.0f", amount) : String(format: "$%.2f", amount)
    }

    static func relative(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86400 { return "\(seconds / 3600) h ago" }
        return "\(seconds / 86400) d ago"
    }
}

/// Keyhop's pixel mark from the dashboard and the Mac menu bar, drawn as pixels: two rows of four
/// squares, each row lit as far as one of the account's two nearest limits is used. Four samples
/// per axis keep the corners smooth at 16 px.
enum TrayGlyph {
    /// Top-down, premultiplied BGRA.
    static func pixels(size: Int, values: [Double?], darkTaskbar: Bool) -> [UInt8] {
        let ink: (Double, Double, Double) = darkTaskbar ? (235, 235, 235) : (23, 23, 23)
        let s = Double(size)
        let gap = max(1, (s / 16).rounded())
        let square = ((s - gap * 3) / 4).rounded(.down)
        let left = ((s - square * 4 - gap * 3) / 2).rounded(.down)
        let top = ((s - square * 3) / 2).rounded(.down)
        let radius = square * 0.25
        let lit = levels(values)

        var buffer = [UInt8](repeating: 0, count: size * size * 4)
        for py in 0..<size {
            for px in 0..<size {
                var alpha = 0.0
                for sy in 0..<4 {
                    for sx in 0..<4 {
                        let x = Double(px) + (Double(sx) + 0.5) / 4
                        let y = Double(py) + (Double(sy) + 0.5) / 4
                        var sample = 0.0
                        for row in 0..<2 {
                            for column in 0..<4 {
                                let squareLeft = left + Double(column) * (square + gap)
                                let squareTop = top + Double(row) * square * 2
                                guard inSquare(x, y, left: squareLeft, top: squareTop, side: square, radius: radius) else { continue }
                                sample = 0.3 + 0.7 * min(max(lit[row] - Double(column), 0), 1)
                            }
                        }
                        alpha += sample / 16
                    }
                }
                let offset = (py * size + px) * 4
                buffer[offset] = UInt8((ink.2 * alpha).rounded())
                buffer[offset + 1] = UInt8((ink.1 * alpha).rounded())
                buffer[offset + 2] = UInt8((ink.0 * alpha).rounded())
                buffer[offset + 3] = UInt8((255 * alpha).rounded())
            }
        }
        return buffer
    }

    /// Lit squares per row, 0...4. With no limits read it's the logo: three on top, one below.
    static func levels(_ values: [Double?]) -> [Double] {
        guard !values.isEmpty else { return [3, 1] }
        return (0..<2).map { row in
            guard row < values.count, let value = values[row] else { return 0 }
            return min(max(value, 0), 1) * 4
        }
    }

    private static func inSquare(_ x: Double, _ y: Double, left: Double, top: Double, side: Double, radius: Double) -> Bool {
        guard x >= left, x <= left + side, y >= top, y <= top + side else { return false }
        let cx = min(max(x, left + radius), left + side - radius)
        let cy = min(max(y, top + radius), top + side - radius)
        let dx = x - cx, dy = y - cy
        return dx * dx + dy * dy <= radius * radius
    }
}
