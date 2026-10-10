import Foundation
import Testing

@testable import FSearchKit

@Suite(.serialized) struct RecentsCoverageTests {
    static let suiteName = "mt.fsearchkit.tests.recents-cov"

    func fresh() -> UserDefaults {
        UserDefaults(suiteName: Self.suiteName)!.removePersistentDomain(forName: Self.suiteName)
        return UserDefaults(suiteName: Self.suiteName)!
    }
    func cleanup() { UserDefaults(suiteName: Self.suiteName)!.removePersistentDomain(forName: Self.suiteName) }

    @Test func emptyHasNoPaths() {
        defer { cleanup() }
        #expect(Recents(defaults: fresh(), exists: { _ in true }).paths.isEmpty)
    }

    @Test func reopeningMovesToFrontWithoutGrowing() {
        defer { cleanup() }
        let r = Recents(defaults: fresh(), exists: { _ in true })
        r.opened("/a"); r.opened("/b"); r.opened("/c")
        r.opened("/a"); r.opened("/a")
        #expect(r.paths == ["/a", "/c", "/b"])
    }

    @Test func keepsSixteenSoGoneFilesStillLeaveEight() {
        defer { cleanup() }
        let d = fresh()
        let live = Set((1...12).map { "/f\($0)" })
        let r = Recents(defaults: d, exists: { live.contains($0) })
        for i in 1...20 { r.opened("/f\(i)") }
        #expect(d.stringArray(forKey: "recentPaths")?.count == 16)
        // f20...f13 are gone; the buffer still holds f12...f5.
        #expect(r.paths == (5...12).reversed().map { "/f\($0)" })
    }

    @Test func allGoneIsEmptyButStillRemembered() {
        defer { cleanup() }
        let d = fresh()
        Recents(defaults: d, exists: { _ in false }).opened("/a")
        #expect(Recents(defaults: d, exists: { _ in false }).paths.isEmpty)
        #expect(Recents(defaults: d, exists: { _ in true }).paths == ["/a"])
    }

    @Test func defaultExistenceCheckUsesTheFileSystem() throws {
        defer { cleanup() }
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

    @Test func pathsAreStoredVerbatim() {
        defer { cleanup() }
        let p = "/Users/me/🏡 a b/ü.txt"
        let r = Recents(defaults: fresh(), exists: { _ in true })
        r.opened(p)
        #expect(r.paths == [p])
    }
}
