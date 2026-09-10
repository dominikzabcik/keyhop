import Foundation

/// A mistake in how a command was typed. Printed with a pointer to `switchr help`.
struct UsageError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// A small argument reader. Flags and options can appear anywhere; everything else is positional.
struct Arguments {
    private var items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    /// True when any of the names is present, consuming it.
    mutating func flag(_ names: String...) -> Bool {
        guard let index = items.firstIndex(where: { names.contains($0) }) else { return false }
        items.remove(at: index)
        return true
    }

    /// Reads `--name value` or `--name=value`.
    mutating func option(_ name: String) throws -> String? {
        if let index = items.firstIndex(where: { $0.hasPrefix(name + "=") }) {
            return String(items.remove(at: index).dropFirst(name.count + 1))
        }
        guard let index = items.firstIndex(of: name) else { return nil }
        guard index + 1 < items.count, !items[index + 1].hasPrefix("--") else {
            throw UsageError("\(name) needs a value.")
        }
        let value = items[index + 1]
        items.removeSubrange(index...(index + 1))
        return value
    }

    mutating func nextPositional() -> String? {
        guard let index = items.firstIndex(where: { !$0.hasPrefix("--") }) else { return nil }
        return items.remove(at: index)
    }

    mutating func positional(_ what: String) throws -> String {
        guard let value = nextPositional() else { throw UsageError("Missing \(what).") }
        return value
    }

    /// All remaining positional words, joined with spaces (for names with spaces).
    mutating func remainingWords() -> String {
        var words: [String] = []
        while let word = nextPositional() { words.append(word) }
        return words.joined(separator: " ")
    }

    func finish() throws {
        if let extra = items.first { throw UsageError("Unexpected argument \(extra).") }
    }
}
