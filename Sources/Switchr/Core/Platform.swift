import Foundation
#if os(Windows)
import WinSDK
#endif

enum Platform {
    static var name: String {
        #if os(macOS)
        return "macOS"
        #elseif os(Windows)
        return "Windows"
        #else
        return "Linux"
        #endif
    }

    /// Where Switchr keeps its account list, usage history and command-line state.
    static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["SWITCHR_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #if os(macOS)
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Switchr", isDirectory: true)
        #elseif os(Windows)
        return windowsFolder("LOCALAPPDATA", default: "AppData/Local").appendingPathComponent("Switchr", isDirectory: true)
        #else
        return xdg("XDG_DATA_HOME", default: ".local/share").appendingPathComponent("switchr", isDirectory: true)
        #endif
    }

    /// Per-user settings: the XDG config folder on Linux, roaming AppData on Windows. Cursor keeps
    /// its data under it on both.
    static var configDirectory: URL {
        #if os(Windows)
        return windowsFolder("APPDATA", default: "AppData/Roaming")
        #else
        return xdg("XDG_CONFIG_HOME", default: ".config")
        #endif
    }

    private static func xdg(_ variable: String, default relative: String) -> URL {
        if let value = ProcessInfo.processInfo.environment[variable], value.hasPrefix("/") {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return Files.home.appendingPathComponent(relative, isDirectory: true)
    }

    private static func windowsFolder(_ variable: String, default relative: String) -> URL {
        if let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return Files.home.appendingPathComponent(relative, isDirectory: true)
    }
}

// MARK: Secret storage

protocol SecretStore: Sendable {
    /// What holds the secrets, for `switchr doctor`.
    var name: String { get }
    func read(_ account: String) -> Data?
    func write(_ data: Data, account: String) throws
    func delete(_ account: String)
}

enum SecretStores {
    static func standard(service: String) -> any SecretStore {
        #if os(macOS)
        return KeychainSecretStore(service: service)
        #else
        let files = FileSecretStore(directory: Platform.dataDirectory.appendingPathComponent("vault", isDirectory: true))
        if ProcessInfo.processInfo.environment["SWITCHR_SECRET_STORE"] == "file" { return files }
        #if os(Windows)
        return WindowsSecretStore(files: files)
        #else
        return LinuxSecretStore(service: service, files: files)
        #endif
        #endif
    }
}

#if os(macOS)
struct KeychainSecretStore: SecretStore {
    let service: String
    var name: String { "macOS Keychain" }

    func read(_ account: String) -> Data? { Keychain.read(service: service, account: account) }
    func write(_ data: Data, account: String) throws { try Keychain.write(service: service, account: account, data: data) }
    func delete(_ account: String) { Keychain.delete(service: service, account: account) }
}
#endif

/// One 0600 file per login in a 0700 folder: the same protection Claude Code itself uses for its
/// credentials on Linux. Used when no keyring is reachable, such as over SSH.
struct FileSecretStore: SecretStore {
    let directory: URL
    var name: String { "private files in \(directory.path)" }

    func read(_ account: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(account))
    }

    func write(_ data: Data, account: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if !os(Windows)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #endif
        try Files.writeAtomically(data, to: directory.appendingPathComponent(account))
    }

    func delete(_ account: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(account))
    }
}

#if os(Windows)
/// Logins encrypted with the Windows Data Protection API for the signed-in user, in files under
/// the user's local AppData. Credential Manager caps entries at 2.5 KB, which a Codex login
/// outgrows, so DPAPI files are the Windows keychain for secrets this size.
struct WindowsSecretStore: SecretStore {
    let files: FileSecretStore
    var name: String { "Windows Data Protection (DPAPI) files in \(files.directory.path)" }

    private static let entropy = Array("dev.switchr.vault".utf8)

    func read(_ account: String) -> Data? {
        guard let sealed = files.read(account) else { return nil }
        return Self.transform(sealed, protect: false)
    }

    func write(_ data: Data, account: String) throws {
        guard let sealed = Self.transform(data, protect: true) else {
            throw SwitchrError("Windows couldn't encrypt the login.")
        }
        try files.write(sealed, account: account)
    }

    func delete(_ account: String) {
        files.delete(account)
    }

    static func transform(_ data: Data, protect: Bool) -> Data? {
        var input = [UInt8](data)
        var salt = entropy
        return input.withUnsafeMutableBufferPointer { inputBytes in
            salt.withUnsafeMutableBufferPointer { saltBytes in
                var inBlob = DATA_BLOB(cbData: DWORD(inputBytes.count), pbData: inputBytes.baseAddress)
                var saltBlob = DATA_BLOB(cbData: DWORD(saltBytes.count), pbData: saltBytes.baseAddress)
                var outBlob = DATA_BLOB()
                let ok = protect
                    ? CryptProtectData(&inBlob, nil, &saltBlob, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), &outBlob)
                    : CryptUnprotectData(&inBlob, nil, &saltBlob, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), &outBlob)
                guard ok.boolValue, let bytes = outBlob.pbData else { return nil }
                defer { LocalFree(bytes) }
                return Data(bytes: bytes, count: Int(outBlob.cbData))
            }
        }
    }
}
#endif

#if os(Linux)
/// The freedesktop Secret Service (GNOME Keyring, KWallet) through libsecret's `secret-tool`.
/// Secrets go in over stdin, never on the command line. When no keyring answers, logins fall
/// back to private files, and reads check both so nothing saved earlier goes missing.
struct LinuxSecretStore: SecretStore {
    let service: String
    let files: FileSecretStore
    private let keyring: String?

    init(service: String, files: FileSecretStore) {
        self.service = service
        self.files = files
        keyring = Self.reachableKeyring(service: service)
    }

    var name: String {
        keyring == nil ? "\(files.name) (no Secret Service is running)" : "Secret Service (GNOME Keyring or KWallet)"
    }

    func read(_ account: String) -> Data? {
        if let keyring,
           let result = try? Shell.run(keyring, ["lookup", "service", service, "account", account]),
           result.status == 0, !result.stdout.isEmpty {
            var data = result.stdout
            while data.last == 0x0A { data.removeLast() }
            return data
        }
        return files.read(account)
    }

    func write(_ data: Data, account: String) throws {
        if let keyring,
           let result = try? Shell.run(keyring, ["store", "--label", "Switchr saved login", "service", service, "account", account], stdin: data),
           result.status == 0 {
            files.delete(account)
            return
        }
        try files.write(data, account: account)
    }

    func delete(_ account: String) {
        if let keyring {
            _ = try? Shell.run(keyring, ["clear", "service", service, "account", account])
        }
        files.delete(account)
    }

    /// `secret-tool`, when it's installed and a keyring answers a harmless lookup.
    private static func reachableKeyring(service: String) -> String? {
        guard let tool = Shell.which("secret-tool"),
              let probe = try? Shell.run(tool, ["lookup", "service", service, "account", "availability-check"]),
              probe.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return tool
    }
}
#endif
