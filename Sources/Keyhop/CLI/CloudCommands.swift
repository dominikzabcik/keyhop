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
        let terminal = TerminalProgress()
        _ = try await workspace.tracker.ingestLocalLogs(progress: terminal.handler)
        terminal.finish()
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

extension Commands {
    /// `keyhop work status|on|off|add|remove|subjects|scan|index|sync`
    ///
    /// What Keyhop reads from this computer's repositories, and how much of it leaves. Counting
    /// commits and sending the words you wrote are separate yeses, so they are separate commands.
    static func work(_ args: inout Arguments) async throws {
        let action = args.nextPositional() ?? "status"
        switch action {
        case "status": try workStatus(&args)
        case "on": try workOn(&args)
        case "off":
            try args.finish()
            var settings = WorkSettings.load()
            guard settings.enabled else { return print("Commit counting is already off.") }
            settings.enabled = false
            try settings.save()
            print("Commit counting is off. Nothing more is read from your repositories.")
            print("What was already sent stays on the website. Use keyhop work subjects off to take the subject lines down.")
        case "add": try workAdd(&args)
        case "remove": try workRemove(&args)
        case "subjects": try await workSubjects(&args)
        case "scan": try workScan(&args)
        case "sync": try await workSync(&args)
        case "index": try await workIndex(&args)
        default:
            throw UsageError("Unknown work command '\(action)'. Use status, on, off, add, remove, subjects, scan, index or sync.")
        }
    }

    private static func workStatus(_ args: inout Arguments) throws {
        let json = args.flag("--json")
        try args.finish()
        let settings = WorkSettings.load()
        if json {
            struct Index: Encodable {
                let done: Int
                let total: Int
                let complete: Bool
                let completedAt: Date?
            }
            struct Document: Encodable {
                let enabled: Bool
                let sharesSubjects: Bool
                let roots: [String]
                let emails: [String]
                let lastSync: Date?
                let gitAvailable: Bool
                let index: Index
            }
            let index = WorkIndex.load()
            return try Output.json(Document(enabled: settings.enabled, sharesSubjects: settings.shareSubjects,
                                            roots: settings.roots, emails: settings.emails, lastSync: settings.lastSync,
                                            gitAvailable: GitWork.isAvailable,
                                            index: Index(done: index.done, total: index.total, complete: index.isComplete,
                                                         completedAt: index.completedAt)))
        }
        guard GitWork.isAvailable else { return print("git isn't installed, so Keyhop can't count commits on this computer.") }
        print("Commit counting: \(settings.enabled ? "on" : "off")")
        print("Subject lines: \(settings.shareSubjects ? "shared" : "kept on this computer")")
        if settings.roots.isEmpty {
            print("No folders to scan. Add one with keyhop work add ~/Projects.")
        } else {
            print("Folders: \(settings.roots.joined(separator: ", "))")
        }
        if !settings.emails.isEmpty { print("Also counting: \(settings.emails.joined(separator: ", "))") }
        let index = WorkIndex.load()
        if index.total > 0 {
            print(index.isComplete
                ? "Indexed: \(index.total) \(index.total == 1 ? "repository" : "repositories")"
                : "Indexing: \(index.done) of \(index.total) repositories, so figures are still filling in")
        }
        if let last = settings.lastSync { print("Last sent: \(Output.relative(last))") }
        if !settings.enabled { print("Turn it on with keyhop work on, to put what you shipped next to what it cost.") }
    }

    private static func workOn(_ args: inout Arguments) throws {
        try args.finish()
        guard GitWork.isAvailable else { throw KeyhopError("git isn't installed, so there is nothing to read.") }
        var settings = WorkSettings.load()
        settings.enabled = true
        // Somewhere to look is the whole job, so folders that obviously hold code are offered
        // rather than left for a second command.
        if settings.roots.isEmpty {
            settings.roots = WorkSettings.likelyRoots()
        }
        try settings.save()
        print("Commit counting is on.")
        if settings.roots.isEmpty {
            print("No folder to scan yet. Add one with keyhop work add ~/Projects.")
        } else {
            print("Scanning: \(settings.roots.joined(separator: ", "))")
            print("Only commits you authored count, and merges are left out. Subject lines stay here until you run keyhop work subjects on.")
        }
    }

    private static func workAdd(_ args: inout Arguments) throws {
        guard let folder = args.nextPositional() else { throw UsageError("Which folder? Try keyhop work add ~/Projects.") }
        try args.finish()
        let path = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw KeyhopError("There's no folder at \(path).")
        }
        var settings = WorkSettings.load()
        guard !settings.roots.contains(path) else { return print("\(path) is already scanned.") }
        settings.roots.append(path)
        try settings.save()
        let found = GitWork.repositories(under: [URL(fileURLWithPath: path)]).count
        print("Scanning \(path): \(found) \(found == 1 ? "repository" : "repositories") found.")
    }

    private static func workRemove(_ args: inout Arguments) throws {
        guard let folder = args.nextPositional() else { throw UsageError("Which folder? Try keyhop work remove ~/Projects.") }
        try args.finish()
        let path = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath).standardizedFileURL.path
        var settings = WorkSettings.load()
        guard settings.roots.contains(path) else { return print("\(path) isn't being scanned.") }
        settings.roots.removeAll { $0 == path }
        try settings.save()
        print("Stopped scanning \(path).")
    }

    /// `keyhop work subjects [on|off]`: whether the words you wrote leave this computer.
    private static func workSubjects(_ args: inout Arguments) async throws {
        let choice = args.nextPositional()
        try args.finish()
        var settings = WorkSettings.load()
        switch choice {
        case nil, "status":
            print("Subject lines are \(settings.shareSubjects ? "shared" : "kept on this computer").")
            if !settings.shareSubjects {
                print("Share them with keyhop work subjects on, so a day reads as what you did rather than only how much.")
            }
        case "on":
            guard CloudLink.load() != nil else { throw KeyhopError("Not linked yet. Run keyhop cloud login.") }
            settings.shareSubjects = true
            try settings.save()
            print("Subject lines are shared. Only the first line of each commit travels: never the body, the diff or the file names.")
            print("They go at the next sync, or now with keyhop work sync.")
        case "off":
            guard settings.shareSubjects else { return print("Subject lines are already kept on this computer.") }
            guard let link = CloudLink.load() else {
                settings.shareSubjects = false
                try settings.save()
                return print("Subject lines are kept on this computer.")
            }
            try await CloudSync.stopSharingSubjects(&settings, link: link)
            print("Subject lines are kept on this computer, and the ones already sent are off the website.")
        case let other?:
            throw UsageError("Unknown subjects command '\(other)'. Use on, off or status.")
        }
    }

    /// `keyhop work scan`: what would be sent, without sending it.
    private static func workScan(_ args: inout Arguments) throws {
        let json = args.flag("--json")
        let days = try args.option("--days").flatMap(Int.init) ?? 1
        try args.finish()
        guard GitWork.isAvailable else { throw KeyhopError("git isn't installed, so there is nothing to read.") }
        let settings = WorkSettings.load()
        guard !settings.roots.isEmpty else { throw KeyhopError("No folders to scan. Add one with keyhop work add ~/Projects.") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let since = formatter.string(from: Date().addingTimeInterval(-Double(max(days, 1)) * 86400))
        // A preview always reads everything: its whole job is to show what is there right now.
        let terminal = json ? nil : TerminalProgress()
        let found = GitWork.days(roots: settings.rootURLs, since: since,
                                 emails: settings.emails, login: CloudLink.load()?.login,
                                 shareSubjects: settings.shareSubjects, progress: terminal?.handler)
        terminal?.finish()
        if json { return try Output.json(found) }
        guard !found.isEmpty else {
            return print("No commits of yours since \(since). Keyhop matches the email git recorded: keyhop work status shows which ones count.")
        }
        for entry in found.sorted(by: { ($0.day, $0.repo) > ($1.day, $1.repo) }) {
            print("\(entry.day)  \(entry.repo)  \(entry.commits) \(entry.commits == 1 ? "commit" : "commits")  +\(entry.insertions) -\(entry.deletions)")
            for commit in entry.subjects ?? [] { print("    \(commit.sha)  \(commit.subject)") }
        }
    }

    private static func workSync(_ args: inout Arguments) async throws {
        let json = args.flag("--json")
        try args.finish()
        guard let link = CloudLink.load() else { throw KeyhopError("Not linked yet. Run keyhop cloud login.") }
        var settings = WorkSettings.load()
        guard settings.enabled else { throw KeyhopError("Commit counting is off. Turn it on with keyhop work on.") }
        let terminal = json ? nil : TerminalProgress()
        do {
            let saved = try await CloudSync.runWork(&settings, link: link, progress: terminal?.handler)
            terminal?.finish()
            let index = WorkIndex.load()
            if json {
                struct Document: Encodable { let saved: Int; let profile: String; let indexed: Int; let repositories: Int }
                try Output.json(Document(saved: saved, profile: link.profileURL, indexed: index.done,
                                         repositories: index.total))
            } else {
                print("Sent \(saved) \(saved == 1 ? "day" : "days") of commits to @\(link.login).")
            }
        } catch let error as CloudError where error.kind == .unlinked {
            terminal?.finish()
            CloudLink.remove()
            throw error
        } catch {
            terminal?.finish()
            throw error
        }
    }

    /// `keyhop work index [--again]`: read every repository now, and say how far it got.
    ///
    /// The first pass is the slow one. After it, a repository nobody has touched costs one bounded
    /// revision walk instead of a full log, which is what keeps the hourly sync out of the way.
    private static func workIndex(_ args: inout Arguments) async throws {
        let again = args.flag("--again")
        let json = args.flag("--json")
        try args.finish()
        guard GitWork.isAvailable else { throw KeyhopError("git isn't installed, so there is nothing to read.") }
        let settings = WorkSettings.load()
        guard !settings.roots.isEmpty else { throw KeyhopError("No folders to scan. Add one with keyhop work add ~/Projects.") }
        if again { WorkIndex.clear() }

        let started = Date()
        let terminal = json ? nil : TerminalProgress()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let since = formatter.string(from: started.addingTimeInterval(-30 * 86400))
        let scan = GitWork.scan(roots: settings.rootURLs, since: since, emails: settings.emails,
                                login: CloudLink.load()?.login, shareSubjects: settings.shareSubjects,
                                index: again ? WorkIndex() : WorkIndex.load(), progress: terminal?.handler)
        terminal?.finish()
        try scan.index.save()
        let seconds = Date().timeIntervalSince(started)

        if json {
            struct Document: Encodable {
                let repositories: Int
                let read: Int
                let skipped: Int
                let days: Int
                let seconds: Double
                let complete: Bool
            }
            return try Output.json(Document(repositories: scan.index.total, read: scan.read, skipped: scan.skipped,
                                            days: scan.days.count, seconds: (seconds * 100).rounded() / 100,
                                            complete: scan.index.isComplete))
        }
        print("Indexed \(scan.index.total) \(scan.index.total == 1 ? "repository" : "repositories") in \(String(format: "%.1f", seconds))s.")
        if scan.skipped > 0 {
            print("\(scan.read) read, \(scan.skipped) unchanged since last time.")
        }
        print("Run keyhop work sync to send what this found, or leave it: a refresh sends it within the hour.")
    }
}
