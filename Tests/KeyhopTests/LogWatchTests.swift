#if os(macOS)
import XCTest
@testable import Keyhop

final class LogWatchTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-watch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAWriteInAWatchedTreeFiresOnce() throws {
        let fired = expectation(description: "change reported")
        fired.assertForOverFulfill = false
        let watch = LogWatch(paths: [directory.path], debounce: 0.2) { fired.fulfill() }
        defer { watch.stop() }
        XCTAssertTrue(watch.start())

        try Data("{\"usage\": 1}\n".utf8).write(to: directory.appendingPathComponent("session.jsonl"))
        wait(for: [fired], timeout: 10)
    }

    func testABurstOfWritesCoalescesIntoOneCallback() throws {
        let counter = Counter()
        // The debounce must outlast FSEvents' own 0.5s batching, or each batch fires separately.
        let watch = LogWatch(paths: [directory.path], debounce: 1.0) { counter.add() }
        defer { watch.stop() }
        XCTAssertTrue(watch.start())

        let file = directory.appendingPathComponent("burst.jsonl")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        for _ in 0..<5 {
            try handle.write(contentsOf: Data("line\n".utf8))
            Thread.sleep(forTimeInterval: 0.05)
        }
        try handle.close()

        // Long enough for FSEvents latency plus the debounce to pass twice over.
        let settled = expectation(description: "burst settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { settled.fulfill() }
        wait(for: [settled], timeout: 10)
        XCTAssertEqual(counter.value, 1)
    }

    func testStartNeedsAPath() {
        XCTAssertFalse(LogWatch(paths: []) {}.start())
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func add() { lock.withLock { count += 1 } }
    }
}
#endif
