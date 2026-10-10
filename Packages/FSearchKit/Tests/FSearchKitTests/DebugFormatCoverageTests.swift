import Foundation
import Testing
@testable import FSearchKit

@Suite struct DebugFormatCoverageTests {
    func tmp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-dfc-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    func rec(_ q: String, ms: Double = 1) -> SearchLog.Record {
        SearchLog.Record(time: Date(timeIntervalSince1970: 1_800_000_000), query: q, mode: "names", results: 0, tookUs: nil, roundTripMs: ms, error: nil)
    }

    @Test func timingEdgeValues() {
        #expect(DebugFormat.daemonMs(0) == "0.00 ms")
        #expect(DebugFormat.daemonMs(1) == "0.00 ms")
        #expect(DebugFormat.daemonMs(999) == "1.00 ms")
        #expect(DebugFormat.daemonMs(UInt64.max).hasSuffix(" ms"))
        #expect(DebugFormat.roundTrip(0) == "0.0 ms")
        #expect(DebugFormat.roundTrip(0.04) == "0.0 ms")
        #expect(DebugFormat.roundTrip(1234.56) == "1234.6 ms")
        #expect(DebugFormat.roundTrip(-1) == "-1.0 ms")
    }

    @Test func shownOnEmptyAndFilterEdges() {
        #expect(DebugFormat.shown([], filter: "").isEmpty)
        #expect(DebugFormat.shown([], filter: "x").isEmpty)
        let rows = [rec("Straße"), rec("café"), rec("a b")]
        #expect(DebugFormat.shown(rows, filter: "CAFÉ").map(\.query) == ["café"])
        #expect(DebugFormat.shown(rows, filter: " ").map(\.query) == ["a b"], "a space filter is a substring match")
    }

    @Test func jsonlSkipsRecordsThatCannotBeEncoded() {
        let data = DebugFormat.jsonl([rec("a"), rec("nan", ms: .nan), rec("b")])
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"a\"") && lines[1].contains("\"b\""))
    }

    @Test func linesEdgeCases() {
        #expect(DebugFormat.lines("").isEmpty)
        #expect(DebugFormat.lines("\n\n").isEmpty)
        #expect(DebugFormat.lines("one") == ["one"])
        #expect(DebugFormat.lines(" \nx") == [" ", "x"], "whitespace-only lines are not blank")
    }

    @Test func dataDirOfBareAndRootSockets() {
        #expect(DebugFormat.dataDir(socketPath: "/fsearch.sock").path == "/")
        #expect(DebugFormat.dataDir(socketPath: "/a/b/c/x.sock").path == "/a/b/c")
    }

    @Test func fileStampOfEmptyFileAndDirectory() throws {
        let dir = try tmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("empty")
        try Data().write(to: f)
        let s = try #require(DebugFormat.FileStamp(of: f))
        #expect(s.size == 0 && s.modified != nil)
        #expect(DebugFormat.FileStamp(of: dir) != nil)
    }

    @Test func tailOfEmptyAndTinyFiles() throws {
        let dir = try tmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("log")
        try Data().write(to: f)
        #expect(DebugFormat.tail(of: f, lines: 5) == "")
        try "only".write(to: f, atomically: true, encoding: .utf8)
        #expect(DebugFormat.tail(of: f, lines: 5) == "only", "no trailing newline, smaller than the window")
        try "a\nb\nc\n".write(to: f, atomically: true, encoding: .utf8)
        #expect(DebugFormat.tail(of: f, lines: 2) == "b\nc")
        #expect(DebugFormat.tail(of: f, lines: 0) == "")
        #expect(DebugFormat.tail(of: f, lines: 10) == "a\nb\nc")
    }

    @Test func tailWithAWindowHoldingNoNewlineIsEmpty() throws {
        let dir = try tmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("log")
        try (String(repeating: "x", count: 500) + "\n").write(to: f, atomically: true, encoding: .utf8)
        // 10 bytes from the end: "xxxxxxxxx\n" has its newline last, so only a
        // partial line precedes it and nothing complete follows.
        #expect(DebugFormat.tail(of: f, lines: 3, maxBytes: 5) == "")
        #expect(DebugFormat.tail(of: f, lines: 3, maxBytes: 1000).count == 500)
    }

    @Test func tailOfADirectoryOrMissingPathIsEmpty() throws {
        let dir = try tmp(); defer { try? FileManager.default.removeItem(at: dir) }
        #expect(DebugFormat.tail(of: dir, lines: 3) == "")
        #expect(DebugFormat.tail(of: dir.appendingPathComponent("nope"), lines: 3) == "")
    }

    @Test func tailWindowExactlyTheFileSizeKeepsTheFirstLine() throws {
        let dir = try tmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("log")
        try "first\nsecond\n".write(to: f, atomically: true, encoding: .utf8)
        #expect(DebugFormat.tail(of: f, lines: 9, maxBytes: 13) == "first\nsecond")
        #expect(DebugFormat.tail(of: f, lines: 9, maxBytes: 12) == "second", "one byte short drops the cut first line")
    }
}
