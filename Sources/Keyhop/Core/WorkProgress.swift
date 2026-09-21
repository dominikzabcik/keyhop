import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#endif

/// How far a long read has got, for whatever shows it: Keyhop's window, the menu, a terminal.
///
/// A refresh is three steps: each tool's login, each account's limits, then the token history
/// in local logs. `done` and `total` count logins and accounts; for history they count bytes still
/// to read, which is what a first read of a large history actually spends its time on.
///
/// Indexing repositories is its own step, and the only one that runs on its own rather than as part
/// of a refresh. It counts repositories, because that is the unit a person recognises and the unit
/// the work is actually divided into.
struct WorkProgress: Codable, Equatable, Sendable {
    enum Step: String, Codable, Sendable {
        case logins, limits, history, repositories
    }

    var step: Step
    var done: Int
    var total: Int
    /// The tool being read, where there is one.
    var detail: String?

    var title: String {
        switch step {
        case .logins: return "Checking logins"
        case .limits: return "Reading limits"
        case .history: return "Reading token history"
        case .repositories: return "Indexing repositories"
        }
    }

    /// Share of this step finished, from 0 to 1, or nil while the total isn't known.
    var fraction: Double? {
        total > 0 ? min(1, max(0, Double(done) / Double(total))) : nil
    }

    /// "3 of 7" for things counted, "42%" for bytes.
    var count: String? {
        guard total > 0 else { return nil }
        switch step {
        case .logins, .limits, .repositories: return "\(min(done, total)) of \(total)"
        case .history: return "\(Int((fraction ?? 0) * 100))%"
        }
    }

    /// The same thing in a few characters, for tight places like the menu bar's footer.
    var brief: String {
        let name: String
        switch step {
        case .history: name = "History"
        case .limits: name = "Limits"
        case .logins: name = "Logins"
        case .repositories: name = "Repos"
        }
        switch step {
        case .logins, .limits, .repositories: return total > 0 ? "\(name) \(min(done, total))/\(total)" : name
        case .history: return count.map { "\(name) \($0)" } ?? name
        }
    }

    private enum CodingKeys: String, CodingKey {
        case step, done, total, detail, title, count, fraction
    }

    init(step: Step, done: Int, total: Int, detail: String? = nil) {
        self.step = step
        self.done = done
        self.total = total
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        step = try values.decode(Step.self, forKey: .step)
        done = try values.decode(Int.self, forKey: .done)
        total = try values.decode(Int.self, forKey: .total)
        detail = try values.decodeIfPresent(String.self, forKey: .detail)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(step, forKey: .step)
        try values.encode(done, forKey: .done)
        try values.encode(total, forKey: .total)
        try values.encodeIfPresent(detail, forKey: .detail)
        try values.encode(title, forKey: .title)
        try values.encodeIfPresent(count, forKey: .count)
        try values.encodeIfPresent(fraction, forKey: .fraction)
    }
}

typealias ProgressHandler = @Sendable (WorkProgress) -> Void

/// The latest progress, written by the work and read by whatever draws it, on its own schedule.
/// Reading on a schedule rather than being called for every update means a burst of updates can
/// never arrive out of order or flood the screen.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: WorkProgress?

    var value: WorkProgress? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func set(_ progress: WorkProgress?) {
        lock.lock()
        current = progress
        lock.unlock()
    }

    var handler: ProgressHandler {
        { [weak self] progress in self?.set(progress) }
    }
}

/// A one-line status on a terminal's error stream, redrawn in place, for commands that can take a
/// while. It stays silent when stderr isn't a terminal, so scripts and `--json` output never see it.
final class TerminalProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var lastDraw = Date.distantPast
    private var drawn = false
    let enabled: Bool

    init(enabled: Bool = TerminalProgress.isTerminal) {
        self.enabled = enabled
    }

    static var isTerminal: Bool {
        #if os(Windows)
        return _isatty(2) != 0
        #else
        return isatty(2) != 0
        #endif
    }

    var handler: ProgressHandler {
        { [weak self] progress in self?.draw(progress) }
    }

    func draw(_ progress: WorkProgress) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let finished = progress.total > 0 && progress.done >= progress.total
        guard finished || now.timeIntervalSince(lastDraw) >= 0.1 else { return }
        lastDraw = now
        FileHandle.standardError.write(Data(("\r\u{1B}[2K" + Self.line(progress)).utf8))
        drawn = true
    }

    /// "Reading limits  [########------------]  3 of 7  Codex"
    static func line(_ progress: WorkProgress, width: Int = 20) -> String {
        var parts = [progress.title]
        if let fraction = progress.fraction {
            let filled = Int((fraction * Double(width)).rounded())
            parts.append("[" + String(repeating: "#", count: filled) + String(repeating: "-", count: width - filled) + "]")
        }
        if let count = progress.count { parts.append(count) }
        if let detail = progress.detail { parts.append(detail) }
        return parts.joined(separator: "  ")
    }

    func finish() {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if drawn { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }
        drawn = false
    }
}
