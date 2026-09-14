import XCTest
@testable import Keyhop

final class KeyhopTests: XCTestCase {
    func testTokenFormatting() {
        XCTAssertEqual(Format.tokens(999), "999")
        XCTAssertEqual(Format.tokens(1_000), "1K")
        XCTAssertEqual(Format.tokens(1_500_000), "1.5M")
        XCTAssertEqual(Format.tokens(4_140_000_000), "4.1B")
    }

    func testTierFormatting() {
        XCTAssertEqual(Format.tier(.init(key: "platinum", name: "Platinum", division: 2)), "Platinum II")
        XCTAssertEqual(Format.tier(.init(key: "master", name: "Master", division: nil)), "Master")
    }

    func testProfileURL() {
        let link = PhoneLink(server: "https://keyhop.app", login: "mira", name: nil)
        XCTAssertEqual(link.profileURL?.absoluteString, "https://keyhop.app/u/mira")
    }

    @MainActor
    func testVerificationURLStaysOnTheConfiguredServer() {
        XCTAssertEqual(
            Store.verificationURL("https://keyhop.app/link?code=ABCD-2345", server: "https://keyhop.app")?.host,
            "keyhop.app"
        )
        XCTAssertNil(Store.verificationURL("https://example.com/link", server: "https://keyhop.app"))
        XCTAssertNil(Store.verificationURL("javascript:alert(1)", server: "https://keyhop.app"))
    }

    func testTokenStoreRoundTrip() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? TokenStore.clear(account: account) }

        try TokenStore.write("first-token", account: account)
        XCTAssertEqual(TokenStore.read(account: account), "first-token")
        try TokenStore.write("replacement-token", account: account)
        XCTAssertEqual(TokenStore.read(account: account), "replacement-token")
        try TokenStore.clear(account: account)
        XCTAssertNil(TokenStore.read(account: account))
    }
}
