import Foundation
#if os(macOS)
import SQLite3
#else
import CSQLite
#endif

enum SQL {
    case int(Int64)
    case real(Double)
    case text(String)
    case null

    static func text(_ value: String?) -> SQL { value.map(SQL.text) ?? .null }
}

/// A small synchronous SQLite wrapper. The tracker engine is an actor, so access is serialized.
final class Database {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw SwitchrError("Couldn't open the usage database: \(message)")
        }
        sqlite3_busy_timeout(handle, 5000)
        try script("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Runs one or more statements without parameters.
    func script(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    func execute(_ sql: String, _ values: [SQL] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw failure() }
    }

    func query(_ sql: String, _ values: [SQL] = [], _ row: (DBRow) throws -> Void) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW, let statement else { throw failure() }
            try row(DBRow(statement: statement))
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try script("BEGIN IMMEDIATE")
        do {
            try body()
            try script("COMMIT")
        } catch {
            try? script("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ values: [SQL]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .int(let number): sqlite3_bind_int64(statement, index, number)
            case .real(let number): sqlite3_bind_double(statement, index, number)
            case .text(let string): sqlite3_bind_text(statement, index, string, -1, Self.transient)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func failure() -> SwitchrError {
        SwitchrError("Usage database: \(String(cString: sqlite3_errmsg(handle)))")
    }
}

struct DBRow {
    let statement: OpaquePointer

    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func text(_ column: Int32) -> String? { sqlite3_column_text(statement, column).map { String(cString: $0) } }
}
