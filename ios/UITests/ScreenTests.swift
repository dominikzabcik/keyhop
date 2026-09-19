import XCTest

/// Drives the phone app the way a person does, on every screen it has.
///
/// Each test opens the app with sample data, walks to a screen, and checks the things that can be
/// checked without a picture: that what must be there is there, that every control has a name and
/// can be reached, and that no label is empty or truncated to nothing. Each screen's accessibility
/// tree is also written out, so the same questions asked of the website's pages can be asked of
/// these.
final class ScreenTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
    }

    private func launch(_ arguments: [String]) {
        app.launchArguments = arguments
        app.launch()
    }

    /// Saves what the screen offers, for the review that reads screens rather than looks at them.
    private func record(_ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "screen-\(name)"
        tree.lifetime = .keepAlways
        add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "screen-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Every button and every image a screen shows has to say what it is, or a screen reader has
    /// nothing to read out.
    private func everythingIsNamed(file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.frame
        for kind in [app.buttons, app.switches, app.images] {
            let all = kind.allElementsBoundByIndex.filter { $0.exists && screen.contains($0.frame) }
            let named = all.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            for element in all {
                guard !Self.systemParts.contains(element.identifier) else { continue }
                guard element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                // A switch is drawn as a named row around the switch itself. A screen reader lands
                // on the row, so an unnamed part inside a named one is reachable by name.
                let wrapped = named.contains { $0.frame.contains(element.frame) && $0.frame != element.frame }
                XCTAssertTrue(
                    wrapped,
                    "a control has no name for a screen reader: \(element.debugDescription.prefix(200))",
                    file: file, line: line)
            }
        }
    }

    /// Parts of the simulator, not of Keyhop.
    private static let systemParts: Set<String> = ["AdditionalDimmingOverlay", "PopoverDismissRegion"]

    /// The controls a screen reader actually lands on: the named ones, without the unnamed parts
    /// they are drawn from.
    private func reachable(_ query: XCUIElementQuery) -> [XCUIElement] {
        query.allElementsBoundByIndex.filter {
            $0.exists && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Nothing on screen says a value that never arrived.
    private func nothingIsBroken(file: StaticString = #filePath, line: UInt = #line) {
        for text in app.staticTexts.allElementsBoundByIndex where text.exists {
            for bad in ["nil", "undefined", "NaN", "(null)", "Optional("] {
                XCTAssertFalse(text.label.contains(bad), "a label says \"\(text.label)\"", file: file, line: line)
            }
        }
    }

    func testTheSeasonScreenShowsLimitsSeasonAndQuests() {
        launch(["--sample"])
        XCTAssertTrue(app.staticTexts["Limits"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Quests"].exists)
        // A limit is only useful with its countdown next to it.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'back in'")).count > 0
            || app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'left'")).count > 0)
        everythingIsNamed()
        nothingIsBroken()
        record("season")
    }

    func testTheBoardIsReachedByScrollingAndNamesTheRanks() {
        launch(["--sample", "--scroll-end"])
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 10))
        let you = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'You'")).firstMatch
        XCTAssertTrue(you.exists, "the board has to show where you stand")
        everythingIsNamed()
        nothingIsBroken()
        record("board")
    }

    func testAlertsOpenAndEachSwitchSaysWhatItDoes() {
        launch(["--sample", "--show-alerts"])
        XCTAssertTrue(app.staticTexts["Alerts"].waitForExistence(timeout: 10))
        let switches = reachable(app.switches)
        XCTAssertGreaterThanOrEqual(switches.count, 2, "both alert settings have to be named and offered")
        XCTAssertTrue(switches.contains { $0.label.contains("limit comes back") }, "the limit alert is missing")
        XCTAssertTrue(switches.contains { $0.label.contains("Seasons") }, "the season alert is missing")
        // A switch that cannot be turned on is not a setting.
        let first = switches[0]
        let before = first.value as? String
        first.tap()
        XCTAssertNotEqual(first.value as? String, before, "the switch did not change when tapped")
        record("alerts")

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Limits"].waitForExistence(timeout: 5), "Done returns to the season")
    }

    func testTheLinkScreenExplainsItselfAndOffersOneAction() {
        launch([])
        XCTAssertTrue(app.staticTexts["Every account."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Link with GitHub"].exists)
        // The phone only reads, and the screen has to say so before anyone links anything.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'only reads'")).count > 0)
        everythingIsNamed()
        nothingIsBroken()
        record("link")
    }

    func testWaitingForApprovalShowsTheCodeAndAWayBack() {
        launch(["--sample-waiting"])
        XCTAssertTrue(app.staticTexts["Approve this code in your browser"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Cancel"].exists, "a wait needs a way out")
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Open the page again'")).count > 0)
        everythingIsNamed()
        nothingIsBroken()
        record("waiting")
    }

    /// Larger text is a setting, not an edge case: the screens have to survive it.
    func testTheSeasonScreenSurvivesTheLargestText() {
        app.launchArguments = ["--sample"]
        app.launchEnvironment["XCUI_CONTENT_SIZE"] = "UICTContentSizeCategoryAccessibilityExtraLarge"
        app.launch()
        XCTAssertTrue(app.staticTexts["Limits"].waitForExistence(timeout: 10))
        nothingIsBroken()
        record("season-large-text")
    }
}
