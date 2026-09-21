import XCTest
@testable import Keyhop

/// Reading a day out of git: naming a repository, placing a commit in a calendar, and knowing when
/// a repository is worth reading again.
final class GitWorkTests: XCTestCase {
    func testARemoteBecomesOwnerAndName() {
        let cases = [
            "git@github.com:dominikzabcik/keyhop.git": "dominikzabcik/keyhop",
            "git@github.com:dominikzabcik/keyhop": "dominikzabcik/keyhop",
            "https://github.com/dominikzabcik/keyhop.git": "dominikzabcik/keyhop",
            "https://github.com/dominikzabcik/keyhop": "dominikzabcik/keyhop",
            "ssh://git@gitlab.com/team/group/service.git": "group/service",
            "https://user:token@github.com/acme/atlas.git": "acme/atlas",
        ]
        for (remote, expected) in cases {
            XCTAssertEqual(GitWork.ownerAndName(from: remote), expected, remote)
        }
        // Nothing that can be split into an owner and a name, so the folder gets to say instead.
        XCTAssertNil(GitWork.ownerAndName(from: "keyhop"))
        XCTAssertNil(GitWork.ownerAndName(from: ""))
        XCTAssertNil(GitWork.ownerAndName(from: "/"))
    }

    func testAStrangeRemoteCannotFailAnUpload() throws {
        // The website takes owner/name built from these characters and nothing else, so anything a
        // folder or a remote can hold has to come back inside that alphabet.
        let name = try XCTUnwrap(GitWork.ownerAndName(from: "git@example.com:a b/c:d*e.git"))
        let pattern = try NSRegularExpression(pattern: "^[A-Za-z0-9._-]{1,60}/[A-Za-z0-9._-]{1,60}$")
        let range = NSRange(name.startIndex..., in: name)
        XCTAssertNotNil(pattern.firstMatch(in: name, range: range), name)
    }

    func testACommitKeepsTheCalendarItsAuthorWasLivingIn() {
        // Late evening two hours east of UTC is still that evening, not the next morning.
        let evening = GitWork.localDay(fromISO: "2026-09-21T23:30:00+02:00")
        XCTAssertEqual(evening?.day, "2026-09-21")
        XCTAssertEqual(evening?.offset, 7200)

        let west = GitWork.localDay(fromISO: "2026-09-21T01:15:00-05:30")
        XCTAssertEqual(west?.day, "2026-09-21")
        XCTAssertEqual(west?.offset, -19800)

        XCTAssertEqual(GitWork.localDay(fromISO: "2026-09-21T12:00:00Z")?.offset, 0)
        XCTAssertNil(GitWork.localDay(fromISO: "2026-09-21"))
        XCTAssertNil(GitWork.localDay(fromISO: ""))
    }

    func testAnIndexRemembersWhetherARepositoryIsWorthReadingAgain() throws {
        // Whole seconds, because that is all the encoder keeps and the round trip below compares.
        let at = Date(timeIntervalSince1970: 1_789_000_000)
        let entry = WorkIndex.Entry(repo: "acme/atlas", head: "abc1234", since: "2026-09-14",
                                    hadSubjects: false, scannedAt: at)
        var index = WorkIndex()
        index.repos["/code/atlas"] = entry
        index.total = 1
        index.done = 1
        index.completedAt = at
        XCTAssertTrue(index.isComplete)

        // Half way through a first pass is not complete, however many repositories it has read.
        var running = index
        running.completedAt = nil
        XCTAssertFalse(running.isComplete)
        running.completedAt = at
        running.done = 11
        running.total = 40
        XCTAssertFalse(running.isComplete)

        // It survives a round trip, because it is read back on the next launch.
        let copy = try DashboardJSON.decoder.decode(WorkIndex.self, from: DashboardJSON.encoder.encode(index))
        XCTAssertEqual(copy, index)
    }

    func testIndexingReportsHowFarItHasGot() {
        let step = WorkProgress(step: .repositories, done: 11, total: 40, detail: "keyhop")
        XCTAssertEqual(step.title, "Indexing repositories")
        XCTAssertEqual(step.count, "11 of 40")
        XCTAssertEqual(step.brief, "Repos 11/40")
        XCTAssertEqual(step.fraction ?? 0, 11.0 / 40, accuracy: 1e-9)
        XCTAssertEqual(TerminalProgress.line(step, width: 4), "Indexing repositories  [#---]  11 of 40  keyhop")
    }
}
