import Foundation

/// The `keyhop` command. On Linux and Windows it's the whole program, and the tray apps run it
/// for data; on macOS the app binary answers the same commands.
enum KeyhopCLI {
    static let commands: Set<String> = [
        "status", "refresh", "recommend", "switch", "add", "rename", "remove", "usage", "dashboard", "insights", "budget",
        "cloud", "mcp", "update", "doctor", "reset", "version", "help", "--help", "-h", "--version",
    ]

    static func handles(_ word: String) -> Bool {
        commands.contains(word)
    }

    static func runAndExit(_ arguments: [String]) -> Never {
        final class Outcome: @unchecked Sendable { var code: Int32 = 0 }
        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            outcome.code = await run(arguments)
            done.signal()
        }
        done.wait()
        exit(outcome.code)
    }

    static func run(_ arguments: [String]) async -> Int32 {
        var args = Arguments(arguments)
        let command = args.nextPositional() ?? "status"
        #if os(Windows)
        WindowsInstaller.cleanUp()
        #endif
        do {
            switch command {
            case "dashboard": try await Commands.dashboard(&args)
            case "insights": try await Commands.insights(&args)
            case "status": try await Commands.status(&args)
            case "refresh": try await Commands.refresh(&args)
            case "recommend": try await Commands.recommend(&args)
            case "switch": try await Commands.switchAccount(&args)
            case "add": try await Commands.add(&args)
            case "rename": try await Commands.rename(&args)
            case "remove": try await Commands.remove(&args)
            case "usage": try await Commands.usage(&args)
            case "budget": try await Commands.budget(&args)
            case "cloud": try await Commands.cloud(&args)
            case "mcp": try await MCPServer.run(&args)
            case "update": try await Commands.update(&args)
            case "doctor": try await Commands.doctor(&args)
            case "reset": try await Commands.reset(&args)
            case "version", "--version": print("keyhop \(AppVersion.current)")
            case "help", "--help", "-h": print(helpText)
            default: throw UsageError("Unknown command '\(command)'.")
            }
            return 0
        } catch let error as UsageError {
            Output.error("\(error.message)\nRun `keyhop help` to see the commands.")
            return 2
        } catch {
            Output.error(error.localizedDescription)
            return 1
        }
    }

    static let helpText = """
    Keyhop \(AppVersion.current): switch Claude Code, Cursor, Codex and Gemini CLI accounts, and track what each one uses.

    Usage: keyhop <command> [options]

    Accounts
      status [--refresh] [--json]          Accounts, limits and today's usage
      refresh [--json]                     Read logins, limits and usage logs now
      recommend [--tool <tool>] [--json]   Smart Hop's best current runway
      switch <account> [--tool <tool>]     Move a tool to a saved account
      add <tool> [--no-wait]               Sign a tool out here so you can save another account
      rename <account> <name>              Give an account a name
      remove <account>                     Forget a saved account that isn't in use

    Usage and budgets
      usage [--range today|week|month|30d] [--tool <tool>] [--json]
      dashboard [--section <name>] [--sample]  Open Keyhop's window: accounts, usage, budgets, settings
      insights [--output <file>] [--sample]    Open Usage in the dashboard, or save the dashboard as one file
      budget list [--json]
      budget set <account|all> <dollars> [--period day|week|month]
      budget clear <account|all>

    Leaderboards
      cloud login [--no-open]              Link this computer with GitHub and send daily totals
      cloud status [--json]                Who this computer is linked to, and the last sync
      cloud sync [--json]                  Send daily totals now (also runs hourly after a refresh)
      cloud limits [on|off]                Let a linked phone see how full each account is
      cloud open                           Open your profile on the website
      cloud logout                         Unlink this computer

    Agents
      mcp                                  Serve read-only status, usage and Smart Hop tools over stdio

    App
      update [--check] [--json]            Check for and install a new release
      doctor [--json]                      Show paths, storage and what Keyhop can see
      reset [--yes]                        Remove saved logins, usage history and settings
      version

    <account> is an email, a name you gave it, or the start of its ID.
    <tool> is claude, cursor, codex or gemini.
    """
}

enum Output {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func json<Value: Encodable>(_ value: Value) throws {
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    static func error(_ message: String) {
        FileHandle.standardError.write(Data("keyhop: \(message)\n".utf8))
    }

    static var isTerminal: Bool {
        Terminal.outputIsInteractive
    }

    /// Provider hints use Markdown backticks for commands; plain terminals don't need them.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "")
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86400 { return "\(seconds / 3600) h ago" }
        return "\(seconds / 86400) d ago"
    }
}
