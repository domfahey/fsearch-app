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

    func clear() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
    }

    @Test func newestFirstDedupedCappedAtEight() {
        defer { clear() }
        let r = Recents(defaults: fresh(), exists: { _ in true })
        for i in 1...10 { r.opened("/f\(i)") }
        r.opened("/f5")
        #expect(r.paths == ["/f5", "/f10", "/f9", "/f8", "/f7", "/f6", "/f4", "/f3"])
    }

    @Test func goneFilesAreLeftOutAndOlderOnesFillIn() {
        defer { clear() }
        // Ten opened, the two newest since deleted: eight older ones still show.
        let r = Recents(defaults: fresh(), exists: { $0 != "/f10" && $0 != "/f9" })
        for i in 1...10 { r.opened("/f\(i)") }
        #expect(r.paths == (1...8).reversed().map { "/f\($0)" })
    }

    /// The panel draws a recent folder with a folder icon, a dotted one (v1.2) too, so the check that it still exists
    /// also says whether it is a folder.
    @Test func entriesSayWhichAreFolders() {
        defer { clear() }
        let r = Recents(defaults: fresh(), probe: { ["/d/v1.2": true, "/f.txt": false][$0] })
        for p in ["/gone", "/f.txt", "/d/v1.2"] { r.opened(p) }
        #expect(r.entries == [Recents.Entry(path: "/d/v1.2", isDirectory: true), Recents.Entry(path: "/f.txt", isDirectory: false)])
        #expect(r.paths == ["/d/v1.2", "/f.txt"])
    }

    @Test func persists() {
        defer { clear() }
        let d = fresh()
        Recents(defaults: d, exists: { _ in true }).opened("/a")
        #expect(Recents(defaults: d, exists: { _ in true }).paths == ["/a"])
    }

    @Test func emptyReopenBufferAndVerbatimPaths() {
        defer { clear() }
        let d = fresh()
        #expect(Recents(defaults: d, exists: { _ in true }).paths.isEmpty)
        let r = Recents(defaults: d, exists: { _ in true })
        r.opened("/a"); r.opened("/b"); r.opened("/c"); r.opened("/a"); r.opened("/a")
        #expect(r.paths == ["/a", "/c", "/b"])
        let unicode = "/Users/me/🏡 a b/ü.txt"
        r.opened(unicode)
        #expect(r.paths.first == unicode)

        // Keeps 16 in UserDefaults so 8 gone files still leave 8 older ones.
        let d2 = fresh()
        let live = Set((1...12).map { "/f\($0)" })
        let r2 = Recents(defaults: d2, exists: { live.contains($0) })
        for i in 1...20 { r2.opened("/f\(i)") }
        #expect(d2.stringArray(forKey: "recentPaths")?.count == 16)
        #expect(r2.paths == (5...12).reversed().map { "/f\($0)" })

        // All gone hides every row while keeping them persisted.
        let d3 = fresh()
        Recents(defaults: d3, exists: { _ in false }).opened("/a")
        #expect(Recents(defaults: d3, exists: { _ in false }).paths.isEmpty)
        #expect(Recents(defaults: d3, exists: { _ in true }).paths == ["/a"])
    }

    @Test func defaultExistenceCheckUsesTheFileSystem() throws {
        defer { clear() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-recents-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: real)
        let missing = dir.appendingPathComponent("missing.txt")
        let r = Recents(defaults: fresh())
        r.opened(real.path); r.opened(missing.path)
        #expect(r.paths == [real.path])
        try FileManager.default.removeItem(at: real)
        r.invalidate()
        #expect(r.paths.isEmpty, "a file deleted later drops out on the next check")
    }
}
