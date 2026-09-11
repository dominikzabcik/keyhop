import XCTest
@testable import Switchr

final class FieldTests: XCTestCase {
    func testTheAppAndTheWebsiteShareOneFieldScript() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("cloud/src/field.ts"), encoding: .utf8)
        guard let start = text.range(of: "/* field:start */"), let end = text.range(of: "/* field:end */") else {
            return XCTFail("cloud/src/field.ts has lost its field markers")
        }
        XCTAssertEqual(String(text[start.lowerBound..<end.upperBound]), Field.script,
                       "The copies differ. Run scripts/sync-field.py after changing cloud/src/field.ts.")
    }

    func testTheDashboardCarriesTheField() {
        let page = DashboardPage.render(boot: nil)
        XCTAssertTrue(page.contains("window.SwitchrField = { mount: mount }"))
        XCTAssertFalse(page.contains("{{field}}"))
    }
}
