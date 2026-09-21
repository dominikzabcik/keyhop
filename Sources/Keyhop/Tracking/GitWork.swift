import Foundation

/// What a day produced, read from the git repositories on this computer.
///
/// Keyhop already counts what a day cost. This counts what came out of it: the commits you wrote,
/// per day and per repository. It runs `git log` over clones you already have, so it works on
/// private repositories and asks GitHub for nothing.
///
/// Three rules keep the number honest. Merges are left out, because moving history is not work.
/// Only commits you authored are counted, matched on the email git recorded rather than on a name.
/// And a day is always restated in full rather than added to, so rebasing, amending or squashing
/// corrects a day instead of inflating it.
///
/// Nothing about this machine travels: no paths, no branches, no file names and no diffs. A
/// repository is named by its remote, and the subject lines go only when they are turned on.
enum GitWork {
    /// Folders never worth walking into while looking for repositories.
    private static let skipped: Set<String> = [
        "node_modules", ".build", "build", "vendor", "Pods", ".venv", "venv", "target", "dist",
        ".next", ".cache", "DerivedData", "Library", ".Trash", ".git",
    ]

    /// Bounds on a scan, so a stray root folder can't turn a sync into a crawl of the disk.
    private static let maxDepth = 4
    private static let maxRepositories = 200

    // MARK: Finding repositories

    /// Every git repository under these folders, found by walking a bounded number of levels down.
    /// A repository's own contents are never walked: once a `.git` is found, that branch stops.
    static func repositories(under roots: [URL]) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        for root in roots {
            walk(root, depth: 0, found: &found, seen: &seen)
            if found.count >= maxRepositories { break }
        }
        return found
    }

    private static func walk(_ folder: URL, depth: Int, found: inout [URL], seen: inout Set<String>) {
        guard depth <= maxDepth, found.count < maxRepositories else { return }
        let path = folder.standardizedFileURL.path
        guard !seen.contains(path) else { return }
        seen.insert(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) {
            found.append(folder)
            return
        }
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                                    options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if skipped.contains(child.lastPathComponent) { continue }
            walk(child, depth: depth + 1, found: &found, seen: &seen)
        }
    }

    // MARK: Naming a repository

    /// "owner/name", taken from the remote. A repository with no usable remote is named after its
    /// own folder, which is a name rather than a path: nothing above it travels.
    static func name(of repo: URL) -> String {
        let remote = git(repo, ["remote", "get-url", "origin"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let remote, let parsed = ownerAndName(from: remote) { return parsed }
        return "local/\(clean(repo.lastPathComponent))"
    }

    /// Pulls "owner/name" out of the shapes a git remote comes in.
    static func ownerAndName(from remote: String) -> String? {
        var value = remote
        if value.hasSuffix(".git") { value.removeLast(4) }
        // scp-style, like git@github.com:owner/name
        if let colon = value.range(of: ":"), !value.contains("://") {
            value = String(value[colon.upperBound...])
        } else if let url = URL(string: value), let host = url.host {
            _ = host
            value = url.path
        }
        let parts = value.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let owner = clean(parts[parts.count - 2])
        let name = clean(parts[parts.count - 1])
        guard !owner.isEmpty, !name.isEmpty else { return nil }
        return "\(owner)/\(name)"
    }

    /// Keeps a name to what the website accepts, so a strange folder name can't fail an upload.
    private static func clean(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_" || $0 == "-" }
        return String(String.UnicodeScalarView(allowed)).prefix(60).description
    }

    // MARK: Whose commits count

    /// The emails that mean "me". Git's own configuration is the truth here, with GitHub's private
    /// addresses for the linked login added, since those are what it rewrites commits to.
    static func identities(repo: URL?, extra: [String], login: String?) -> Set<String> {
        var emails = Set(extra.map { $0.lowercased() })
        if let repo, let configured = git(repo, ["config", "user.email"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            emails.insert(configured.lowercased())
        }
        if let login, !login.isEmpty {
            emails.insert("\(login.lowercased())@users.noreply.github.com")
        }
        return emails
    }

    // MARK: Reading a repository

    struct Commit: Equatable {
        var sha: String
        var subject: String
        var insertions: Int
        var deletions: Int
        var at: Int
        var day: String
        /// Seconds east of UTC, as recorded on the commit itself.
        var offset: Int
    }

    /// Splits git's strict ISO author date, like `2026-09-21T17:13:40+02:00`, into the calendar day
    /// the author was living in and how far that was from UTC.
    static func localDay(fromISO value: String) -> (day: String, offset: Int)? {
        guard value.count >= 20 else { return nil }
        let day = String(value.prefix(10))
        guard day.count == 10 else { return nil }
        let tail = String(value.suffix(6))
        if value.hasSuffix("Z") { return (day, 0) }
        guard let sign = tail.first, sign == "+" || sign == "-" else { return nil }
        let parts = tail.dropFirst().split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        let seconds = hours * 3600 + minutes * 60
        return (day, sign == "-" ? -seconds : seconds)
    }

    /// Commits in one repository since a day, newest first. Merges are excluded by git itself, and
    /// authorship is matched here rather than with `--author`, so a name can never stand in for an
    /// address and no pattern needs escaping.
    ///
    /// A commit's day is the one its author was living in, taken from the commit itself, so a day
    /// reads the same wherever it is later looked at.
    static func commits(in repo: URL, since day: String, mine: Set<String>) -> [Commit] {
        // %aI is the author's own recorded local time, so the day and the clock come from the same
        // place: the calendar the person was actually living in when they wrote the commit.
        let format = "%x1e%h%x1f%ae%x1f%at%x1f%aI%x1f%s"
        guard let output = git(repo, [
            "log", "--no-merges", "--all", "--since=\(day)", "--pretty=format:\(format)", "--numstat",
        ]) else { return [] }

        var commits: [Commit] = []
        var seen = Set<String>()
        for record in output.components(separatedBy: "\u{1e}") where !record.isEmpty {
            var lines = record.components(separatedBy: "\n")
            guard !lines.isEmpty else { continue }
            let fields = lines.removeFirst().components(separatedBy: "\u{1f}")
            guard fields.count >= 5 else { continue }
            let email = fields[1].lowercased()
            guard mine.contains(email) else { continue }
            let sha = fields[0]
            // `--all` walks every branch, so the same commit can arrive by more than one path.
            guard !sha.isEmpty, seen.insert(sha).inserted else { continue }

            var insertions = 0
            var deletions = 0
            for line in lines where !line.isEmpty {
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 3 else { continue }
                // A binary file reports "-" for both counts and simply adds nothing.
                insertions += Int(parts[0]) ?? 0
                deletions += Int(parts[1]) ?? 0
            }
            guard let local = localDay(fromISO: fields[3]) else { continue }
            commits.append(Commit(sha: sha, subject: fields[4], insertions: insertions, deletions: deletions,
                                  at: Int(fields[2]) ?? 0, day: local.day, offset: local.offset))
        }
        return commits
    }

    // MARK: Knowing what has already been read

    /// The newest commit across every branch and tag, which is the cheapest honest answer to "has
    /// anything happened here since I last looked".
    ///
    /// One revision walk bounded to a single commit, rather than the full log with its per-file
    /// counts. On a repository nobody has touched, this is the entire cost of a sync.
    static func fingerprint(of repo: URL) -> String? {
        guard let output = git(repo, ["log", "-1", "--all", "--format=%H"]) else { return nil }
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        // A repository with no commits at all answers with nothing, and has nothing to read.
        return value.isEmpty ? nil : value
    }

    // MARK: A whole scan

    /// What one pass over the repositories found, and what it learned for the next one.
    struct Scan {
        var days: [CloudWorkDay]
        var index: WorkIndex
        /// Repositories read this time, as opposed to skipped because nothing had changed.
        var read: Int
        var skipped: Int
    }

    /// Every repository's days, rolled up the way the website stores them.
    ///
    /// The index is what keeps this cheap after the first run. Reading a repository's log with
    /// per-file counts is the expensive part, and most repositories have not changed since the last
    /// sync, so each one is first asked for its newest commit: one bounded revision walk. When that
    /// answer and the window both match what was recorded last time, the log is never opened.
    ///
    /// `progress` is called as each repository is finished, so the window, the menu and a terminal
    /// can all show the same count while a first index works through a disk full of clones.
    static func scan(roots: [URL], since day: String, emails: [String], login: String?, shareSubjects: Bool,
                     index: WorkIndex = WorkIndex(), progress: ProgressHandler? = nil) -> Scan {
        var rolled: [String: CloudWorkDay] = [:]
        var next = index
        var read = 0
        var skipped = 0

        let found = repositories(under: roots)
        next.total = found.count
        next.done = 0
        progress?(WorkProgress(step: .repositories, done: 0, total: found.count))

        for (position, repo) in found.enumerated() {
            defer {
                next.done = position + 1
                progress?(WorkProgress(step: .repositories, done: position + 1, total: found.count,
                                       detail: repo.lastPathComponent))
            }
            let path = repo.standardizedFileURL.path
            let mine = identities(repo: repo, extra: emails, login: login)
            guard !mine.isEmpty else { continue }

            // Nothing new, and the same stretch of days as last time, means nothing to read. The
            // website still holds what was sent for this repository, so skipping changes nothing
            // about what anyone sees.
            let head = fingerprint(of: repo)
            let known = index.repos[path]
            if let head, let known, known.head == head, known.since <= day, !shareSubjects || known.hadSubjects {
                skipped += 1
                next.repos[path] = known
                continue
            }

            read += 1
            let repoName = name(of: repo)
            for commit in commits(in: repo, since: day, mine: mine) where commit.day >= day {
                let key = "\(commit.day)|\(repoName)"
                var entry = rolled[key] ?? CloudWorkDay(day: commit.day, repo: repoName, commits: 0, insertions: 0,
                                                        deletions: 0, subjects: shareSubjects ? [] : nil)
                entry.commits += 1
                entry.insertions += commit.insertions
                entry.deletions += commit.deletions
                if shareSubjects {
                    entry.subjects = (entry.subjects ?? []) + [
                        CloudWorkCommit(sha: commit.sha, subject: commit.subject, insertions: commit.insertions,
                                        deletions: commit.deletions, at: commit.at, offset: commit.offset),
                    ]
                }
                rolled[key] = entry
            }
            if let head {
                next.repos[path] = WorkIndex.Entry(repo: repoName, head: head, since: day, hadSubjects: shareSubjects,
                                                   scannedAt: Date())
            }
        }

        // A repository that has gone away shouldn't keep a row in the index forever.
        let alive = Set(found.map { $0.standardizedFileURL.path })
        next.repos = next.repos.filter { alive.contains($0.key) }
        next.completedAt = Date()

        // The website keeps at most a couple of hundred subjects for a day, and the newest are the
        // ones worth having, so a very long day is trimmed here rather than refused there.
        let days = rolled.values
            .map { entry -> CloudWorkDay in
                guard var subjects = entry.subjects, subjects.count > 200 else { return entry }
                subjects.sort { $0.at > $1.at }
                var trimmed = entry
                trimmed.subjects = Array(subjects.prefix(200))
                return trimmed
            }
            .sorted { ($0.day, $0.repo) < ($1.day, $1.repo) }
        return Scan(days: days, index: next, read: read, skipped: skipped)
    }

    /// Every repository's days, ignoring any index. Used where a full read is what is wanted, like
    /// `keyhop work scan`.
    static func days(roots: [URL], since day: String, emails: [String], login: String?, shareSubjects: Bool,
                     progress: ProgressHandler? = nil) -> [CloudWorkDay] {
        scan(roots: roots, since: day, emails: emails, login: login, shareSubjects: shareSubjects,
             progress: progress).days
    }

    // MARK: Running git

    /// Runs git in a repository. A missing git, or a folder git refuses, simply reads as no commits.
    private static func git(_ repo: URL, _ arguments: [String]) -> String? {
        guard let tool = gitPath else { return nil }
        let result = try? Shell.run(tool, ["-C", repo.path] + arguments)
        guard let result, result.status == 0 else { return nil }
        return String(decoding: result.stdout, as: UTF8.self)
    }

    /// Looked up once: this runs for every repository on every sync.
    private static let gitPath: String? = Shell.which("git")

    static var isAvailable: Bool { gitPath != nil }
}

/// What has already been read, so the next pass doesn't read it again.
///
/// The first index is the slow one: every repository under every folder, each one's log walked with
/// per-file counts. After that, nearly all of them are untouched, and an untouched repository costs
/// one bounded revision walk instead of a full read. Keeping that memory on disk is what turns an
/// hourly sync from a minute of work into a second of it.
///
/// It is only ever a cache. Deleting `work-index.json` costs one slow pass and nothing else, and
/// every day it produces is restated on the website rather than added to, so a stale or wrong entry
/// can make a sync redundant but can never make a day wrong.
struct WorkIndex: Codable, Equatable {
    struct Entry: Codable, Equatable {
        /// The name this repository travels under, kept so the index can be read on its own.
        var repo: String
        /// Its newest commit across all branches when it was last read.
        var head: String
        /// The earliest day that read covered. A wider window has to be read again.
        var since: String
        /// Whether subject lines were collected. Turning sharing on has to read them again.
        var hadSubjects: Bool
        var scannedAt: Date
    }

    /// Keyed by the repository's path on this computer, which never leaves it.
    var repos: [String: Entry] = [:]
    /// Where the last pass got to, for anything drawing progress.
    var done: Int = 0
    var total: Int = 0
    var completedAt: Date?

    /// Nothing has been indexed yet, so any figures built from it are still filling in.
    var isComplete: Bool { completedAt != nil && done >= total }

    static var url: URL { Platform.dataDirectory.appendingPathComponent("work-index.json") }

    static func load() -> WorkIndex {
        guard let data = try? Data(contentsOf: url),
              let index = try? DashboardJSON.decoder.decode(WorkIndex.self, from: data) else { return WorkIndex() }
        return index
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
        try Files.writeAtomically(DashboardJSON.encoder.encode(self), to: Self.url)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// What Keyhop is allowed to read, and how much of it is allowed to leave. Off until it is turned
/// on, and the subjects are a second, separate yes: counting commits and sending the words you
/// wrote are different things, so they are different switches.
struct WorkSettings: Codable, Equatable {
    /// Scan this computer's repositories at all.
    var enabled: Bool
    /// Send the subject lines, not only the counts.
    var shareSubjects: Bool
    /// The folders to look for repositories under.
    var roots: [String]
    /// Extra addresses that mean "me", for repositories configured with a different one.
    var emails: [String]
    var lastSync: Date?

    static let empty = WorkSettings(enabled: false, shareSubjects: false, roots: [], emails: [], lastSync: nil)

    static var url: URL { Platform.dataDirectory.appendingPathComponent("work.json") }

    static func load() -> WorkSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? DashboardJSON.decoder.decode(WorkSettings.self, from: data) else { return .empty }
        return settings
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
        try Files.writeAtomically(DashboardJSON.encoder.encode(self), to: Self.url)
    }

    var rootURLs: [URL] { roots.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } }

    /// The folders people keep code in, offered when someone turns this on without naming any.
    /// Only ones that already exist are suggested, so nothing is invented.
    static func likelyRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Developer", "Projects", "projects", "src", "code", "dev", "git", "repos", "work"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)
    }
}
