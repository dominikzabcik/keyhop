import XCTest
@testable import Switchr

final class BackdropTests: XCTestCase {
    func testTheAppAndTheWebsiteShareOneBackdropScript() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("cloud/src/backdrop.ts"), encoding: .utf8)
        guard let start = text.range(of: "/* backdrop:start */"), let end = text.range(of: "/* backdrop:end */") else {
            return XCTFail("cloud/src/backdrop.ts has lost its backdrop markers")
        }
        XCTAssertEqual(String(text[start.lowerBound..<end.upperBound]), Backdrop.script,
                       "The copies differ. Run scripts/sync-backdrop.py after changing cloud/src/backdrop.ts.")
    }

    func testTheDashboardCarriesTheBackdrop() {
        let page = DashboardPage.render(boot: nil)
        XCTAssertTrue(page.contains("window.SwitchrBackdrop = { mount: mount, sprite: sprite }"))
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
    }
}
