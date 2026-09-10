import Foundation

/// Saved logins, one secret per account: the Keychain on macOS, the Secret Service on Linux.
/// Values are base64 JSON, so every backend can hold them as plain text.
actor Vault {
    static let service = "dev.switchr.vault"
    private let store: any SecretStore
    private var cache: [UUID: Secret] = [:]

    init(store: any SecretStore = SecretStores.standard(service: Vault.service)) {
        self.store = store
    }

    nonisolated var storeName: String { store.name }

    func read(_ id: UUID) -> Secret? {
        if let cached = cache[id] { return cached }
        guard let raw = store.read(id.uuidString),
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
            try store.write(Data(json.base64EncodedString().utf8), account: id.uuidString)
            cache[id] = secret
            return true
        } catch {
            return false
        }
    }

    func delete(_ id: UUID) {
        store.delete(id.uuidString)
        cache[id] = nil
    }
}
