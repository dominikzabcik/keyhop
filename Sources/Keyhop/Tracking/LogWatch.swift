#if os(macOS)
import CoreServices
import Foundation

/// Watches the log trees the feeds read and fires once writes settle, so new usage shows up
/// within seconds instead of on the next poll. Directory-granularity FSEvents are enough: the
/// ingest is incremental anyway, so one callback per burst of writes is all that's needed.
final class LogWatch {
    private let paths: [String]
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "app.keyhop.logwatch")
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    /// `paths` must exist when the watch starts; a root that appears later needs a new watch.
    init(paths: [String], debounce: TimeInterval = 1.0, onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit { stop() }

    @discardableResult
    func start() -> Bool {
        guard stream == nil, !paths.isEmpty else { return false }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<LogWatch>.fromOpaque(info).takeUnretainedValue().schedule()
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return false }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return false
        }
        return true
    }

    func stop() {
        queue.sync {
            pending?.cancel()
            pending = nil
        }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Coalesces a burst of writes into one callback, `debounce` after the last event.
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
#endif
