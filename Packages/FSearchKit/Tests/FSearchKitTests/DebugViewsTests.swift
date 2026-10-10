import Foundation
import Testing
@testable import FSearchKit

@Suite struct DebugViewsTests {
    func rec(_ q: String, _ err: String? = nil) -> SearchLog.Record {
        SearchLog.Record(time: Date(timeIntervalSince1970: 1_800_000_000), query: q, mode: "names", results: 2, tookUs: 1500, roundTripMs: 2.25, error: err)
    }

    @Test func filterIsNewestFirstAndCaseInsensitive() {
        let rows = [rec("Alpha"), rec("beta"), rec("alphabet")]
        #expect(DebugFormat.shown(rows, filter: "").map(\.query) == ["alphabet", "beta", "Alpha"])
        #expect(DebugFormat.shown(rows, filter: "ALPHA").map(\.query) == ["alphabet", "Alpha"])
        #expect(DebugFormat.shown(rows, filter: "zzz").isEmpty)
    }

    @Test func jsonlExportRoundTrips() throws {
        let data = DebugFormat.jsonl([rec("a"), rec("b", "bad regex")])
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        #expect(lines.count == 2)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        #expect(try dec.decode(SearchLog.Record.self, from: Data(lines[1].utf8)) == rec("b", "bad regex"))
        #expect(DebugFormat.jsonl([]).isEmpty)
    }

    @Test func formatsTimings() {
        #expect(DebugFormat.daemonMs(1500) == "1.50 ms")
        #expect(DebugFormat.daemonMs(nil) == "–")
        #expect(DebugFormat.roundTrip(12.34) == "12.3 ms")
    }

    @Test func formatsBytes() {
        // Same formatter and style, so the result holds in any locale.
        for n in [0, 1_000_000, Int.max] {
            let want = ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
            #expect(DebugFormat.bytes(n) == want)
            #expect(!want.isEmpty)
        }
    }

    @Test func dataDirIsTheSocketsFolder() {
        #expect(DebugFormat.dataDir(socketPath: "/tmp/fsk-x/fsearch.sock").path == "/tmp/fsk-x")
    }

    @Test func fileStampChangesWithTheFile() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-stamp-\(UUID())")
        defer { try? FileManager.default.removeItem(at: f) }
        #expect(DebugFormat.FileStamp(of: f) == nil)
        try Data("a\n".utf8).write(to: f)
        let a = try #require(DebugFormat.FileStamp(of: f))
        #expect(a.size == 2)
        #expect(DebugFormat.FileStamp(of: f) == a)
        try Data("a\nbb\n".utf8).write(to: f)
        #expect(DebugFormat.FileStamp(of: f) != a)
    }

    @Test func tailReadsOnlyTheEndAndWholeLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-tail-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("daemon.log")
        let all = (0..<5000).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try all.write(to: f, atomically: true, encoding: .utf8)
        #expect(DebugFormat.tail(of: f, lines: 3, maxBytes: 1024) == "line 4997\nline 4998\nline 4999")
        let small = DebugFormat.tail(of: f, lines: 100, maxBytes: 40)
        #expect(small.split(separator: "\n").allSatisfy { $0.hasPrefix("line ") })
        #expect(small.hasSuffix("line 4999"))
        #expect(DebugFormat.tail(of: dir.appendingPathComponent("nope"), lines: 3, maxBytes: 100) == "")
    }

    @Test func linesDropsBlanks() {
        #expect(DebugFormat.lines("a\n\nb\n") == ["a", "b"])
    }
}
