import XCTest
@testable import Keyhop

final class BrowserTests: XCTestCase {
    private func account(_ email: String, _ identity: String, _ provider: Provider = .claude) -> Account {
        Account(id: UUID(), provider: provider, identity: identity, email: email, label: nil, plan: nil, addedAt: Date())
    }

    func testMessagesAreFramedWithALittleEndianLength() {
        let framed = BrowserHost.frame(Data("{}".utf8))
        XCTAssertEqual(Array(framed.prefix(4)), [2, 0, 0, 0])
        XCTAssertEqual(framed.dropFirst(4), Data("{}".utf8))
    }

    func testASiteLoginBelongsToTheSameAccountIDThenTheSameEmail() {
        let personal = account("me@x.dev", "uuid-a|org-1"), team = account("me@x.dev", "uuid-a|org-2")
        let other = account("you@x.dev", "uuid-b|org-1"), codex = account("me@x.dev", "user-1", .codex)
        let all = [personal, team, other, codex]
        XCTAssertEqual(BrowserSetup.matches(email: "ME@x.dev", webID: "uuid-a", site: .claude, in: all).map(\.id), [personal.id, team.id])
        XCTAssertEqual(BrowserSetup.matches(email: "you@x.dev", webID: "", site: .claude, in: all).map(\.id), [other.id])
        XCTAssertEqual(BrowserSetup.matches(email: "me@x.dev", webID: "", site: .chatgpt, in: all).map(\.id), [codex.id])
        XCTAssertTrue(BrowserSetup.matches(email: "nobody@x.dev", webID: "", site: .claude, in: all).isEmpty)
    }

    func testTheHostManifestNamesOnlyKeyhopsExtension() throws {
        let manifest = try XCTUnwrap(JSON.object(try BrowserSetup.hostManifest(executable: "/Applications/Keyhop.app/Contents/MacOS/Keyhop")))
        XCTAssertEqual(manifest["name"] as? String, "app.keyhop.browser")
        XCTAssertEqual(manifest["type"] as? String, "stdio")
        XCTAssertEqual(manifest["allowed_origins"] as? [String], ["chrome-extension://\(BrowserExtensionFiles.id)/"])
    }

    func testTheExtensionManifestIsValidAndCarriesItsKey() throws {
        let manifest = try XCTUnwrap(JSON.object(BrowserExtensionFiles.manifest))
        XCTAssertEqual(manifest["manifest_version"] as? Int, 3)
        XCTAssertNotNil(manifest["key"] as? String)
        XCTAssertEqual(Set(BrowserExtensionFiles.images.keys), ["icon-32.png", "icon-48.png", "icon-128.png"])
        for (_, png) in BrowserExtensionFiles.images { XCTAssertNotNil(Data(base64Encoded: png)) }
    }

    func testTheHostKeepsASiteLoginAndHandsItBack() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-browser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let me = account("me@x.dev", "uuid-a|org")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([me]).write(to: directory.appendingPathComponent("accounts.json"))
        let vault = Vault(store: MemorySecretStore())
        let host = BrowserHost(directory: directory, vault: vault, send: { _ in })
        let cookie = BrowserCookie(name: "sessionKey", value: "sk", domain: ".claude.ai", path: "/", secure: true, httpOnly: true,
                                   sameSite: "lax", hostOnly: false, expirationDate: nil)

        let saved = await host.handle(.init(type: "session", id: "1", site: "claude.ai", email: "me@x.dev", webId: "uuid-a", cookies: [cookie]))
        XCTAssertEqual(saved?.type, "saved")
        let unknown = await host.handle(.init(type: "session", id: "2", site: "claude.ai", email: "else@x.dev", webId: "", cookies: [cookie]))
        XCTAssertEqual(unknown?.type, "unknown")
        let back = await host.handle(.init(type: "cookies", id: "3", site: "claude.ai", account: me.id.uuidString))
        XCTAssertEqual(back?.cookies, [cookie])
        let sites = await host.sites()
        XCTAssertEqual(sites.first { $0.site == "claude.ai" }?.accounts.first?.web, true)
    }
}
