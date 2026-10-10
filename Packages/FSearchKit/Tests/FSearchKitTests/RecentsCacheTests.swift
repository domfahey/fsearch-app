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
    func exists(_ p: String) -> Bool { lock.withLock { _checks += 1; return !_gone.contains(p) } }
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
    static let suiteName = "mt.fsearchkit.tests.recents.cache"
    func fresh() -> UserDefaults {
        UserDefaults(suiteName: Self.suiteName)!.removePersistentDomain(forName: Self.suiteName)
        return UserDefaults(suiteName: Self.suiteName)!
    }

    @Test func repeatedReadsCheckOnce() {
        let probe = ExistsProbe(), clock = TestClock()
        let r = Recents(defaults: fresh(), exists: probe.exists, now: { clock.now })
        for i in 1...3 { r.opened("/f\(i)") }
        _ = r.paths
        let once = probe.checks
        for _ in 0..<50 { _ = r.paths }
        #expect(once == 3 && probe.checks == once)
    }

    @Test func openingRechecks() {
        let probe = ExistsProbe(), clock = TestClock()
        let r = Recents(defaults: fresh(), exists: probe.exists, now: { clock.now })
        r.opened("/a")
        #expect(r.paths == ["/a"])
        r.opened("/b")
        #expect(r.paths == ["/b", "/a"])
    }

    @Test func invalidateRechecks() {
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
        let probe = ExistsProbe(), clock = TestClock()
        let r = Recents(defaults: fresh(), exists: probe.exists, now: { clock.now })
        r.opened("/a"); r.opened("/b")
        _ = r.paths
        probe.remove("/a")
        clock.advance(Recents.recheckAfter + 0.1)
        #expect(r.paths == ["/b"])
    }
}
