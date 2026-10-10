import Foundation
import Testing
@testable import FSearchKit

@Suite struct RecentsTests {
    /// Runs `body` against a throwaway suite, then removes the suite. The
    /// suite's objects are released inside `body`, before the cleanup: cfprefsd
    /// writes the emptied domain back when they go away, so the cleanup must
    /// come after that, and `removePersistentDomain` alone leaves an empty plist.
    func withSuite(_ body: (UserDefaults) -> Void) {
        let name = "fsk-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        body(d)
        d.removePersistentDomain(forName: name)
        d.synchronize()
        try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/Library/Preferences/\(name).plist")
    }

    @Test func newestFirstDedupedCappedAtEight() {
        withSuite { d in
            let r = Recents(defaults: d, exists: { _ in true })
            for i in 1...10 { r.opened("/f\(i)") }
            r.opened("/f5")
            #expect(r.paths == ["/f5", "/f10", "/f9", "/f8", "/f7", "/f6", "/f4", "/f3"])
        }
    }

    @Test func goneFilesAreLeftOut() {
        withSuite { d in
            let r = Recents(defaults: d, exists: { $0 != "/gone" })
            r.opened("/gone"); r.opened("/here")
            #expect(r.paths == ["/here"])
        }
    }

    @Test func persists() {
        withSuite { d in
            Recents(defaults: d, exists: { _ in true }).opened("/a")
            #expect(Recents(defaults: d, exists: { _ in true }).paths == ["/a"])
        }
    }
}
