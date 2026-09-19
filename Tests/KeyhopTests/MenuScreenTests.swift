#if os(macOS)
import AppKit
import SwiftUI
import Vision
import XCTest
@testable import Keyhop

/// Reads the menu bar panel the way a person does: off the screen itself.
///
/// The panel is SwiftUI, so there is no page to query and, hosted in a test, no accessibility tree
/// to walk either: macOS builds one only for a window a real assistive client is looking at. What
/// is left is what a person has, the pixels. Each screen is rendered and the words on it are read
/// back, so a label that goes missing, gets cut off, or turns into a placeholder fails here rather
/// than in front of someone.
@MainActor
final class MenuScreenTests: XCTestCase {
    private var savedTab: String?

    override func setUp() {
        savedTab = UserDefaults.standard.string(forKey: "menuTool")
    }

    override func tearDown() {
        // Someone's own menu opens where they left it, not where a test went.
        if let savedTab { UserDefaults.standard.set(savedTab, forKey: "menuTool") } else { UserDefaults.standard.removeObject(forKey: "menuTool") }
    }

    /// Renders a screen at the menu's real width and reads every word on it.
    private func words<V: View>(of view: V, width: CGFloat = 340) throws -> [String] {
        let renderer = ImageRenderer(content: view.frame(width: width).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw XCTSkip("This machine can't render SwiftUI offscreen.") }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        // Keyhop's screens are in English; without this, a mark like Pi's is read as another
        // alphabet's letter.
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.map(Self.latin)
    }

    /// Reading text off a screen is not exact: a few letters have twins in other alphabets, and
    /// Pi's mark next to its name is enough for the reader to pick the wrong one. The twins are
    /// turned back before anything is compared.
    private static let twins: [Character: Character] = [
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K", "М": "M", "О": "O", "Р": "P",
        "Т": "T", "Х": "X", "а": "a", "е": "e", "і": "i", "о": "o", "р": "p", "с": "c", "х": "x",
    ]

    private static func latin(_ text: String) -> String {
        String(text.map { twins[$0] ?? $0 })
    }

    /// The menu opens on the tab it last showed, which is saved, so the test says which one.
    private func menu(tab: Provider = .claude) -> some View {
        UserDefaults.standard.set(tab.rawValue, forKey: "menuTool")
        let store = AccountStore(preview: (), focus: tab)
        return MenuView()
            .environmentObject(store)
            .environmentObject(UsageTracker(preview: store))
            .environment(\.staticSnapshot, true)
    }

    /// Everything the panel promises about the account in use has to be on the panel.
    func testTheMenuShowsTheAccountInUseItsLimitsAndTheWayIn() throws {
        let said = try words(of: menu()).joined(separator: " | ")
        XCTAssertTrue(said.contains("Claude"), "the tool is never named: \(said)")
        XCTAssertTrue(said.contains("Personal"), "the account in use is never named: \(said)")
        XCTAssertTrue(said.contains("In use"), "nothing says which account is in use: \(said)")
        XCTAssertTrue(said.contains("5h") || said.contains("Week"), "no limit is shown: \(said)")
        XCTAssertTrue(said.contains("%"), "no limit reading is shown: \(said)")
        XCTAssertTrue(said.contains("Open Keyhop"), "there is no way into the window: \(said)")
        XCTAssertTrue(said.contains("Add"), "there is no way to add an account: \(said)")
    }

    /// Every tool draws its own panel, and every panel keeps its footer.
    func testEveryToolsPanelNamesItself() throws {
        for tool in Provider.allCases {
            let said = try words(of: menu(tab: tool)).joined(separator: " | ")
            XCTAssertTrue(said.contains(tool.shortName) || said.contains(tool.name),
                          "\(tool.name)'s panel never names it: \(said)")
            XCTAssertTrue(said.contains("Open Keyhop"), "\(tool.name): the footer is missing: \(said)")
        }
    }

    /// A value that never arrived must never reach the screen.
    func testNoScreenShowsAnUnfinishedValue() throws {
        for tool in Provider.allCases {
            for word in try words(of: menu(tab: tool)) {
                for bad in ["nil", "Optional(", "NaN", "(null)", "undefined", "Infinity"] {
                    XCTAssertFalse(word.contains(bad), "\(tool.name): the panel shows \"\(word)\"")
                }
            }
        }
    }

    /// The house style applies to what is on screen, not only to what is in the source.
    func testNoScreenUsesAnEmDash() throws {
        for tool in [Provider.claude, .cursor, .codex] {
            for word in try words(of: menu(tab: tool)) {
                XCTAssertFalse(word.contains("—"), "\(tool.name): the panel shows an em dash in \"\(word)\"")
            }
        }
    }

    /// The welcome window is the first thing anyone sees, and it names every tool Keyhop knows.
    func testTheWelcomeWindowNamesEveryTool() throws {
        let store = AccountStore(preview: ())
        let said = try words(of: WelcomeView(canMove: false, dismiss: {}).environmentObject(store), width: 420)
            .joined(separator: " | ")
        for tool in Provider.allCases {
            XCTAssertTrue(said.contains(tool.name) || said.contains(tool.shortName),
                          "the welcome window never mentions \(tool.name): \(said)")
        }
    }
}
#endif
