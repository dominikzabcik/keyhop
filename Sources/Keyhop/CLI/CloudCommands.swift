import Foundation

extension Commands {
    /// `keyhop cloud login|status|sync|limits|open|logout`
    static func cloud(_ args: inout Arguments) async throws {
        let action = args.nextPositional() ?? "status"
        switch action {
        case "login": try await cloudLogin(&args)
        case "status": try cloudStatus(&args)
        case "sync": try await cloudSync(&args)
        case "limits": try await cloudLimits(&args)
        case "open":
            try args.finish()
            guard let link = CloudLink.load() else { throw KeyhopError("Not linked yet. Run keyhop cloud login.") }
            _ = Desktop.open(link.profileURL)
            print(link.profileURL)
        case "logout":
            try args.finish()
            guard let link = CloudLink.load() else { return print("This computer isn't linked to Keyhop cloud.") }
            try? await CloudClient(server: link.server, token: link.token).unlink()
            CloudLink.remove()
            print("Unlinked @\(link.login). Nothing more is sent from this computer.")
        default:
            throw UsageError("Unknown cloud command '\(action)'. Use login, status, sync, limits, open or logout.")
        }
    }

    private static func cloudLogin(_ args: inout Arguments) async throws {
        let noOpen = args.flag("--no-open")
        let serverOption = try args.option("--server")
        try args.finish()
        guard let server = serverOption ?? Cloud.server else {
            throw KeyhopError("Keyhop cloud isn't available in this version yet.")
        }
        let client = CloudClient(server: server)
        let start = try await client.startLink(label: Cloud.deviceLabel)
        print("Sign in with GitHub and approve the code \(start.userCode):")
        print("  \(start.verifyUrl)")
        fflush(nil)
        if !noOpen { _ = Desktop.open(start.verifyUrl) }

        let deadline = Date().addingTimeInterval(TimeInterval(start.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(max(start.interval, 2)))
            switch try await client.poll(start.deviceCode) {
            case .pending:
                continue
            case .expired:
                throw KeyhopError("The code expired. Run keyhop cloud login again.")
            case .granted(let granted):
                var link = CloudLink(server: server, token: granted.token, login: granted.user.login, name: granted.user.name,
                                     isPublic: granted.user.isPublic, linkedAt: Date())
                try link.save()
                print("Linked to @\(granted.user.login).")
                let workspace = try Workspace.open()
                _ = try? await workspace.tracker.ingestLocalLogs()
                do {
                    let saved = try await CloudSync.run(&link, tracker: workspace.tracker)
                    print("Sent \(saved) daily totals. Your profile: \(link.profileURL)")
                } catch {
                    print("Linked, but the first sync failed: \(error.localizedDescription) It retries after the next refresh.")
                }
                if !granted.user.isPublic {
                    print("Your profile is private. Make it public on the website to join the global leaderboard.")
                }
                workspace.state.save()
                return
            }
        }
        throw KeyhopError("The code expired. Run keyhop cloud login again.")
    }

    private static func cloudStatus(_ args: inout Arguments) throws {
        let json = args.flag("--json")
        try args.finish()
        let link = CloudLink.load()
        if json {
            struct Document: Encodable {
                let linked: Bool
                let server: String?
                let login: String?
                let profile: String?
                let lastSync: Date?
                let lastSyncError: String?
                let sharesLimits: Bool
                let lastLimitSync: Date?
            }
            return try Output.json(Document(linked: link != nil, server: link?.server ?? Cloud.server, login: link?.login,
                                            profile: link?.profileURL, lastSync: link?.lastSync, lastSyncError: link?.lastSyncError,
                                            sharesLimits: link?.sharesLimits ?? false, lastLimitSync: link?.lastLimitSync))
        }
        guard let link else {
            return print(Cloud.server == nil ? "Keyhop cloud isn't available in this version yet." : "Not linked. Run keyhop cloud login.")
        }
        print("Linked to @\(link.login) on \(link.server)")
        print("Profile: \(link.profileURL)")
        if let lastSync = link.lastSync { print("Last sync: \(Output.relative(lastSync))") } else { print("Not synced yet") }
        if let problem = link.lastSyncError { print("Last sync failed: \(problem)") }
        print("Limit sharing: \(link.sharesLimits ? "on" : "off")")
    }

    /// `keyhop cloud limits [on|off]`: whether a linked phone can see where accounts stand.
    private static func cloudLimits(_ args: inout Arguments) async throws {
        let choice = args.nextPositional()
        try args.finish()
        guard var link = CloudLink.load() else { throw KeyhopError("Not linked yet. Run keyhop cloud login.") }
        switch choice {
        case nil, "status":
            print("Limit sharing is \(link.sharesLimits ? "on" : "off").")
            if link.sharesLimits, let last = link.lastLimitSync { print("Last sent: \(Output.relative(last))") }
            if !link.sharesLimits { print("Turn it on with keyhop cloud limits on, to let a linked phone count down to a reset.") }
        case "on":
            let workspace = try Workspace.open()
            let accounts = await workspace.service.accounts
            let usage = workspace.state.usageByID
            link.sharesLimits = true
            link.lastLimitSync = Date()
            try link.save()
            let sent = CloudSync.limits(accounts: accounts, usage: usage)
            do {
                try await CloudClient(server: link.server, token: link.token).upload(sent)
            } catch let error as CloudError where error.kind == .unlinked {
                CloudLink.remove()
                throw error
            }
            print("Limit sharing is on. Sent \(sent.count) \(sent.count == 1 ? "reading" : "readings") to @\(link.login).")
            print("A linked phone can now see how full each account is and when it comes back. Your prompts, emails and account names still never leave this computer.")
        case "off":
            guard link.sharesLimits else { return print("Limit sharing is already off.") }
            try await CloudSync.stopSharingLimits(&link)
            print("Limit sharing is off, and the readings are off the website.")
        case let other?:
            throw UsageError("Unknown limits command '\(other)'. Use on, off or status.")
        }
    }

    private static func cloudSync(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        try args.finish()
        guard var link = CloudLink.load() else { throw KeyhopError("Not linked yet. Run keyhop cloud login.") }
        let workspace = try Workspace.open()
        _ = try await workspace.tracker.ingestLocalLogs()
        do {
            let saved = try await CloudSync.run(&link, tracker: workspace.tracker)
            if json {
                struct Document: Encodable { let saved: Int; let profile: String }
                try Output.json(Document(saved: saved, profile: link.profileURL))
            } else {
                print("Sent \(saved) daily totals to @\(link.login).")
            }
        } catch let error as CloudError where error.kind == .unlinked {
            CloudLink.remove()
            throw error
        }
    }
}
