import Foundation
import Testing
@testable import FSearchKit

/// All tests share one defaults suite, which is cleared at the start of each
/// test, so at most one plist for it exists. The suite is serialized so the
/// tests never touch it at the same time.
@Suite(.serialized) struct RecentsTests {
    static let suiteName = "mt.fsearchkit.tests.recents"

    /// A clean suite for one test. Removing the domain first wipes what the
    /// previous test left behind.
    func fresh() -> UserDefaults {
        UserDefaults(suiteName: Self.suiteName)!.removePersistentDomain(forName: Self.suiteName)
        return UserDefaults(suiteName: Self.suiteName)!
    }

    @Test func newestFirstDedupedCappedAtEight() {
        let r = Recents(defaults: fresh(), exists: { _ in true })
        for i in 1...10 { r.opened("/f\(i)") }
        r.opened("/f5")
        #expect(r.paths == ["/f5", "/f10", "/f9", "/f8", "/f7", "/f6", "/f4", "/f3"])
    }

    @Test func goneFilesAreLeftOut() {
        let r = Recents(defaults: fresh(), exists: { $0 != "/gone" })
        r.opened("/gone"); r.opened("/here")
        #expect(r.paths == ["/here"])
    }

    @Test func persists() {
        let d = fresh()
        Recents(defaults: d, exists: { _ in true }).opened("/a")
        #expect(Recents(defaults: d, exists: { _ in true }).paths == ["/a"])
    }
}
