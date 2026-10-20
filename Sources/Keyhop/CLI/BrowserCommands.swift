import Foundation

extension Commands {
    static func browser(_ args: inout Arguments) async throws {
        let action = args.nextPositional() ?? "status"
        let json = args.flag("--json")
        try args.finish()
        switch action {
        case "install":
            try BrowserSetup.install()
            let report = try await browserReport()
            if json { return try Output.json(report) }
            let browsers = report.browsers.filter(\.registered).map(\.name)
            print("Keyhop's extension is in \(report.extensionFolder)")
            print("Registered with \(browsers.isEmpty ? "no browser yet" : browsers.joined(separator: ", ")).")
            print("""

            To load it, once:
              1. Open chrome://extensions
              2. Turn on Developer mode (top right)
              3. Click Load unpacked and choose the folder above

            From then on claude.ai follows each Claude Code hop and chatgpt.com each Codex hop.
            """)
        case "status":
            let report = try await browserReport()
            if json { return try Output.json(report) }
            print("Extension: \(report.installed ? report.extensionFolder : "not set up. Run keyhop browser install.")")
            let browsers = report.browsers.filter(\.registered).map(\.name)
            print("Browsers: \(browsers.isEmpty ? "none registered" : browsers.joined(separator: ", "))")
            print("Last heard: \(report.lastSeen.map { Output.relative($0) } ?? "never")")
            print("Site logins kept: \(report.webLogins.count)")
        case "remove":
            BrowserSetup.remove()
            if json { return try Output.json(ActionResult(ok: true, message: "Removed the browser extension.", account: nil, note: nil)) }
            print("Removed the extension's files and its registration. Remove it from chrome://extensions too.")
        default:
            throw UsageError("keyhop browser takes install, status or remove.")
        }
    }

    static func browserReport() async throws -> BrowserSetup.Report {
        let workspace = try Workspace.open()
        return await BrowserSetup.report(vault: workspace.service.vault, accounts: await workspace.service.accounts)
    }
}
