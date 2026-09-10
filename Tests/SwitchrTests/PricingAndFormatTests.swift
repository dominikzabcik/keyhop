import XCTest
@testable import Switchr

final class PricingTests: XCTestCase {
    func testNormalizeStripsPrefixesAndDateSuffixes() {
        XCTAssertEqual(Pricing.normalize("claude-haiku-4-5-20251001"), "claude-haiku-4-5")
        XCTAssertEqual(Pricing.normalize("cursor-grok-4.6-hi"), "grok-4.6-hi")
        XCTAssertEqual(Pricing.normalize("anthropic/Claude-Opus-5"), "claude-opus-5")
    }

    func testVariantsPriceLikeTheirBaseModel() {
        XCTAssertNotNil(Pricing.price(for: "claude-opus-5"))
        XCTAssertEqual(Pricing.price(for: "claude-opus-5-thinking"), Pricing.price(for: "claude-opus-5"))
        XCTAssertNil(Pricing.price(for: "definitely-not-a-model"))
    }

    func testEachTokenKindCostsItsOwnRate() {
        func cost(_ build: (inout TokenCounts) -> Void, fast: Bool = false) -> Double {
            var tokens = TokenCounts()
            build(&tokens)
            return Pricing.cost(model: "claude-opus-5", tokens: tokens, fast: fast)
        }
        XCTAssertEqual(cost { $0.input = 1_000_000 }, 5, accuracy: 1e-9)
        XCTAssertEqual(cost { $0.output = 1_000_000 }, 25, accuracy: 1e-9)
        XCTAssertEqual(cost { $0.cacheRead = 1_000_000 }, 0.5, accuracy: 1e-9)
        XCTAssertEqual(cost { $0.cacheWrite = 1_000_000 }, 6.25, accuracy: 1e-9)
        XCTAssertEqual(cost { $0.cacheWrite1h = 1_000_000 }, 10, accuracy: 1e-9)
        XCTAssertEqual(cost({ $0.input = 1_000_000 }, fast: true), 10, accuracy: 1e-9)
        XCTAssertEqual(Pricing.cost(model: "unknown-model", tokens: TokenCounts(input: 1_000_000)), 0)
    }
}

final class NumbersTests: XCTestCase {
    func testTokens() {
        XCTAssertEqual(Numbers.tokens(950), "950")
        XCTAssertEqual(Numbers.tokens(1_500), "1.5K")
        XCTAssertEqual(Numbers.tokens(100_000), "100K")
        XCTAssertEqual(Numbers.tokens(12_300_000), "12.3M")
        XCTAssertEqual(Numbers.tokens(3_000_000), "3M")
        XCTAssertEqual(Numbers.tokens(3_900_000_000), "3.9B")
    }

    func testDollarsUseUSFormattingEverywhere() {
        XCTAssertEqual(Numbers.usd(4.861), "$4.86")
        XCTAssertEqual(Numbers.usd(212.4), "$212")
        XCTAssertEqual(Numbers.usd(2621), "$2,621")
    }
}

final class UsageWindowTests: XCTestCase {
    func testLabelsFollowTheWindowLength() {
        XCTAssertEqual(UsageWindow.label(seconds: 18000), "5h")
        XCTAssertEqual(UsageWindow.label(seconds: 604_800), "Week")
        XCTAssertEqual(UsageWindow.label(seconds: 2_592_000), "Month")
        XCTAssertEqual(UsageWindow.label(seconds: 10_800), "3h")
        XCTAssertEqual(UsageWindow.label(seconds: nil), "Limit")
    }

    func testResetText() {
        let now = Date()
        func text(_ seconds: TimeInterval) -> String {
            UsageWindow(label: "5h", usedPercent: 0, resetsAt: now.addingTimeInterval(seconds), windowSeconds: 18000).resetText(at: now)
        }
        XCTAssertEqual(text(2 * 3600 + 14 * 60 + 5), "2h 14m")
        XCTAssertEqual(text(3 * 86400 + 4 * 3600 + 30), "3d 4h")
        XCTAssertEqual(text(20), "1m")
        XCTAssertEqual(text(-5), "now")
    }

    func testPaceIsTheShareOfTheWindowThatHasPassed() {
        let now = Date()
        let window = UsageWindow(label: "5h", usedPercent: 40, resetsAt: now.addingTimeInterval(3600), windowSeconds: 18000)
        XCTAssertEqual(window.pace(at: now)!, 0.8, accuracy: 1e-9)
    }
}

final class ParsingTests: XCTestCase {
    func testDatesWithMicrosecondsAndEpochMilliseconds() {
        XCTAssertNotNil(Dates.parse("2026-09-17T04:59:59.971196+00:00"))
        XCTAssertNotNil(Dates.parse("2026-09-10T10:09:23.757Z"))
        XCTAssertEqual(Dates.parse(1_757_494_800_000)?.timeIntervalSince1970, 1_757_494_800)
    }

    func testJWTClaimsDecodeWithoutPadding() {
        let payload = Data(#"{"sub":"auth0|user_1","exp":2000000000}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let token = "header.\(payload).signature"
        XCTAssertEqual(JWT.claims(token)?["sub"] as? String, "auth0|user_1")
        XCTAssertEqual(JWT.expiry(token)?.timeIntervalSince1970, 2_000_000_000)
    }

    func testCSVHandlesQuotesCommasAndLineBreaks() {
        let rows = CSV.rows("a,b\n\"x, y\",\"said \"\"hi\"\"\"\r\n\"two\nlines\",2\n")
        XCTAssertEqual(rows, [["a", "b"], ["x, y", "said \"hi\""], ["two\nlines", "2"]])
    }
}

final class UpdaterTests: XCTestCase {
    func testVersionsCompareNumerically() {
        XCTAssertTrue(Updater.isNewer("0.10.0", than: "0.9.1"))
        XCTAssertTrue(Updater.isNewer("0.6", than: "0.5.9"))
        XCTAssertFalse(Updater.isNewer("0.6.0", than: "0.6.0"))
        XCTAssertFalse(Updater.isNewer("1.0.0", than: "1.0.1"))
    }

    func testChecksumListing() {
        let listing = "abc123  Switchr.zip\ndef456 *Switchr.dmg\n"
        XCTAssertEqual(Updater.expectedHash(in: listing, for: "Switchr.zip"), "abc123")
        XCTAssertEqual(Updater.expectedHash(in: listing, for: "Switchr.dmg"), "def456")
        XCTAssertNil(Updater.expectedHash(in: listing, for: "Other.zip"))
    }
}
