import XCTest
@testable import Keyhop

final class BackdropTests: XCTestCase {
    func testTheAppAndTheWebsiteShareOneBackdropScript() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // Windows checks the file out with CRLF line endings, so compare the text itself, not them.
        let text = try String(contentsOf: root.appendingPathComponent("cloud/src/backdrop.ts"), encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
        guard let start = text.range(of: "/* backdrop:start */"), let end = text.range(of: "/* backdrop:end */") else {
            return XCTFail("cloud/src/backdrop.ts has lost its backdrop markers")
        }
        XCTAssertEqual(String(text[start.lowerBound..<end.upperBound]), Backdrop.script,
                       "The copies differ. Run scripts/sync-backdrop.py after changing cloud/src/backdrop.ts.")
    }

    func testTheDashboardCarriesTheBackdrop() {
        let page = DashboardPage.render(boot: nil)
        XCTAssertTrue(page.contains("window.KeyhopBackdrop = { mount: mount, sprite: sprite }"))
        XCTAssertFalse(page.contains("{{backdrop}}"))
    }

    func testAnOldFieldAppearanceFallsBackToTheDefaults() throws {
        let old = #"{"image":false,"intensity":0.6,"scene":"planet","tint":"ultraviolet"}"#
        XCTAssertNil(try? DashboardJSON.decoder.decode(DashboardAppearance.self, from: Data(old.utf8)))
        XCTAssertEqual(DashboardAppearance().scene, "leaves")
    }

    func testAnAppearanceSavedBeforeWindowOpacityGetsTheDefault() throws {
        let saved = #"{"image":false,"opacity":0.6,"scene":"orbit","scope":"all"}"#
        let appearance = try DashboardJSON.decoder.decode(DashboardAppearance.self, from: Data(saved.utf8))
        XCTAssertEqual(appearance.scene, "orbit")
        XCTAssertEqual(appearance.glass, 0.85)
        XCTAssertEqual(appearance.blur, 24)
        XCTAssertEqual(appearance.theme, "night")
    }

    func testTheSavedFieldRoundTrips() throws {
        var appearance = DashboardAppearance()
        appearance.theme = "day"
        let data = try DashboardJSON.encoder.encode(appearance)
        XCTAssertEqual(try DashboardJSON.decoder.decode(DashboardAppearance.self, from: data).theme, "day")
        XCTAssertEqual(DashboardAppearance.themes, ["night", "day", "auto"])
    }

    func testThePageCarriesBothFields() {
        let page = DashboardPage.render(boot: nil)
        XCTAssertTrue(page.contains(#":root[data-theme="day"]"#))
        XCTAssertTrue(page.contains("prefers-color-scheme: light"))
        XCTAssertTrue(page.contains(#"id="status-theme""#))
        // Every overlay tint reads from the ink hue, so the day field never paints white on white.
        let style = page.components(separatedBy: "<style>")[1].components(separatedBy: "</style>")[0]
        XCTAssertFalse(style.contains("hsl(0 0% 100% / "))
    }
}
