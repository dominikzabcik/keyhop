import Foundation

/// Merges usage across machines through a folder something else already syncs (iCloud Drive,
/// Syncthing, Dropbox). Each machine appends its own events to one JSONL file named after it
/// and reads everyone else's; event keys keep a line from ever counting twice, and `origin`
/// keeps imported rows from being exported again. There is no server and nothing to sign into.
enum MergeFolder {
    struct Settings: Codable, Equatable {
        /// The shared folder, or nil when merging is off.
        var folder: String?
        var lastSync: Date?

        static let empty = Settings(folder: nil, lastSync: nil)
        static var url: URL { Platform.dataDirectory.appendingPathComponent("merge.json") }

        static func load() -> Settings {
            guard let data = try? Data(contentsOf: url),
                  let settings = try? DashboardJSON.decoder.decode(Settings.self, from: data) else { return .empty }
            return settings
        }

        func save() throws {
            try FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
            try Files.writeAtomically(DashboardJSON.encoder.encode(self), to: Self.url)
        }

        var folderURL: URL? {
            folder.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        }
    }

    struct Outcome {
        var exported = 0
        var imported = 0
        var machines = 0
    }

    private static let exportMarkPath = "merge-export"

    /// This machine's file name: the host name plus a saved random suffix, so two machines
    /// with the same name never write over each other.
    static func machineFile() -> String {
        var host = ProcessInfo.processInfo.hostName.lowercased()
        if host.hasSuffix(".local") { host = String(host.dropLast(6)) }
        host = String(host.map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(30))
        let idURL = Platform.dataDirectory.appendingPathComponent("machine-id")
        let id: String
        if let saved = try? String(contentsOf: idURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
            id = saved
        } else {
            id = String(UUID().uuidString.prefix(8)).lowercased()
            try? FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
            try? Files.writeAtomically(Data(id.utf8), to: idURL)
        }
        return "usage-\(host)-\(id).jsonl"
    }

    /// Runs at most once per 15 minutes, from the same places the logs are read.
    @discardableResult
    static func syncIfDue(tracker: TrackerEngine, accounts: [Account], now: Date = Date()) async -> Outcome? {
        var settings = Settings.load()
        guard settings.folderURL != nil else { return nil }
        if let last = settings.lastSync, now.timeIntervalSince(last) < 15 * 60 { return nil }
        let outcome = try? await sync(tracker: tracker, accounts: accounts)
        settings.lastSync = now
        try? settings.save()
        return outcome
    }

    static func sync(tracker: TrackerEngine, accounts: [Account]) async throws -> Outcome {
        guard let folder = Settings.load().folderURL else {
            throw UsageError("No merge folder is set. Run `keyhop merge <folder>` first.")
        }
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw UsageError("The merge folder \(folder.path) doesn't exist.")
        }
        var outcome = Outcome()
        outcome.exported = try await exportOwn(to: folder, tracker: tracker, accounts: accounts)
        let foreign = try await importOthers(from: folder, tracker: tracker, accounts: accounts)
        outcome.imported = foreign.imported
        outcome.machines = foreign.machines
        return outcome
    }

    // MARK: Export

    private static func exportOwn(to folder: URL, tracker: TrackerEngine, accounts: [Account]) async throws -> Int {
        let identities = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id.uuidString, $0.identity) })
        let file = folder.appendingPathComponent(machineFile())

        var lastRow: Int64 = 0
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        if let mark = try await tracker.sourceMark(exportMarkPath), let size, size == mark.size {
            lastRow = mark.offset
        } else {
            // The file is missing, or someone else touched it: write it whole again.
            try Data().write(to: file)
        }

        var exported = 0
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        while true {
            let batch = try await tracker.exportMergeEvents(after: lastRow, identities: identities)
            if !batch.lines.isEmpty {
                try handle.write(contentsOf: Data((batch.lines.joined(separator: "\n") + "\n").utf8))
            }
            exported += batch.lines.count
            lastRow = batch.lastRow
            if batch.lines.count < 20000 { break }
        }
        let newSize = Int64((try? handle.offset()) ?? 0)
        try await tracker.setSourceMark(exportMarkPath, size: newSize, offset: lastRow)
        return exported
    }

    // MARK: Import

    private static func importOthers(from folder: URL, tracker: TrackerEngine, accounts: [Account]) async throws -> (imported: Int, machines: Int) {
        let own = machineFile()
        let byIdentity = Dictionary(uniqueKeysWithValues: accounts.map { ("\($0.provider.rawValue)|\($0.identity)", $0.id.uuidString) })
        var imported = 0
        var machines = 0
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = file.lastPathComponent
            guard name.hasPrefix("usage-"), name.hasSuffix(".jsonl"), name != own else { continue }
            machines += 1
            let origin = String(name.dropFirst(6).dropLast(6))
            imported += try await importFile(file, origin: origin, tracker: tracker, byIdentity: byIdentity)
        }
        return (imported, machines)
    }

    /// Reads only what was appended since the last pass, and only whole lines, so a file a sync
    /// service is still writing is picked up next time.
    private static func importFile(_ file: URL, origin: String, tracker: TrackerEngine, byIdentity: [String: String]) async throws -> Int {
        let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        var offset: Int64 = 0
        if let mark = try await tracker.sourceMark(file.path), mark.offset <= size {
            offset = mark.offset
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: file) else {
            if size < offset { try await tracker.setSourceMark(file.path, size: size, offset: 0) }
            return 0
        }
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        guard let data = try handle.read(upToCount: Int(size - offset)) else { return 0 }
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return 0 }
        let complete = data[data.startIndex...lastNewline]
        let lines = String(decoding: complete, as: UTF8.self).split(separator: "\n")
        let imported = try await tracker.importMergeLines(lines, origin: origin, accountsByIdentity: byIdentity)
        let consumed = offset + Int64(complete.count)
        try await tracker.setSourceMark(file.path, size: size, offset: consumed)
        return imported
    }
}
