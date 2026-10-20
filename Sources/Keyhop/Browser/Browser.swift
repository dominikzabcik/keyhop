import Foundation

/// The sites that follow a hop: each one's login in a Chromium browser belongs to a tool's
/// account, because the same subscription signs in to both.
enum BrowserSite: String, CaseIterable, Sendable {
    case claude = "claude.ai"
    case chatgpt = "chatgpt.com"

    var provider: Provider {
        switch self {
        case .claude: .claude
        case .chatgpt: .codex
        }
    }

    static func of(_ provider: Provider) -> BrowserSite? {
        allCases.first { $0.provider == provider }
    }
}

/// One cookie as `chrome.cookies` describes it, enough to set it again.
struct BrowserCookie: Codable, Equatable, Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var secure: Bool
    var httpOnly: Bool
    var sameSite: String?
    var hostOnly: Bool
    var expirationDate: Double?
}

/// A site's cookies for one account, kept in the vault beside the tool's own login.
struct WebSession: Codable, Equatable, Sendable {
    var site: String
    var email: String
    var cookies: [BrowserCookie]
    var savedAt: Date
}

extension Vault {
    private static func webKey(_ id: UUID) -> String { "web-\(id.uuidString)" }

    func webSession(_ id: UUID) -> WebSession? {
        guard let raw = webStore.read(Self.webKey(id)), let json = Data(base64Encoded: raw) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WebSession.self, from: json)
    }

    @discardableResult
    func writeWebSession(_ session: WebSession, for id: UUID) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let json = try? encoder.encode(session) else { return false }
        return (try? webStore.write(Data(json.base64EncodedString().utf8), account: Self.webKey(id))) != nil
    }

    func deleteWebSession(_ id: UUID) {
        webStore.delete(Self.webKey(id))
    }
}

// MARK: Setup

/// Where the extension and the native host's manifest go, and what is set up already.
enum BrowserSetup {
    static let hostName = "app.keyhop.browser"
    static let origin = "chrome-extension://\(BrowserExtensionFiles.id)/"

    static var extensionFolder: URL {
        Platform.dataDirectory.appendingPathComponent("Chrome Extension", isDirectory: true)
    }

    static var seenFile: URL { Platform.dataDirectory.appendingPathComponent("browser.json") }

    struct Browser: Codable, Equatable, Sendable {
        let name: String
        /// The browser's own folder; it exists once the browser has run.
        let root: String
        var found: Bool
        var registered: Bool
        var manifest: String { root + "/NativeMessagingHosts/\(BrowserSetup.hostName).json" }
    }

    /// Chromium browsers by the folder each keeps its profiles in.
    /// The home Chrome itself uses: `$HOME` when it is set.
    static var home: URL {
        ProcessInfo.processInfo.environment["HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil } ?? Files.home
    }

    static func browsers(home: URL = BrowserSetup.home) -> [Browser] {
        #if os(macOS)
        let base = home.appendingPathComponent("Library/Application Support")
        let folders = [("Google Chrome", "Google/Chrome"), ("Chrome Beta", "Google/Chrome Beta"), ("Chrome Canary", "Google/Chrome Canary"),
                       ("Chromium", "Chromium"), ("Microsoft Edge", "Microsoft Edge"), ("Brave", "BraveSoftware/Brave-Browser"),
                       ("Arc", "Arc/User Data"), ("Vivaldi", "Vivaldi")]
        #else
        let config = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        let base = config.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? home.appendingPathComponent(".config")
        let folders = [("Google Chrome", "google-chrome"), ("Chrome Beta", "google-chrome-beta"), ("Chromium", "chromium"),
                       ("Microsoft Edge", "microsoft-edge"), ("Brave", "BraveSoftware/Brave-Browser"), ("Vivaldi", "vivaldi")]
        #endif
        return folders.map { name, folder in
            let root = base.appendingPathComponent(folder).path
            var browser = Browser(name: name, root: root, found: FileManager.default.fileExists(atPath: root), registered: false)
            browser.registered = FileManager.default.fileExists(atPath: browser.manifest)
            return browser
        }
    }

    /// The binary Chrome starts as the host: this one, with symlinks resolved, so a Homebrew or
    /// installer link still points at the real file.
    static var executable: String {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
    }

    static func hostManifest(executable: String) throws -> Data {
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Keyhop: moves claude.ai and chatgpt.com to the account Keyhop hops to",
            "path": executable,
            "type": "stdio",
            "allowed_origins": [origin],
        ]
        return try JSON.data(manifest, pretty: true)
    }

    struct Report: Codable, Sendable {
        var extensionFolder: String
        var extensionID: String
        var installed: Bool
        var browsers: [Browser]
        /// When the extension last talked to Keyhop, and from which version.
        var lastSeen: Date?
        var extensionVersion: String?
        /// Saved accounts with a site login kept for hops.
        var webLogins: [String]
    }

    struct Seen: Codable {
        var lastSeen: Date
        var extensionVersion: String?
    }

    static func report(vault: Vault, accounts: [Account], home: URL = BrowserSetup.home) async -> Report {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let seen = (try? Data(contentsOf: seenFile)).flatMap { try? decoder.decode(Seen.self, from: $0) }
        var web: [String] = []
        for account in accounts where BrowserSite.of(account.provider) != nil {
            if await vault.webSession(account.id) != nil { web.append(account.id.uuidString) }
        }
        let folder = extensionFolder
        return Report(extensionFolder: folder.path, extensionID: BrowserExtensionFiles.id,
                      installed: FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path),
                      browsers: browsers(home: home), lastSeen: seen?.lastSeen, extensionVersion: seen?.extensionVersion, webLogins: web)
    }

    /// Writes the extension's files and registers the host with every Chromium browser that has
    /// run here, and with Chrome even before it has.
    static func install(home: URL = BrowserSetup.home, executable: String = executable) throws {
        #if os(Windows)
        throw KeyhopError("The browser extension isn't available on Windows yet.")
        #else
        let folder = extensionFolder
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in BrowserExtensionFiles.text {
            try Data(text.utf8).write(to: folder.appendingPathComponent(name))
        }
        for (name, base64) in BrowserExtensionFiles.images {
            guard let data = Data(base64Encoded: base64) else { continue }
            try data.write(to: folder.appendingPathComponent(name))
        }
        let manifest = try hostManifest(executable: executable)
        for (index, browser) in browsers(home: home).enumerated() where browser.found || index == 0 {
            let target = URL(fileURLWithPath: browser.manifest)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manifest.write(to: target)
        }
        #endif
    }

    static func remove(home: URL = BrowserSetup.home) {
        for browser in browsers(home: home) where browser.registered {
            try? FileManager.default.removeItem(atPath: browser.manifest)
        }
        try? FileManager.default.removeItem(at: extensionFolder)
        try? FileManager.default.removeItem(at: seenFile)
    }

    /// Which saved accounts a site's signed-in user is: the same account ID when the site gives
    /// one, otherwise the same email. A Claude login with several organizations is one web login.
    static func matches(email: String, webID: String, site: BrowserSite, in accounts: [Account]) -> [Account] {
        let mine = accounts.filter { $0.provider == site.provider }
        if !webID.isEmpty {
            let byID = mine.filter { $0.identity == webID || $0.identity.hasPrefix(webID + "|") }
            if !byID.isEmpty { return byID }
        }
        return mine.filter { $0.email.caseInsensitiveCompare(email) == .orderedSame }
    }
}
