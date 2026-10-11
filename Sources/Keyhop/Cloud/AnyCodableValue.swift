import Foundation

/// A payload carried verbatim, so what would be sent can be shown exactly as it would be sent.
struct AnyCodableValue: Encodable {
    private let write: (Encoder) throws -> Void

    init(_ value: some Encodable) {
        write = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try write(encoder)
    }
}
