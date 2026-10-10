import Foundation
import Testing

@testable import FSearchKit

@Suite struct DebugViewsTests {
    func rec(_ q: String, _ err: String? = nil) -> SearchLog.Record {
        SearchLog.Record(
            time: Date(timeIntervalSince1970: 1_800_000_000), query: q, mode: "names", results: 2, tookUs: 1500, roundTripMs: 2.25,
            error: err)
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

    @Test func bytesUseDecimalFileUnits() {
        // The text is locale-dependent, so compare against the formatter. What
        // this pins is the style: .file (1000-based, as Finder shows sizes), not .memory.
        let n: Int64 = 1_000_000
        #expect(DebugFormat.bytes(Int(n)) == ByteCountFormatter.string(fromByteCount: n, countStyle: .file))
        #expect(DebugFormat.bytes(Int(n)) != ByteCountFormatter.string(fromByteCount: n, countStyle: .memory))
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
        // Same size, new modification date: the date alone must change the stamp.
        let b = try #require(DebugFormat.FileStamp(of: f))
        try Data("a\ncc\n".utf8).write(to: f)
        let later = Date(timeIntervalSince1970: 1_900_000_000)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: f.path)
        let c = try #require(DebugFormat.FileStamp(of: f))
        #expect(c.size == b.size)
        #expect(c.modified == later)
        #expect(c != b)
    }

    @Test func tailReadsOnlyTheEndAndWholeLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-tail-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("daemon.log")
        let all = (0..<5000).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try all.write(to: f, atomically: true, encoding: .utf8)
        #expect(DebugFormat.tail(of: f, lines: 3, maxBytes: 1024) == "line 4997\nline 4998\nline 4999")
        // 45 bytes is four 10-byte lines plus the last 5 bytes ("4995\n") of a
        // fifth: that partial first line is dropped.
        #expect(DebugFormat.tail(of: f, lines: 100, maxBytes: 45) == "line 4996\nline 4997\nline 4998\nline 4999")
        #expect(DebugFormat.tail(of: dir.appendingPathComponent("nope"), lines: 3, maxBytes: 100) == "")
    }

    @Test func linesDropsBlanks() {
        #expect(DebugFormat.lines("a\n\nb\n") == ["a", "b"])
    }
}
