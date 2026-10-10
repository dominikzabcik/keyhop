import XCTest
@testable import Keyhop

final class OverrideTests: XCTestCase {
    private var home: URL!

    override func setUp() {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-overrides-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ text: String, to path: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testACleanMachineHasNoOverrides() {
        for provider in Provider.allCases {
            XCTAssertEqual(Overrides.list(for: provider, environment: [:], home: home), [], "\(provider)")
        }
    }

    func testClaudeEnvTokensAndCloudRoutingAreNamed() {
        let found = Overrides.list(for: .claude, environment: [
            "ANTHROPIC_API_KEY": "sk-ant-x",
            "CLAUDE_CODE_USE_BEDROCK": "1",
        ], home: home)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains { $0.contains("Bedrock") })
        XCTAssertTrue(found.contains { $0.contains("ANTHROPIC_API_KEY") })
    }

    func testAFlagSpelledOffDoesNotCount() {
        XCTAssertEqual(Overrides.list(for: .claude, environment: ["CLAUDE_CODE_USE_VERTEX": "false"], home: home), [])
        XCTAssertEqual(Overrides.list(for: .claude, environment: ["ANTHROPIC_API_KEY": "  "], home: home), [])
    }

    func testClaudeApiKeyHelperInSettingsIsNamed() throws {
        try write(#"{"apiKeyHelper": "/usr/local/bin/key.sh"}"#, to: ".claude/settings.json")
        let found = Overrides.list(for: .claude, environment: [:], home: home)
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found[0].contains("apiKeyHelper"))
    }

    func testClaudeSettingsFollowTheConfigDir() throws {
        let custom = home.appendingPathComponent("elsewhere").path
        try write(#"{"apiKeyHelper": "x"}"#, to: "elsewhere/settings.json")
        XCTAssertEqual(Overrides.list(for: .claude, environment: ["CLAUDE_CONFIG_DIR": custom], home: home).count, 1)
        // The default location is not consulted once the config dir moves.
        try write(#"{"apiKeyHelper": "x"}"#, to: ".claude/settings.json")
        XCTAssertEqual(Overrides.list(for: .claude, environment: [:], home: home).count, 1)
    }

    func testCodexKeyringStoreIsNamedAndFileStoreIsNot() throws {
        try write("cli_auth_credentials_store = \"keyring\"\n", to: ".codex/config.toml")
        var found = Overrides.list(for: .codex, environment: [:], home: home)
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found[0].contains("keyring"))

        try write("cli_auth_credentials_store = \"file\"\n", to: ".codex/config.toml")
        found = Overrides.list(for: .codex, environment: [:], home: home)
        XCTAssertEqual(found, [])
    }

    func testCodexConfigFollowsCodexHome() throws {
        try write("cli_auth_credentials_store = \"ephemeral\"\n", to: "codex-home/config.toml")
        let env = ["CODEX_HOME": home.appendingPathComponent("codex-home").path]
        XCTAssertEqual(Overrides.list(for: .codex, environment: env, home: home).count, 1)
    }

    func testCopilotEnvTokensAndOwnLoginAreNamed() throws {
        try write(#"{"loggedInUsers": ["octocat"]}"#, to: ".copilot/config.json")
        let found = Overrides.list(for: .copilot, environment: ["GH_TOKEN": "ghp_x"], home: home)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains { $0.contains("GH_TOKEN") })
        XCTAssertTrue(found.contains { $0.contains("/user switch") })
    }

    func testCopilotEmptyLoggedInUsersIsNotAnOverride() throws {
        try write(#"{"loggedInUsers": []}"#, to: ".copilot/config.json")
        XCTAssertEqual(Overrides.list(for: .copilot, environment: [:], home: home), [])
    }

    func testGeminiEncryptedStorageMustBeExactlyTrue() {
        XCTAssertEqual(Overrides.list(for: .gemini, environment: ["GEMINI_FORCE_ENCRYPTED_FILE_STORAGE": "TRUE"], home: home), [])
        XCTAssertEqual(Overrides.list(for: .gemini, environment: ["GEMINI_FORCE_ENCRYPTED_FILE_STORAGE": "true"], home: home).count, 1)
    }

    func testCursorAndOpenCodeEnvKeysAreNamed() {
        XCTAssertEqual(Overrides.list(for: .cursor, environment: ["CURSOR_API_KEY": "k"], home: home).count, 1)
        XCTAssertEqual(Overrides.list(for: .opencode, environment: ["OPENCODE_AUTH_CONTENT": "{}"], home: home).count, 1)
    }
}
