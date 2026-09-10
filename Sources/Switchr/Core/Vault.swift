import Foundation

/// Saved logins, one Keychain item per account. Values are base64 JSON so the
/// `security -w` readback is always printable.
actor Vault {
    static let service = "dev.switchr.vault"
    private var cache: [UUID: Secret] = [:]

    func read(_ id: UUID) -> Secret? {
        if let cached = cache[id] { return cached }
        guard let raw = Keychain.read(service: Self.service, account: id.uuidString),
              let json = Data(base64Encoded: raw),
              let secret = try? JSONDecoder().decode(Secret.self, from: json) else { return nil }
        cache[id] = secret
        return secret
    }

    @discardableResult
    func write(_ secret: Secret, for id: UUID) -> Bool {
        if cache[id] == secret { return true }
        guard let json = try? JSONEncoder().encode(secret) else { return false }
        do {
            try Keychain.write(service: Self.service, account: id.uuidString, data: Data(json.base64EncodedString().utf8))
            cache[id] = secret
            return true
        } catch {
            return false
        }
    }

    func delete(_ id: UUID) {
        Keychain.delete(service: Self.service, account: id.uuidString)
        cache[id] = nil
    }
}
