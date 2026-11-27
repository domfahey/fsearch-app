import Foundation
import Testing

@testable import FSearchKit

/// Counts existence checks, which can block on a slow network mount.
final class ExistsProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _checks = 0
    private var _gone: Set<String> = []
    var checks: Int { lock.withLock { _checks } }
    func remove(_ p: String) { lock.withLock { _ = _gone.insert(p) } }
    func exists(_ p: String) -> Bool {
        lock.withLock {
            _checks += 1; return !_gone.contains(p)
        }
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { t } }
    func advance(_ s: TimeInterval) { lock.withLock { t += s } }
}

/// Redraws read `paths` many times a second: the files are checked once, then
/// again only after the list changes, `invalidate()`, or `Recents.recheckAfter`.
@Suite(.serialized) struct RecentsCacheTests {
    static let suiteName = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mt.fsearchkit.tests.recents.cache").path
    func fresh() -> UserDefaults {
        UserDefaults(suiteName: Self.suiteName)!.removePersistentDomain(forName: Self.suiteName)
        return UserDefaults(suiteName: Self.suiteName)!
    }

    func clear() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        try? FileManager.default.removeItem(atPath: Self.suiteName + ".plist")
    }

    @Test func repeatedReadsCheckOnce() {
        defer { clear() }
        let probe = ExistsProbe(), clock = TestClock()
        let r = Recents(defaults: fresh(), exists: probe.exists, now: { clock.now })
        for i in 1...3 { r.opened("/f\(i)") }
        _ = r.paths
        let once = probe.checks
        for _ in 0..<50 { _ = r.paths }
        #expect(once == 3 && probe.checks == once)
    }

    @Test func openingRechecks() {
        defer { clear() }
        let probe = ExistsProbe(), clock = TestClock()
        let r = Recents(defaults: fresh(), exists: probe.exists, now: { clock.now })
        r.opened("/a")
        #expect(r.paths == ["/a"])
        r.opened("/b")
        #expect(r.paths == ["/b", "/a"])
    }

    @Test func invalidateRechecks() {
        defer { clear() }
        let probe = ExistsProbe(), clock = TestClock()
        let r = Recents(defaults: fresh(), exists: probe.exists, now: { clock.now })
        r.opened("/a"); r.opened("/b")
        #expect(r.paths == ["/b", "/a"])
        probe.remove("/b")  // trashed from the panel
        #expect(r.paths == ["/b", "/a"], "cached")
        r.invalidate()
        #expect(r.paths == ["/a"])
    }

    @Test func staleCacheIsRechecked() {
        defer { clear() }
        let probe = ExistsProbe(), clock = TestClock()
        let r = Recents(defaults: fresh(), exists: probe.exists, now: { clock.now })
        r.opened("/a"); r.opened("/b")
        _ = r.paths
        probe.remove("/a")
        clock.advance(Recents.recheckAfter + 0.1)
        #expect(r.paths == ["/b"])
    }

    @Test func invalidateDuringInFlightProbeDoesNotCacheStaleResult() {
        defer { clear() }
        let clock = TestClock()
        let entered = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)
        let probe = ExistsProbe()
        let recents = Recents(
            defaults: fresh(),
            exists: { path in
                if probe.checks == 0 {
                    entered.signal()
                    _ = proceed.wait(timeout: .now() + 2)
                }
                return probe.exists(path)
            }, now: { clock.now })
        recents.opened("/a")
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = recents.paths
            done.signal()
        }
        #expect(entered.wait(timeout: .now() + 2) == .success)
        probe.remove("/a")
        recents.invalidate()
        proceed.signal()
        #expect(done.wait(timeout: .now() + 2) == .success)
        // The stale probe must not have poisoned the cache: the next read re-probes and sees /a gone.
        #expect(recents.paths.isEmpty)
    }
}
