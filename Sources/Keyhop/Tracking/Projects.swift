import Foundation

/// Where a piece of work happened, named the way the person knows it.
///
/// Claude Code, Codex, OpenCode and Pi record the directory they ran in. That directory is usually
/// somewhere inside a git repository, and the repository is what someone means by "the project",
/// so usage is filed under the repository's top folder. A directory outside any repository is its
/// own project. Gemini CLI and Cursor record no directory, so their usage has no project rather
/// than a guessed one.
///
/// Project paths stay on this computer: they are kept in the local usage database and shown in
/// Keyhop's window, and the daily totals sent to a linked website never carry them.
enum Projects {
    private static let cache = Cache()

    /// The project a working directory belongs to, as a path, or nil when there is none.
    static func root(for directory: String?) -> String? {
        guard let directory = directory?.trimmingCharacters(in: .whitespacesAndNewlines), !directory.isEmpty else { return nil }
        if let known = cache.get(directory) { return known }
        let found = walk(from: directory)
        cache.set(directory, found)
        return found
    }

    /// Up from the directory to the first folder holding `.git`, a folder or, in a worktree, a file.
    /// Home and everything above it is never a project, even when someone keeps their dotfiles in
    /// git: that would file every stray directory under one enormous project called their name.
    private static func walk(from directory: String) -> String {
        let start = URL(fileURLWithPath: directory).standardizedFileURL
        let home = Files.home.standardizedFileURL.path
        let manager = FileManager.default
        var url = start
        while true {
            let path = url.path
            if path == home || path == "/" || path.count <= home.count && home.hasPrefix(path) { break }
            if manager.fileExists(atPath: url.appendingPathComponent(".git").path) { return path }
            let parent = url.deletingLastPathComponent()
            if parent.path == path { break }
            url = parent
        }
        // Not in a repository, or the directory has since been removed: the directory itself.
        return start.path
    }

    /// Short names for project paths: the folder's own name, with the folder above it where two
    /// projects would otherwise share one ("work/app" and "side/app").
    static func names(for roots: [String]) -> [String: String] {
        func last(_ path: String, _ count: Int) -> String {
            let parts = URL(fileURLWithPath: path).standardizedFileURL.pathComponents.filter { $0 != "/" }
            return parts.suffix(count).joined(separator: "/")
        }
        var names: [String: String] = [:]
        // Work started from the home folder isn't a project, and naming it after the person who
        // owns the folder reads as if it were one.
        let home = Files.home.standardizedFileURL.path
        var roots = Set(roots)
        if roots.remove(home) != nil { names[home] = "Home folder" }
        let byName = Dictionary(grouping: roots, by: { last($0, 1) })
        for (name, paths) in byName {
            for path in paths {
                names[path] = paths.count > 1 ? last(path, 2) : name
            }
        }
        return names
    }

    /// A path as a person would recognise it, with the home folder shortened to `~`.
    static func display(_ path: String) -> String {
        let home = Files.home.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var roots: [String: String] = [:]

        func get(_ directory: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return roots[directory]
        }

        func set(_ directory: String, _ root: String) {
            lock.lock()
            roots[directory] = root
            lock.unlock()
        }
    }
}
