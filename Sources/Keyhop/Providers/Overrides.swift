import Foundation

/// Credentials that outrank the login Keyhop swaps. Each tool reads these before its saved
/// login file or Keychain item, so while one is present a hop changes nothing: the tool keeps
/// using the higher credential. They are the person's own setup, so Keyhop never removes them;
/// it names them in `doctor` and after a switch instead.
enum Overrides {
    static func list(for provider: Provider) -> [String] {
        list(for: provider, environment: ProcessInfo.processInfo.environment, home: Files.home)
    }

    static func list(for provider: Provider, environment: [String: String], home: URL) -> [String] {
        switch provider {
        case .claude: claude(environment, home)
        case .codex: codex(environment, home)
        case .cursor: cursor(environment)
        case .gemini: gemini(environment)
        case .opencode: opencode(environment)
        case .copilot: copilot(environment, home)
        case .pi, .windsurf, .codebuff: []
        // Measured-only tools have no login Keyhop swaps, so nothing can outrank it.
        case .amp, .goose, .qwen, .kimi, .grok, .kilo, .openclaw: []
        }
    }

    // MARK: Per tool

    /// Claude Code's documented order puts cloud routing, env tokens and the key helper all
    /// above the subscription OAuth that Keyhop swaps.
    private static func claude(_ env: [String: String], _ home: URL) -> [String] {
        var found: [String] = []
        let clouds = [("CLAUDE_CODE_USE_BEDROCK", "Bedrock"), ("CLAUDE_CODE_USE_VERTEX", "Vertex"), ("CLAUDE_CODE_USE_FOUNDRY", "Foundry")]
        for (key, name) in clouds where isOn(env[key]) {
            found.append("\(key) is set: Claude Code talks to \(name) and the saved login isn't used.")
        }
        for key in ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"] where isSet(env[key]) {
            found.append("\(key) is set and outranks the saved login.")
        }
        let settings = ClaudeAdapter.configDirectory(environment: env, home: home).appendingPathComponent("settings.json")
        if let object = read(settings), object["apiKeyHelper"] != nil {
            found.append("settings.json sets apiKeyHelper, which outranks the saved login.")
        }
        return found
    }

    /// Swapping `auth.json` only moves Codex when its credential store is `file`. With `keyring`
    /// the file isn't the live secret, and `auto` means keyring wherever one is available.
    private static func codex(_ env: [String: String], _ home: URL) -> [String] {
        let config = CodexAdapter.homeDirectory(environment: env, home: home).appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return [] }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("cli_auth_credentials_store") else { continue }
            guard let value = trimmed.split(separator: "=").dropFirst().first?
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) else { continue }
            switch value {
            case "keyring":
                return ["config.toml sets cli_auth_credentials_store = \"keyring\": the login lives in the system keyring, and swapping auth.json doesn't change it."]
            case "auto":
                return ["config.toml sets cli_auth_credentials_store = \"auto\": the login likely lives in the system keyring, and swapping auth.json then changes nothing."]
            case "ephemeral":
                return ["config.toml sets cli_auth_credentials_store = \"ephemeral\": logins aren't saved at all, so there is nothing a switch can move."]
            default:
                return []
            }
        }
        return []
    }

    private static func cursor(_ env: [String: String]) -> [String] {
        guard isSet(env["CURSOR_API_KEY"]) else { return [] }
        return ["CURSOR_API_KEY is set and outranks the saved login for cursor-agent and the SDK."]
    }

    private static func gemini(_ env: [String: String]) -> [String] {
        var found: [String] = []
        if isSet(env["GEMINI_API_KEY"]) {
            found.append("GEMINI_API_KEY is set: Gemini CLI uses it instead of the Google login.")
        }
        if isOn(env["GOOGLE_GENAI_USE_VERTEXAI"]) {
            found.append("GOOGLE_GENAI_USE_VERTEXAI is set: Gemini CLI talks to Vertex and the saved login isn't used.")
        }
        // The flag must be exactly "true"; in that mode oauth_creds.json is migrated away and deleted.
        if env["GEMINI_FORCE_ENCRYPTED_FILE_STORAGE"] == "true" {
            found.append("GEMINI_FORCE_ENCRYPTED_FILE_STORAGE is on: the login lives in an encrypted store, and swapping oauth_creds.json doesn't change it.")
        }
        return found
    }

    private static func opencode(_ env: [String: String]) -> [String] {
        guard isSet(env["OPENCODE_AUTH_CONTENT"]) else { return [] }
        return ["OPENCODE_AUTH_CONTENT is set and replaces auth.json."]
    }

    /// Copilot CLI reads its own token env vars and its own saved login before it falls back to
    /// the gh login that Keyhop switches.
    private static func copilot(_ env: [String: String], _ home: URL) -> [String] {
        var found: [String] = []
        for key in ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"] where isSet(env[key]) {
            found.append("\(key) is set and outranks the gh login Keyhop switches.")
        }
        let config = home.appendingPathComponent(".copilot/config.json")
        if let object = read(config), let users = object["loggedInUsers"] as? [Any], !users.isEmpty {
            found.append("Copilot CLI has its own saved login (~/.copilot/config.json), so switching gh doesn't move it. Use `copilot /user switch`.")
        }
        return found
    }

    // MARK: Helpers

    private static func isSet(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Set, and not spelled "off": flags like CLAUDE_CODE_USE_BEDROCK treat 0/false as absent.
    private static func isOn(_ value: String?) -> Bool {
        guard isSet(value), let value else { return false }
        return !["0", "false", "no"].contains(value.lowercased())
    }

    private static func read(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { JSON.object($0) }
    }
}
