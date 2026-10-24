import XCTest
@testable import Keyhop

/// The field left the window in 2.0; the website keeps its own copy in cloud/src/backdrop.ts.
/// What remains here is the saved appearance file, which older installs still carry.
final class BackdropTests: XCTestCase {
    func testTheDashboardCarriesNoBackdrop() {
        let page = DashboardPage.render(boot: nil)
        XCTAssertFalse(page.contains("KeyhopBackdrop"))
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

    func testTheWindowIsOneNight() {
        let page = DashboardPage.render(boot: nil)
        XCTAssertFalse(page.contains(#":root[data-theme="day"]"#), "the window's day field left with 1.x")
        // Every overlay tint reads from the ink hue, never a literal white.
        let style = page.components(separatedBy: "<style>")[1].components(separatedBy: "</style>")[0]
        XCTAssertFalse(style.contains("hsl(0 0% 100% / "))
    }
}
