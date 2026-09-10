import Foundation

// What the tray shows, built from `switchr status --json`. Nothing here touches Win32, so it
// compiles and runs on every system; `SwitchrTray --print-menu status.json` prints the menu.

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

    let version: String
    let refreshedAt: Date?
    let today: Spend
    let tools: [Tool]
    let alerts: [Alert]
    let notices: [String]

    static func decode(_ data: Data) throws -> TrayStatus {
        try TrayJSON.decoder.decode(TrayStatus.self, from: data)
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
    case insights
    case toggleStartAtSignIn
    case installUpdate
    case checkForUpdates
    case quit
}

struct TrayMenuItem: Equatable {
    var title: String
    var command: TrayCommand?
    var checked = false
    var enabled = true
    var isSeparator = false

    static let separator = TrayMenuItem(title: "", isSeparator: true)
}

enum TrayMenu {
    static func build(status: TrayStatus?, busy: String?, update: TrayUpdate?, startsAtSignIn: Bool, now: Date = Date()) -> [TrayMenuItem] {
        var items: [TrayMenuItem] = []
        if let busy {
            items.append(TrayMenuItem(title: busy, enabled: false))
            items.append(.separator)
        }

        if let status {
            for tool in status.tools {
                items.append(TrayMenuItem(title: tool.name, enabled: false))
                for account in tool.accounts {
                    items.append(TrayMenuItem(
                        title: "\(account.name)\t\(detail(account))",
                        command: account.active ? nil : .switchTo(account.id),
                        checked: account.active,
                        enabled: busy == nil || account.active
                    ))
                }
                items.append(TrayMenuItem(title: tool.accounts.isEmpty ? "Save the signed-in account…" : "Add account…",
                                          command: .add(tool.id), enabled: busy == nil))
                items.append(.separator)
            }
            if status.today.requests > 0 {
                items.append(TrayMenuItem(title: "Today: \(tokens(status.today.tokens)) tokens, \(usd(status.today.cost)) at API prices", enabled: false))
            }
            items.append(TrayMenuItem(title: status.refreshedAt.map { "Limits read \(relative($0, now: now))" } ?? "Limits not read yet", enabled: false))
        } else {
            items.append(TrayMenuItem(title: "Reading your accounts…", enabled: false))
        }

        items.append(TrayMenuItem(title: "Refresh now", command: .refresh, enabled: busy == nil))
        items.append(TrayMenuItem(title: "Insights", command: .insights))
        items.append(.separator)
        items.append(TrayMenuItem(title: "Open at sign-in", command: .toggleStartAtSignIn, checked: startsAtSignIn))
        if let update, update.available {
            items.append(TrayMenuItem(title: "Update to \(update.latest)", command: .installUpdate, enabled: busy == nil))
        } else {
            items.append(TrayMenuItem(title: "Check for updates (\(status?.version ?? update?.current ?? "…"))", command: .checkForUpdates, enabled: busy == nil))
        }
        items.append(TrayMenuItem(title: "Quit Switchr", command: .quit))
        return items
    }

    /// The tightest limit, or why there isn't one.
    static func detail(_ account: TrayStatus.Account) -> String {
        if let tightest = account.limits.max(by: { $0.usedPercent < $1.usedPercent }) {
            return "\(Int(tightest.usedPercent.rounded()))% of \(tightest.label)"
        }
        if account.error != nil { return "limits unavailable" }
        return account.plan ?? ""
    }

    /// Two lines at most; Windows cuts tray tooltips at 127 characters.
    static func tooltip(_ status: TrayStatus?) -> String {
        guard let status else { return "Switchr" }
        var lines = ["Switchr"]
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

/// The menu bar glyph from the Mac app, drawn as pixels: the account's two nearest limits as two
/// short tracks. Four samples per axis keep the rounded ends smooth at 16 px.
enum TrayGlyph {
    /// Top-down, premultiplied BGRA.
    static func pixels(size: Int, values: [Double?], darkTaskbar: Bool) -> [UInt8] {
        let ink: (Double, Double, Double) = darkTaskbar ? (237, 231, 217) : (10, 21, 16)
        let s = Double(size)
        let trackWidth = (s * 0.875).rounded()
        let trackHeight = max(3, (s * 0.22).rounded())
        let gap = max(2, (s * 0.19).rounded())
        let left = ((s - trackWidth) / 2).rounded()
        let firstTop = ((s - trackHeight * 2 - gap) / 2).rounded()
        let idle = values.isEmpty

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
                            let top = firstTop + Double(row) * (trackHeight + gap)
                            guard inCapsule(x, y, left: left, top: top, width: trackWidth, height: trackHeight) else { continue }
                            let raw = row < values.count ? values[row] : nil
                            let filled = raw.map { max(trackHeight, trackWidth * min(max($0, 0), 1)) } ?? 0
                            if let raw, raw > 0, inCapsule(x, y, left: left, top: top, width: filled, height: trackHeight) {
                                sample = 1
                            } else {
                                sample = idle ? 0.6 : 0.34
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

    private static func inCapsule(_ x: Double, _ y: Double, left: Double, top: Double, width: Double, height: Double) -> Bool {
        let radius = height / 2
        let cy = top + radius
        let cx = min(max(x, left + radius), left + width - radius)
        let dx = x - cx, dy = y - cy
        return dx * dx + dy * dy <= radius * radius
    }
}
